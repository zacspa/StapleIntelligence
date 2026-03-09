//
//  MLReceiptParser.swift
//  StapleIntelligence
//

import CoreML
import Foundation
import CoreGraphics
import OSLog

// MARK: - MLReceiptParser

/// On-device receipt token classifier backed by a 4-bit palettized DistilBERT Core ML model
/// (~15 MB).
///
/// Text-only — no image preprocessing, no bounding boxes. Tokenizes the concatenated OCR
/// line text and classifies each token into a `ReceiptFieldLabel` via per-token argmax,
/// then aggregates to per-line labels (majority vote) and assembles a `ParsedReceipt`.
///
/// ## Pipeline position
///
/// Wire into `ReceiptsView.runPipeline` as a third strategy. After the generic `ReceiptParser`
/// and any `TemplateParser` run, call `MLReceiptParser.parse(ocrLines:)` and keep the
/// result with the highest `parseConfidence`.
///
/// ## Setup (one-time, manual Xcode step)
///
/// Drag `Scanning/ReceiptTextClassifier.mlpackage` into Xcode and add it to the
/// `StapleIntelligence` target. JSON resources in `Scanning/Resources/` are included
/// automatically via `PBXFileSystemSynchronizedRootGroup`.
struct MLReceiptParser: @unchecked Sendable {

    private static let maxSeqLen = 512

    private let model: MLModel
    private let tokenizer: ByteLevelBPETokenizer
    private let labelMap: [Int: ReceiptFieldLabel]
    private let numLabels: Int

    // MARK: - Init

    /// Throws `MLParserError` if the `.mlpackage` or JSON resources are absent from the bundle.
    init() throws {
        guard let modelURL = Bundle.main.url(forResource: "ReceiptTextClassifier", withExtension: "mlmodelc")
                          ?? Bundle.main.url(forResource: "ReceiptTextClassifier", withExtension: "mlpackage") else {
            throw MLParserError.missingModel
        }
        let config = MLModelConfiguration()
        config.computeUnits = .all
        model = try MLModel(contentsOf: modelURL, configuration: config)

        guard let tokURL = Bundle.main.url(forResource: "receipt_tokenizer", withExtension: "json") else {
            throw MLParserError.missingResource("receipt_tokenizer.json")
        }
        tokenizer = try ByteLevelBPETokenizer(contentsOf: tokURL)

        guard let labelURL = Bundle.main.url(forResource: "receipt_label_map_v3", withExtension: "json"),
              let data = try? Data(contentsOf: labelURL),
              let raw = try? JSONDecoder().decode([String: String].self, from: data) else {
            throw MLParserError.missingResource("receipt_label_map_v3.json")
        }
        labelMap = raw.reduce(into: [:]) { dict, pair in
            if let id = Int(pair.key), let label = ReceiptFieldLabel(rawValue: pair.value) {
                dict[id] = label
            }
        }
        numLabels = labelMap.keys.max().map { $0 + 1 } ?? raw.count
    }

    // MARK: - Parse

    /// Returns `nil` if inference fails.
    func parse(ocrLines: [OCRLine]) -> ParsedReceipt? {
        guard !ocrLines.isEmpty else { return nil }

        let (inputIds, attentionMask, lineTokenRanges) = buildInputs(ocrLines: ocrLines)
        guard let logitArray = runInference(inputIds: inputIds, attentionMask: attentionMask)
        else { return nil }

        #if DEBUG
        ScanningLog.parse.log("ML logit shape: \(logitArray.shape.map(\.intValue), privacy: .public) strides: \(logitArray.strides.map(\.intValue), privacy: .public)")
        let firstTokLogits = (0..<min(10, numLabels)).map {
            String(format: "%.2f", logitArray[[0, 0, $0] as [NSNumber]].floatValue)
        }.joined(separator: ", ")
        ScanningLog.parse.log("ML [CLS] logits (id 0-9): \(firstTokLogits, privacy: .public)")
        #endif

        // Aggregate per-token predictions → per-line dominant label
        var labeledLines = [ReceiptFieldLabel: [OCRLine]]()
        #if DEBUG
        var globalLabelCounts = [Int: Int]()
        #endif

        for (lineIdx, line) in ocrLines.enumerated() {
            guard lineIdx < lineTokenRanges.count else { continue }
            let range = lineTokenRanges[lineIdx]
            guard !range.isEmpty else { continue }

            var counts = [ReceiptFieldLabel: Int]()
            for tokenIdx in range {
                let labelId = argmax(logitArray: logitArray, tokenIndex: tokenIdx)
                #if DEBUG
                globalLabelCounts[labelId, default: 0] += 1
                #endif
                let label = labelMap[labelId] ?? .ignore
                if label != .ignore { counts[label, default: 0] += 1 }
            }
            if let dominant = counts.max(by: { $0.value < $1.value })?.key {
                labeledLines[dominant, default: []].append(line)
            }
        }

        #if DEBUG
        let topLabels = globalLabelCounts.sorted { $0.value > $1.value }.prefix(8)
            .map { "\($0.key)(\(labelMap[$0.key]?.rawValue ?? "?"))×\($0.value)" }.joined(separator: " ")
        ScanningLog.parse.log("ML top predicted label IDs: \(topLabels, privacy: .public)")
        let realTokenCount = attentionMask.prefix(Self.maxSeqLen).filter { $0 == 1 }.count
        var realLabelCounts = [Int: Int]()
        for ti in 1..<max(1, realTokenCount - 1) {
            realLabelCounts[argmax(logitArray: logitArray, tokenIndex: ti), default: 0] += 1
        }
        let realLabels = realLabelCounts.sorted { $0.value > $1.value }.prefix(6)
            .map { "\($0.key)(\(labelMap[$0.key]?.rawValue ?? "?"))×\($0.value)" }.joined(separator: " ")
        ScanningLog.parse.log("ML real-token labels (\(realTokenCount, privacy: .public) real): \(realLabels, privacy: .public)")
        #endif

        let rawText = ocrLines.map(\.text).joined(separator: "\n")
        return extractParsedReceipt(from: labeledLines, rawOcrText: rawText)
    }

    // MARK: - Input construction

    private func buildInputs(ocrLines: [OCRLine]) -> (
        inputIds: [Int32],
        attentionMask: [Int32],
        lineTokenRanges: [Range<Int>]
    ) {
        let maxLen = Self.maxSeqLen
        var inputIds   = [Int32]()
        var lineRanges = [Range<Int>]()

        // [CLS]
        inputIds.append(Int32(tokenizer.clsId))

        for line in ocrLines {
            let startIdx = inputIds.count
            let (tokenIds, _) = tokenizer.encode(line.text)
            for tid in tokenIds {
                guard inputIds.count < maxLen - 1 else { break }
                inputIds.append(Int32(tid))
            }
            let endIdx = min(inputIds.count, maxLen - 1)
            lineRanges.append(startIdx..<endIdx)
            if inputIds.count >= maxLen - 1 { break }
        }

        // [SEP]
        inputIds.append(Int32(tokenizer.sepId))

        let realLen = inputIds.count
        while inputIds.count < maxLen {
            inputIds.append(Int32(tokenizer.padId))
        }

        let attentionMask = (0..<maxLen).map { Int32($0 < realLen ? 1 : 0) }
        return (inputIds, attentionMask, lineRanges)
    }

    // MARK: - Inference

    private func runInference(inputIds: [Int32], attentionMask: [Int32]) -> MLMultiArray? {
        let seq = Self.maxSeqLen

        guard let idArr  = try? MLMultiArray(shape: [1, seq as NSNumber], dataType: .int32),
              let mskArr = try? MLMultiArray(shape: [1, seq as NSNumber], dataType: .int32)
        else { return nil }

        for i in 0..<seq {
            idArr[i]  = NSNumber(value: inputIds[i])
            mskArr[i] = NSNumber(value: attentionMask[i])
        }

        guard let provider = try? MLDictionaryFeatureProvider(dictionary: [
            "input_ids":      MLFeatureValue(multiArray: idArr),
            "attention_mask": MLFeatureValue(multiArray: mskArr),
        ]) else { return nil }

        guard let output = try? model.prediction(from: provider),
              let logitArray = output.featureValue(for: "logits")?.multiArrayValue
        else { return nil }

        return logitArray
    }

    /// Argmax using MLMultiArray multi-index subscript (respects actual strides).
    private func argmax(logitArray: MLMultiArray, tokenIndex: Int) -> Int {
        var bestIdx = 0
        var bestVal = logitArray[[0, tokenIndex, 0] as [NSNumber]].floatValue
        for i in 1..<numLabels {
            let val = logitArray[[0, tokenIndex, i] as [NSNumber]].floatValue
            if val > bestVal {
                bestVal = val
                bestIdx = i
            }
        }
        return bestIdx
    }

    // MARK: - ParsedReceipt extraction

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

/// Minimal byte-level BPE tokenizer compatible with RoBERTa / DistilBERT (uncased).
///
/// DistilBERT uses WordPiece, not BPE. However, the fine-tuned checkpoint was trained
/// with the standard `distilbert-base-uncased` tokenizer (WordPiece).
/// This tokenizer loads HuggingFace `tokenizer.json` format; if the checkpoint uses
/// a `tokenizer.json` with a WordPiece model block the struct decodes it correctly.
///
/// For BPE (RoBERTa-style) the struct also works — `merges` is optional and the
/// fallback single-char split is still a valid (lossy) tokenization.
private struct ByteLevelBPETokenizer {

    private let vocab: [String: Int]
    private let mergeRanks: [MergePair: Int]
    private let byteEncoder: [UInt8: String]
    private let isWordPiece: Bool

    let clsId: Int
    let padId: Int
    let sepId: Int
    let unkId: Int

    // MARK: - Init

    init(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(TokenizerFile.self, from: data)

        vocab = decoded.model.vocab

        // BPE merges (empty for WordPiece models)
        var ranks = [MergePair: Int]()
        for (i, merge) in (decoded.model.merges ?? []).enumerated() {
            let parts = merge.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            ranks[MergePair(first: parts[0], second: parts[1])] = i
        }
        mergeRanks = ranks
        isWordPiece = (decoded.model.type?.lowercased() == "wordpiece") || ranks.isEmpty
        byteEncoder = Self.buildByteEncoder()

        // Token IDs — WordPiece uses [CLS]=101, [SEP]=102, [PAD]=0, [UNK]=100
        // BPE (RoBERTa) uses <s>=0, </s>=2, <pad>=1, <unk>=3
        clsId = vocab["[CLS]"] ?? vocab["<s>"]    ?? 101
        padId = vocab["[PAD]"] ?? vocab["<pad>"]  ?? 0
        sepId = vocab["[SEP]"] ?? vocab["</s>"]   ?? 102
        unkId = vocab["[UNK]"] ?? vocab["<unk>"]  ?? 100
    }

    // MARK: - Encoding

    func encode(_ text: String) -> (tokenIds: [Int], wordIds: [Int]) {
        return isWordPiece ? encodeWordPiece(text) : encodeBPE(text)
    }

    // MARK: - WordPiece

    private func encodeWordPiece(_ text: String) -> (tokenIds: [Int], wordIds: [Int]) {
        let words = text.lowercased().components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        var tokenIds = [Int]()
        var wordIds  = [Int]()

        for (wordIdx, word) in words.enumerated() {
            var remaining = word
            var first     = true
            var wordTokenized = false
            while !remaining.isEmpty {
                var found = false
                for len in stride(from: remaining.count, through: 1, by: -1) {
                    let prefix = String(remaining.prefix(len))
                    let candidate = first ? prefix : "##" + prefix
                    if let id = vocab[candidate] {
                        tokenIds.append(id)
                        wordIds.append(wordIdx)
                        remaining = String(remaining.dropFirst(len))
                        first = false
                        found = true
                        wordTokenized = true
                        break
                    }
                }
                if !found {
                    // Unknown character — emit [UNK] and skip rest of word
                    tokenIds.append(unkId)
                    wordIds.append(wordIdx)
                    remaining = ""
                    wordTokenized = true
                }
            }
            if !wordTokenized {
                tokenIds.append(unkId)
                wordIds.append(wordIdx)
            }
        }
        return (tokenIds, wordIds)
    }

    // MARK: - BPE (RoBERTa-style)

    private func encodeBPE(_ text: String) -> (tokenIds: [Int], wordIds: [Int]) {
        let words = text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        var tokenIds = [Int]()
        var wordIds  = [Int]()

        let spaceChar = byteEncoder[32] ?? "Ġ"
        for (wordIdx, word) in words.enumerated() {
            var chars = word.utf8.compactMap { byteEncoder[$0] }
            chars.insert(spaceChar, at: 0)
            let merged = bpe(chars)
            let ids    = merged.map { vocab[$0] ?? unkId }
            tokenIds.append(contentsOf: ids)
            wordIds.append(contentsOf: Array(repeating: wordIdx, count: ids.count))
        }
        return (tokenIds, wordIds)
    }

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

    private static func buildByteEncoder() -> [UInt8: String] {
        let passthrough: [ClosedRange<UInt8>] = [33...126, 161...172, 174...255]
        var result = [UInt8: String]()
        for range in passthrough {
            for b in range { result[b] = String(UnicodeScalar(UInt32(b))!) }
        }
        var extra: UInt32 = 256
        for b in UInt8(0)...UInt8(255) {
            if result[b] == nil { result[b] = String(UnicodeScalar(extra)!); extra += 1 }
        }
        return result
    }

    // MARK: - Decodable schema

    private struct TokenizerFile: Decodable {
        struct Model: Decodable {
            let type: String?
            let vocab: [String: Int]
            let merges: [String]?
        }
        let model: Model
    }

    private struct MergePair: Hashable {
        let first: String
        let second: String
    }
}
