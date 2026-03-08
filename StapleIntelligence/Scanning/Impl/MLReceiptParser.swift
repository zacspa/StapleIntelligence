//
//  MLReceiptParser.swift
//  StapleIntelligence
//

import CoreML
import UIKit
import Foundation
import CoreGraphics

// MARK: - MLReceiptParser

/// On-device receipt token classifier backed by a 4-bit palettized LayoutLMv3 Core ML model
/// (~64 MB).
///
/// Classifies each OCR token into a `ReceiptFieldLabel` category via per-token logit argmax,
/// then aggregates to per-line labels (majority vote, ignoring `.ignore` predictions) and
/// assembles a `ParsedReceipt` using the same spatial pairing logic as `TemplateParser`.
///
/// ## Pipeline position
///
/// Wire into `ReceiptsView.runPipeline` as a third strategy. After the generic `ReceiptParser`
/// and any `TemplateParser` run, call `MLReceiptParser.parse(ocrLines:image:)` and keep the
/// result with the highest `parseConfidence`.
///
/// ## Setup (one-time, manual Xcode step)
///
/// Drag `Scanning/ReceiptClassifier.mlpackage` into Xcode and add it to the
/// `StapleIntelligence` target so Xcode compiles it and includes it in the bundle.
/// The JSON resource files in `Scanning/Resources/` are included automatically via
/// the `PBXFileSystemSynchronizedRootGroup` configuration.
/// `MLModel.prediction(from:)` is thread-safe; the struct is safe to send across actor
/// boundaries even though it holds a reference-type `MLModel`.
struct MLReceiptParser: @unchecked Sendable {

    private static let maxSeqLen = 512
    private static let imageSize = 224

    private let model: MLModel
    private let tokenizer: ByteLevelBPETokenizer
    private let labelMap: [Int: ReceiptFieldLabel]
    private let numLabels: Int

    // MARK: - Init

    /// Throws `MLParserError` if the `.mlpackage` or JSON resources are absent from the bundle.
    init() throws {
        // ReceiptClassifier.mlpackage compiles to ReceiptClassifier.mlmodelc in the bundle.
        guard let modelURL = Bundle.main.url(forResource: "ReceiptClassifier", withExtension: "mlmodelc")
                          ?? Bundle.main.url(forResource: "ReceiptClassifier", withExtension: "mlpackage") else {
            throw MLParserError.missingModel
        }
        let config = MLModelConfiguration()
        // ANE does not support int32 vector inputs (input_ids, attention_mask, bbox).
        // cpuAndGPU routes integer-input ops to GPU/CPU and avoids the
        // "Cannot retrieve vector from IRValue format int32" ANE error.
        config.computeUnits = .cpuAndGPU
        model = try MLModel(contentsOf: modelURL, configuration: config)

        guard let tokURL = Bundle.main.url(forResource: "receipt_tokenizer", withExtension: "json") else {
            throw MLParserError.missingResource("receipt_tokenizer.json")
        }
        tokenizer = try ByteLevelBPETokenizer(contentsOf: tokURL)

        guard let labelURL = Bundle.main.url(forResource: "receipt_label_map", withExtension: "json"),
              let data = try? Data(contentsOf: labelURL),
              let raw = try? JSONDecoder().decode([String: String].self, from: data) else {
            throw MLParserError.missingResource("receipt_label_map.json")
        }
        labelMap = raw.reduce(into: [:]) { dict, pair in
            if let id = Int(pair.key), let label = ReceiptFieldLabel(rawValue: pair.value) {
                dict[id] = label
            }
        }
        numLabels = labelMap.keys.max().map { $0 + 1 } ?? raw.count
    }

    // MARK: - Parse

    /// Returns `nil` if inference fails or no OCR lines have bounding boxes.
    func parse(ocrLines: [OCRLine], image: UIImage) -> ParsedReceipt? {
        guard !ocrLines.isEmpty else { return nil }

        let (inputIds, attentionMask, bboxFlat, lineTokenRanges) = buildTextInputs(ocrLines: ocrLines)
        guard let pixelValues = imageToPixelValues(image) else { return nil }
        guard let logits = runInference(inputIds: inputIds,
                                        attentionMask: attentionMask,
                                        bboxFlat: bboxFlat,
                                        pixelValues: pixelValues) else { return nil }

        // Aggregate per-token predictions → per-line dominant label
        var labeledLines = [ReceiptFieldLabel: [OCRLine]]()
        for (lineIdx, line) in ocrLines.enumerated() {
            guard lineIdx < lineTokenRanges.count else { continue }
            let range = lineTokenRanges[lineIdx]
            guard !range.isEmpty else { continue }

            var counts = [ReceiptFieldLabel: Int]()
            for tokenIdx in range {
                guard tokenIdx * numLabels + numLabels <= logits.count else { continue }
                let labelId = argmax(logits: logits, tokenIndex: tokenIdx, numLabels: numLabels)
                let label   = labelMap[labelId] ?? .ignore
                if label != .ignore { counts[label, default: 0] += 1 }
            }
            if let dominant = counts.max(by: { $0.value < $1.value })?.key {
                labeledLines[dominant, default: []].append(line)
            }
        }

        let rawText = ocrLines.map(\.text).joined(separator: "\n")
        return extractParsedReceipt(from: labeledLines, rawOcrText: rawText)
    }

    // MARK: - Text input construction

    private func buildTextInputs(ocrLines: [OCRLine]) -> (
        inputIds: [Int32],
        attentionMask: [Int32],
        bboxFlat: [Int32],
        lineTokenRanges: [Range<Int>]
    ) {
        let maxLen = Self.maxSeqLen
        var inputIds   = [Int32]()
        var bboxFlat   = [Int32]()
        var lineRanges = [Range<Int>]()

        // [CLS]
        inputIds.append(Int32(tokenizer.clsId))
        bboxFlat.append(contentsOf: [0, 0, 0, 0])

        for line in ocrLines {
            let startIdx = inputIds.count
            let box = visionBboxToLayoutLM(line.boundingBox)
            let (tokenIds, _) = tokenizer.encode(line.text)
            for tid in tokenIds {
                guard inputIds.count < maxLen - 1 else { break }
                inputIds.append(Int32(tid))
                bboxFlat.append(contentsOf: box)
            }
            let endIdx = min(inputIds.count, maxLen - 1)
            lineRanges.append(startIdx..<endIdx)
            if inputIds.count >= maxLen - 1 { break }
        }

        // [SEP]
        inputIds.append(Int32(tokenizer.sepId))
        bboxFlat.append(contentsOf: [1000, 1000, 1000, 1000])

        let realLen = inputIds.count
        while inputIds.count < maxLen {
            inputIds.append(Int32(tokenizer.padId))
            bboxFlat.append(contentsOf: [0, 0, 0, 0])
        }

        let attentionMask = (0..<maxLen).map { Int32($0 < realLen ? 1 : 0) }
        return (inputIds, attentionMask, bboxFlat, lineRanges)
    }

    /// Converts a Vision-normalized bounding box (bottom-left origin) to
    /// LayoutLMv3 format (top-left origin, 0–1000 range): [x0, y0, x1, y1].
    private func visionBboxToLayoutLM(_ bbox: CGRect?) -> [Int32] {
        guard let b = bbox else { return [0, 0, 0, 0] }
        return [
            Int32(b.minX * 1000),
            Int32((1 - b.maxY) * 1000),   // Y-flip: Vision BL → display TL
            Int32(b.maxX * 1000),
            Int32((1 - b.minY) * 1000),
        ]
    }

    // MARK: - Image preprocessing

    /// Resizes to 224×224 and normalizes to [-1, 1] in CHW order.
    private func imageToPixelValues(_ image: UIImage) -> [Float]? {
        let s = Self.imageSize
        let size = CGSize(width: s, height: s)
        UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
        image.draw(in: CGRect(origin: .zero, size: size))
        let resized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        guard let cg = resized?.cgImage else { return nil }
        var raw = [UInt8](repeating: 0, count: s * s * 4)
        let cs  = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &raw, width: s, height: s,
                                  bitsPerComponent: 8, bytesPerRow: s * 4,
                                  space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: s, height: s))

        // RGBA bytes → CHW float32, normalized (pixel/127.5 - 1)
        var pixels = [Float](repeating: 0, count: 3 * s * s)
        for i in 0..<(s * s) {
            let p = i * 4
            pixels[0 * s * s + i] = Float(raw[p])     / 127.5 - 1.0  // R
            pixels[1 * s * s + i] = Float(raw[p + 1]) / 127.5 - 1.0  // G
            pixels[2 * s * s + i] = Float(raw[p + 2]) / 127.5 - 1.0  // B
        }
        return pixels
    }

    // MARK: - Inference

    private func runInference(
        inputIds: [Int32],
        attentionMask: [Int32],
        bboxFlat: [Int32],
        pixelValues: [Float]
    ) -> [Float]? {
        let seq = Self.maxSeqLen
        let img = Self.imageSize

        guard let idArr  = try? MLMultiArray(shape: [1, seq as NSNumber],          dataType: .int32),
              let mskArr = try? MLMultiArray(shape: [1, seq as NSNumber],          dataType: .int32),
              let bxArr  = try? MLMultiArray(shape: [1, seq as NSNumber, 4],       dataType: .int32),
              let pxArr  = try? MLMultiArray(shape: [1, 3, img as NSNumber, img as NSNumber], dataType: .float32)
        else { return nil }

        for i in 0..<seq {
            idArr[i]  = NSNumber(value: inputIds[i])
            mskArr[i] = NSNumber(value: attentionMask[i])
        }
        for i in 0..<(seq * 4) {
            bxArr[i] = NSNumber(value: bboxFlat[i])
        }
        for i in 0..<pixelValues.count {
            pxArr[i] = NSNumber(value: pixelValues[i])
        }

        guard let provider = try? MLDictionaryFeatureProvider(dictionary: [
            "input_ids":      MLFeatureValue(multiArray: idArr),
            "attention_mask": MLFeatureValue(multiArray: mskArr),
            "bbox":           MLFeatureValue(multiArray: bxArr),
            "pixel_values":   MLFeatureValue(multiArray: pxArr),
        ]) else { return nil }

        guard let output = try? model.prediction(from: provider),
              let logitArray = output.featureValue(for: "logits")?.multiArrayValue
        else { return nil }

        let total = seq * numLabels
        var logits = [Float](repeating: 0, count: total)
        for i in 0..<min(total, logitArray.count) {
            logits[i] = logitArray[i].floatValue
        }
        return logits
    }

    private func argmax(logits: [Float], tokenIndex: Int, numLabels: Int) -> Int {
        let offset = tokenIndex * numLabels
        var bestIdx = 0
        var bestVal = logits[offset]
        for i in 1..<numLabels {
            if logits[offset + i] > bestVal {
                bestVal = logits[offset + i]
                bestIdx = i
            }
        }
        return bestIdx
    }

    // MARK: - ParsedReceipt extraction

    /// Mirrors `TemplateParser`'s extraction logic, accepting the same
    /// `[ReceiptFieldLabel: [OCRLine]]` bucket structure.
    private func extractParsedReceipt(
        from labeledLines: [ReceiptFieldLabel: [OCRLine]],
        rawOcrText: String
    ) -> ParsedReceipt {
        let merchantName: String? = labeledLines[.merchantName].flatMap { lines in
            let j = lines.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespaces)
            return j.isEmpty ? nil : j
        }

        let purchaseDate: Date? = labeledLines[.purchaseDate].flatMap { lines in
            extractDate(from: lines.map(\.text).joined(separator: " "))
        }

        let nameLines     = (labeledLines[.lineItemName]  ?? []).sorted { midY($0) > midY($1) }
        let priceLines    = (labeledLines[.lineItemPrice] ?? []).sorted { midY($0) > midY($1) }
        let discountLines = (labeledLines[.discount]      ?? []).sorted { midY($0) > midY($1) }
        let skuLines      = (labeledLines[.sku]           ?? []).sorted { midY($0) > midY($1) }
        let lineItems     = buildLineItems(nameLines: nameLines,
                                           priceLines: priceLines,
                                           discountLines: discountLines,
                                           skuLines: skuLines)

        let subtotal = extractDecimal(from: labeledLines[.subtotal] ?? [])
        let tax      = extractDecimal(from: labeledLines[.tax]      ?? [])
        let total    = extractDecimal(from: labeledLines[.total]    ?? [])

        var score = 0.0
        for f in [ReceiptFieldLabel.merchantName, .purchaseDate, .total] {
            if labeledLines[f] != nil { score += 1 }
        }
        score += lineItems.isEmpty ? 0 : (lineItems.count >= 3 ? 2 : 1)
        let confidence = score / 5.0

        let reconciliation: ReconciliationStatus = {
            guard let sub = subtotal else { return .unverified }
            let sum = lineItems.reduce(Decimal.zero) { $0 + $1.lineTotal }
            return abs(sum - sub) <= Decimal(string: "0.02")! ? .reconciled : .discrepancy
        }()

        return ParsedReceipt(
            rawOcrText: rawOcrText,
            merchantName: merchantName,
            purchaseDate: purchaseDate,
            lineItems: lineItems,
            subtotal: subtotal,
            tax: tax,
            total: total,
            parseConfidence: confidence,
            reconciliationStatus: reconciliation
        )
    }

    private func midY(_ line: OCRLine) -> CGFloat {
        line.boundingBox?.midY ?? 0
    }

    private func buildLineItems(
        nameLines: [OCRLine],
        priceLines: [OCRLine],
        discountLines: [OCRLine],
        skuLines: [OCRLine]
    ) -> [ParsedLineItem] {
        var remaining    = priceLines
        var remainingSKUs = skuLines
        var items        = [ParsedLineItem]()

        for nameLine in nameLines {
            let raw = nameLine.text.trimmingCharacters(in: .whitespaces)
            guard !raw.isEmpty else { continue }
            let canonical = ReceiptParser.canonicalize(raw)
            let yMid = midY(nameLine)

            if let (idx, priceLine) = remaining.enumerated()
                .min(by: { abs(midY($0.element) - yMid) < abs(midY($1.element) - yMid) }),
               let price = parsePrice(from: priceLine.text)
            {
                remaining.remove(at: idx)
                let sku: String?
                if let (skuIdx, skuLine) = remainingSKUs.enumerated()
                    .min(by: { abs(midY($0.element) - yMid) < abs(midY($1.element) - yMid) }) {
                    remainingSKUs.remove(at: skuIdx)
                    sku = skuLine.text.trimmingCharacters(in: .whitespaces)
                                      .components(separatedBy: .whitespaces).first
                } else {
                    sku = ReceiptParser.extractSKU(from: raw)
                }
                items.append(ParsedLineItem(
                    rawName: raw, canonicalName: canonical,
                    itemType: .byCount(count: 1), unitPrice: nil,
                    lineTotal: price, isDiscount: false,
                    confidence: nameLine.confidence, taxCode: nil,
                    sku: sku, boundingBox: nameLine.boundingBox
                ))
            }
        }

        for discLine in discountLines {
            let raw = discLine.text.trimmingCharacters(in: .whitespaces)
            guard !raw.isEmpty, let absPrice = parsePrice(from: raw) else { continue }
            items.append(ParsedLineItem(
                rawName: raw, canonicalName: ReceiptParser.canonicalize(raw),
                itemType: .byCount(count: 1), unitPrice: nil,
                lineTotal: -abs(absPrice), isDiscount: true,
                confidence: discLine.confidence, taxCode: nil,
                sku: nil, boundingBox: discLine.boundingBox
            ))
        }
        return items
    }

    // Shared helpers (mirrors TemplateParser)

    private func extractDate(from text: String) -> Date? {
        guard let m = try? ReceiptParser.datePattern.firstMatch(in: text),
              let mo = Int(String(m.1)), let d = Int(String(m.2)), var y = Int(String(m.3))
        else { return nil }
        if y < 100 { y += y < 50 ? 2000 : 1900 }
        var comps = DateComponents()
        comps.year = y; comps.month = mo; comps.day = d
        return Calendar(identifier: .gregorian).date(from: comps)
    }

    private func extractDecimal(from lines: [OCRLine]) -> Decimal? {
        lines.lazy.compactMap { parsePrice(from: $0.text) }.first
    }

    private func parsePrice(from text: String) -> Decimal? {
        let t = text.trimmingCharacters(in: .whitespaces)
        if (try? ReceiptParser.standalonePricePattern.wholeMatch(in: t)) != nil {
            return Decimal(string: t.replacingOccurrences(of: ",", with: "."),
                           locale: Locale(identifier: "en_US_POSIX"))
        }
        if let m = try? ReceiptParser.priceWithCodePattern.firstMatch(in: t) {
            return Decimal(string: String(m.1).replacingOccurrences(of: ",", with: "."),
                           locale: Locale(identifier: "en_US_POSIX"))
        }
        if let m = try? ReceiptParser.dollarAmountPattern.firstMatch(in: t) {
            return Decimal(string: String(m.1).replacingOccurrences(of: ",", with: "."),
                           locale: Locale(identifier: "en_US_POSIX"))
        }
        for part in t.components(separatedBy: .whitespaces).reversed() {
            let p = part.replacingOccurrences(of: ",", with: ".")
            if let val = Decimal(string: p, locale: Locale(identifier: "en_US_POSIX")), val > 0 { return val }
        }
        return nil
    }
}

// MARK: - Error

enum MLParserError: Error {
    case missingModel
    case missingResource(String)
    case inferenceFailure
}

// MARK: - ByteLevelBPETokenizer

/// Minimal byte-level BPE tokenizer compatible with RoBERTa / LayoutLMv3.
///
/// Loads vocabulary and merge rules from a `tokenizer.json` file (HuggingFace format).
/// Implements GPT-2's byte-to-unicode encoding so that any UTF-8 input can be tokenized
/// without unknown-byte failures. The `encode(_:)` method adds a 'Ġ' space prefix to
/// every word after the first, matching the `add_prefix_space: true` pre-tokenizer config.
private struct ByteLevelBPETokenizer {

    private let vocab: [String: Int]
    private let mergeRanks: [MergePair: Int]
    private let byteEncoder: [UInt8: String]    // byte → unicode char string

    let clsId: Int    // <s>
    let padId: Int    // <pad>
    let sepId: Int    // </s>
    let unkId: Int    // <unk>

    // MARK: - Init

    init(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(TokenizerFile.self, from: data)

        vocab = decoded.model.vocab

        var ranks = [MergePair: Int]()
        for (i, merge) in decoded.model.merges.enumerated() {
            let parts = merge.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            ranks[MergePair(first: parts[0], second: parts[1])] = i
        }
        mergeRanks = ranks
        byteEncoder = Self.buildByteEncoder()

        clsId = vocab["<s>"]    ?? 0
        padId = vocab["<pad>"]  ?? 1
        sepId = vocab["</s>"]   ?? 2
        unkId = vocab["<unk>"]  ?? 3
    }

    // MARK: - Encoding

    func encode(_ text: String) -> (tokenIds: [Int], wordIds: [Int]) {
        let words = text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        var tokenIds = [Int]()
        var wordIds  = [Int]()

        for (wordIdx, word) in words.enumerated() {
            var chars = word.utf8.compactMap { byteEncoder[$0] }
            if wordIdx > 0, let spaceChar = byteEncoder[32] {
                chars.insert(spaceChar, at: 0)
            }
            let merged = bpe(chars)
            let ids    = merged.map { vocab[$0] ?? unkId }
            tokenIds.append(contentsOf: ids)
            wordIds.append(contentsOf: Array(repeating: wordIdx, count: ids.count))
        }
        return (tokenIds, wordIds)
    }

    // MARK: - BPE merge

    private func bpe(_ word: [String]) -> [String] {
        var chars = word
        while chars.count > 1 {
            var bestRank = Int.max
            var bestIdx  = -1
            for i in 0..<chars.count - 1 {
                let pair = MergePair(first: chars[i], second: chars[i + 1])
                if let rank = mergeRanks[pair], rank < bestRank {
                    bestRank = rank
                    bestIdx  = i
                }
            }
            guard bestIdx >= 0 else { break }
            chars[bestIdx] = chars[bestIdx] + chars[bestIdx + 1]
            chars.remove(at: bestIdx + 1)
        }
        return chars
    }

    // MARK: - GPT-2 byte encoder

    /// Builds the fixed GPT-2 byte-to-unicode mapping.
    /// Bytes in printable ASCII (33–126) and Latin-1 supplement ranges (161–172, 174–255)
    /// map to themselves; the remaining 68 bytes map to U+0100 onwards.
    private static func buildByteEncoder() -> [UInt8: String] {
        // Bytes that map to their own unicode scalar
        let passthrough: [ClosedRange<UInt8>] = [33...126, 161...172, 174...255]
        var result = [UInt8: String]()
        for range in passthrough {
            for b in range {
                result[b] = String(UnicodeScalar(UInt32(b))!)
            }
        }
        // Remaining bytes map to U+0100, U+0101, ... in byte order
        var extra: UInt32 = 256
        for b in UInt8(0)...UInt8(255) {
            if result[b] == nil {
                result[b] = String(UnicodeScalar(extra)!)
                extra += 1
            }
        }
        return result
    }

    // MARK: - Decodable schema

    private struct TokenizerFile: Decodable {
        struct Model: Decodable {
            let vocab: [String: Int]
            let merges: [String]
        }
        let model: Model
    }

    private struct MergePair: Hashable {
        let first: String
        let second: String
    }
}
