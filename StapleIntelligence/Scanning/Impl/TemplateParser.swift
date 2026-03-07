//
//  TemplateParser.swift
//  StapleIntelligence
//

import Foundation
import CoreGraphics

/// Parses OCR lines using a pre-defined `ReceiptLayoutTemplate`.
///
/// ## Algorithm
///
/// 1. **Region matching** — for each `TemplateField`, collect every `OCRLine` whose
///    `boundingBox` intersects the field's `region` using `CGRect.intersects`. Both use
///    Vision-normalized coordinates (bottom-left origin, 0–1 range). Lines with a `nil`
///    `boundingBox` (pages beyond the first) are never matched to any field.
///
/// 2. **Grouping** — matched lines are bucketed by `ReceiptFieldLabel`. `.ignore` fields
///    are skipped entirely during region matching, not after.
///
/// 3. **Extraction**
///    - `.merchantName`: OCR texts joined with a space.
///    - `.purchaseDate`: run `ReceiptParser.datePattern` against the joined text. Only
///      `MM/DD/YY(YY)` format is recognised; other formats fall back to `nil`.
///    - `.lineItemName` + `.lineItemPrice`: sorted by Y midpoint descending (top of page
///      first), then greedily paired — each name claims the nearest available price.
///      A name with no remaining price match is dropped.
///    - `.discount`: price parsed inline from the OCR text, negated so that
///      `sum(lineItems) ≈ subtotal` arithmetic stays correct.
///    - `.subtotal`, `.tax`, `.total`: first parseable `Decimal` from the matched lines.
///
/// 4. **Confidence** — fraction of expected field types (merchantName, purchaseDate, total)
///    that were matched, plus up to 2 extra points for item count (>0 and ≥3).
///    Range: 0.0–1.0.
///
/// ## Coordinate system
///
/// All bounding boxes use Vision's **bottom-left origin**, where `minY=0` is the bottom
/// of the image and `minY=1` is the top. This is the same system used by `OCRLine.boundingBox`
/// and `TemplateField.region`. No flipping is needed for intersection tests.
///
/// ## Reuse
///
/// `ReceiptParser.canonicalize(_:)` normalises item names (uppercase, remove SKU prefix,
/// strip noise tokens and weight fragments). `ReceiptParser.datePattern`,
/// `ReceiptParser.standalonePricePattern`, `ReceiptParser.priceWithCodePattern`, and
/// `ReceiptParser.dollarAmountPattern` are shared via their `internal static let` declarations.
struct TemplateParser {

    func parse(ocrLines: [OCRLine], template: ReceiptLayoutTemplate) -> ParsedReceipt {
        let rawText = ocrLines.map(\.text).joined(separator: "\n")
        // Filter once: ignore fields are never added to labeledLines
        let fields = template.fields.filter { $0.label != .ignore }

        // Step 1: bucket each OCR line into label groups by bounding-box intersection.
        // A single OCRLine may match multiple fields if their regions overlap — this is
        // expected for dense receipts and handled correctly by the extraction logic.
        var labeledLines: [ReceiptFieldLabel: [OCRLine]] = [:]
        for field in fields {
            let region = field.region.cgRect
            let matched = ocrLines.filter { line in
                guard let bbox = line.boundingBox else { return false }
                return bbox.intersects(region)
            }
            if !matched.isEmpty {
                labeledLines[field.label, default: []].append(contentsOf: matched)
            }
        }

        // Merchant
        let merchantName: String? = labeledLines[.merchantName].flatMap { lines in
            let joined = lines.map(\.text).joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            return joined.isEmpty ? nil : joined
        }

        // Date
        let purchaseDate: Date? = labeledLines[.purchaseDate].flatMap { lines in
            extractDate(from: lines.map(\.text).joined(separator: " "))
        }

        // Line items — pair names, prices, and SKUs by Y-midpoint proximity
        let nameLines     = (labeledLines[.lineItemName]  ?? []).sorted { midY($0) > midY($1) }
        let priceLines    = (labeledLines[.lineItemPrice] ?? []).sorted { midY($0) > midY($1) }
        let discountLines = (labeledLines[.discount]      ?? []).sorted { midY($0) > midY($1) }
        let skuLines      = (labeledLines[.sku]           ?? []).sorted { midY($0) > midY($1) }
        let lineItems = buildLineItems(nameLines: nameLines,
                                       priceLines: priceLines,
                                       discountLines: discountLines,
                                       skuLines: skuLines)

        // Footer totals
        let subtotal = extractDecimal(from: labeledLines[.subtotal] ?? [])
        let tax      = extractDecimal(from: labeledLines[.tax]      ?? [])
        let total    = extractDecimal(from: labeledLines[.total]    ?? [])

        // Reconciliation
        let reconciliation: ReconciliationStatus = {
            guard let sub = subtotal else { return .unverified }
            let itemSum = lineItems.reduce(Decimal.zero) { $0 + $1.lineTotal }
            return abs(itemSum - sub) <= Decimal(string: "0.02")! ? .reconciled : .discrepancy
        }()

        let confidence = computeConfidence(labeled: labeledLines, itemCount: lineItems.count)

        return ParsedReceipt(
            rawOcrText: rawText,
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

    // MARK: - Line item construction

    /// Pairs name lines with their spatially-closest price line using Y-midpoint proximity.
    ///
    /// Both input arrays are pre-sorted descending by Vision Y (top of page first).
    /// The algorithm is **greedy**: each name line claims the nearest available price line,
    /// removing it from the pool so it cannot be re-used. Names that have no remaining
    /// price match are silently dropped.
    ///
    /// Discount lines are handled separately — their price is extracted inline from the
    /// OCR text itself and `lineTotal` is negated so that reconciliation arithmetic works.
    private func buildLineItems(
        nameLines: [OCRLine],
        priceLines: [OCRLine],
        discountLines: [OCRLine],
        skuLines: [OCRLine]
    ) -> [ParsedLineItem] {
        var remaining = priceLines
        var remainingSKUs = skuLines
        var items: [ParsedLineItem] = []

        for nameLine in nameLines {
            let raw = nameLine.text.trimmingCharacters(in: .whitespaces)
            guard !raw.isEmpty else { continue }
            let canonical = ReceiptParser.canonicalize(raw)
            let yMid = midY(nameLine)

            // Greedy nearest-neighbour match in Y: pick the price line whose midpoint
            // is closest to this name line's midpoint, then remove it from the pool.
            if let (idx, priceLine) = remaining.enumerated()
                .min(by: { abs(midY($0.element) - yMid) < abs(midY($1.element) - yMid) }),
               let price = parsePrice(from: priceLine.text)
            {
                remaining.remove(at: idx)

                // Pair with nearest SKU line if a .sku region was labeled; otherwise
                // fall back to extracting a leading numeric token from the name itself.
                let sku: String?
                if let (skuIdx, skuLine) = remainingSKUs.enumerated()
                    .min(by: { abs(midY($0.element) - yMid) < abs(midY($1.element) - yMid) })
                {
                    remainingSKUs.remove(at: skuIdx)
                    sku = skuLine.text.trimmingCharacters(in: .whitespaces)
                        .components(separatedBy: .whitespaces).first
                } else {
                    sku = ReceiptParser.extractSKU(from: raw)
                }

                items.append(ParsedLineItem(
                    rawName: raw,
                    canonicalName: canonical,
                    itemType: .byCount(count: 1),
                    unitPrice: nil,
                    lineTotal: price,
                    isDiscount: false,
                    confidence: nameLine.confidence,
                    taxCode: nil,
                    sku: sku,
                    boundingBox: nameLine.boundingBox
                ))
            }
        }

        // Discount lines (label handles them as a unit; try to parse their price inline).
        // lineTotal is negated so that reconciliation arithmetic stays correct
        // (sum of items including discounts ≈ subtotal).
        for discLine in discountLines {
            let raw = discLine.text.trimmingCharacters(in: .whitespaces)
            guard !raw.isEmpty, let absPrice = parsePrice(from: raw) else { continue }
            items.append(ParsedLineItem(
                rawName: raw,
                canonicalName: ReceiptParser.canonicalize(raw),
                itemType: .byCount(count: 1),
                unitPrice: nil,
                lineTotal: -abs(absPrice),
                isDiscount: true,
                confidence: discLine.confidence,
                taxCode: nil,
                sku: nil,
                boundingBox: discLine.boundingBox
            ))
        }

        return items
    }

    // MARK: - Helpers

    private func midY(_ line: OCRLine) -> CGFloat {
        guard let bbox = line.boundingBox else { return 0 }
        return bbox.midY
    }

    private func extractDate(from text: String) -> Date? {
        guard let match = try? ReceiptParser.datePattern.firstMatch(in: text) else { return nil }
        guard let m = Int(String(match.1)),
              let d = Int(String(match.2)),
              var y = Int(String(match.3)) else { return nil }
        if y < 100 { y += y < 50 ? 2000 : 1900 }
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d
        return Calendar(identifier: .gregorian).date(from: comps)
    }

    private func extractDecimal(from lines: [OCRLine]) -> Decimal? {
        for line in lines {
            if let d = parsePrice(from: line.text) { return d }
        }
        return nil
    }

    private func parsePrice(from text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)

        // "2.99" or "2,99"
        if (try? ReceiptParser.standalonePricePattern.wholeMatch(in: trimmed)) != nil {
            return Decimal(string: trimmed.replacingOccurrences(of: ",", with: "."),
                           locale: Locale(identifier: "en_US_POSIX"))
        }
        // "2.69 FB"
        if let match = try? ReceiptParser.priceWithCodePattern.firstMatch(in: trimmed) {
            return Decimal(string: String(match.1).replacingOccurrences(of: ",", with: "."),
                           locale: Locale(identifier: "en_US_POSIX"))
        }
        // "$2.99"
        if let match = try? ReceiptParser.dollarAmountPattern.firstMatch(in: trimmed) {
            return Decimal(string: String(match.1).replacingOccurrences(of: ",", with: "."),
                           locale: Locale(identifier: "en_US_POSIX"))
        }
        // Last resort: rightmost decimal-looking token
        for part in trimmed.components(separatedBy: .whitespaces).reversed() {
            let p = part.replacingOccurrences(of: ",", with: ".")
            if let val = Decimal(string: p, locale: Locale(identifier: "en_US_POSIX")), val > 0 {
                return val
            }
        }
        return nil
    }

    /// Confidence based on fraction of expected field types matched, weighted by importance.
    private func computeConfidence(
        labeled: [ReceiptFieldLabel: [OCRLine]],
        itemCount: Int
    ) -> Double {
        var score = 0.0; var total = 0.0

        for field in [ReceiptFieldLabel.merchantName, .purchaseDate, .total] {
            total += 1
            if labeled[field] != nil { score += 1 }
        }
        // Items (worth up to 2 points)
        total += 2
        if itemCount > 0 { score += 1 }
        if itemCount >= 3 { score += 1 }

        return total > 0 ? score / total : 0
    }
}
