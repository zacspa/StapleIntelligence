//
//  ReceiptParser.swift
//  StapleIntelligence
//
//  Created by Zack Sparks on 3/2/26.
//

import Foundation
import CoreGraphics
import OSLog

struct ReceiptParser {

    // MARK: - Feature flags

    #if DEBUG
    /// When true (default), `extractSplitColumnItems` uses a positive SKU gate:
    /// only lines starting with a 3–9 digit SKU are accepted as item names.
    /// When false, the original blacklist approach is used (for A/B comparison).
    /// Persisted in UserDefaults so both modes can be tested without rebuilding.
    static var useSkuGatedNameCollection: Bool {
        get { UserDefaults.standard.object(forKey: "parser.skuGatedNames") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "parser.skuGatedNames") }
    }
    #endif

    // MARK: - Static regex patterns

    private static let merchantPattern      = /^[A-Za-z][A-Za-z &'#.\-]{2,}$/
    private static let datePattern          = /\b(\d{1,2})\/(\d{1,2})\/(\d{2,4})\b/
    // Single-column: SKU? + name + price + taxcode?
    private static let lineItemPattern      = /^(?:\d{3,9}\s+)?(.+?)\s+(-?\d{1,3}\.\d{2})\s*(FB|ND|FR|Ft|[ABDF])?$/
    // Weight sub-line: "1.51 lb x 1.95/lb" (OCR may read 'l' as '1')
    private static let weightSublinePattern = /^(\d+[\.,]\d+)\s*(?:lb|oz|kg|1b|ib)\s+[xX]\s+(\d+[\.,]\d+)\s*[\/]?\s*(?:lb|oz|kg|1b|ib)$/
    // OCR sometimes splits the weight line across two lines:
    //   fragment 1: "1.511b x" or "1.18 ib x"  (qty × unit)
    //   fragment 2: "1.95/1b"                   (unit price)
    private static let weightFrag1Pattern = /^(\d+[\.,]\d+)\s*(1b|ib|lb|oz|kg)\s+[xX]$/
    private static let weightFrag2Pattern = /^(\d+[\.,]\d+)\s*\/\s*(1b|ib|lb|oz|kg)$/
    // Inline weight embedded in rawName: "BANANAS 1.23 lb x 0.59/lb" → qty=1.23, unit=lb, unitPrice=0.59
    // Group 1: qty, Group 2: unit, Group 3: unitPrice
    private static let inlineWeightDetailPattern =
        /(?i)(\d+[\.,]\d+)\s*(lb|oz|kg|1b|ib)\s+[xX]\s+(\d+[\.,]\d+)\s*\/?\s*(?:lb|oz|kg|1b|ib)\s*$/
    private static let discountPattern      = /(?i)^[\*\-]|SAVING|DISCOUNT|COUPON/
    private static let subtotalLabelPattern = /(?i)^SUBTOTAL$/
    private static let subtotalInlinePattern = /(?i)SUBTOTAL\s+(\d+[\.,]\d{2})/
    private static let totalPattern         = /(?im)^TOTAL\s+\$?(\d+[\.,]\d{2})$/
    private static let dollarAmountPattern  = /\$\s*(\d{1,3}[\.,]\d{2})/
    private static let cashierPattern       = /(?i)CASHIER|CLERK|OPERATOR/
    private static let visaPattern          = /(?i)VISA|MASTERCARD|DEBIT|CREDIT|CARD/
    // Allow "++APPROVED++", "+ APPROVED++", etc. — OCR sometimes drops the first "+"
    private static let approvedPattern      = /(?i)\+\s*APPROVED/
    // Price with ASCII tax code: "2.69 FB", "1.95 F8", "0.56 Fb" (case-insensitive)
    private static let priceWithCodePattern = /(?i)^(\d{1,3}[\.,]\d{2})\s+([A-Z][A-Z0-9]?)$/
    // Fallback: price followed by any non-whitespace token (handles non-ASCII codes like "гВ")
    private static let priceWithAnyCodePattern = /^(\d{1,3}[\.,]\d{2})\s+\S+$/
    // Standalone price with no tax code: must be exactly "X.XX" or "X,XX"
    private static let standalonePricePattern = /^\d{1,3}[.,]\d{2}$/

    // Matches a bare monetary amount: digits + decimal separator + exactly 2 decimal digits, nothing else.
    // Used to validate split-line subtotal/total candidates so that "50 ITEMS" (which Decimal(string:)
    // greedily parses as 50) is rejected while "116.39" is accepted.
    private static let bareDecimalPattern   = /^\d+[.,]\d{2}$/
    private static let noiseTokenPattern    = /\b(FB|ND|FR|Ft|[ABDF])\b/
    private static let weightFragPattern    = /(?i)\s+\d+[\.,]\d+\s*(?:lb|oz|kg|1b|ib).*$/
    private static let skuPrefixPattern     = /^\d{3,9}\s+/
    private static let skuCapturePattern    = /^(\d{3,9})\s+/
    // Tare/gross/net weight annotation lines printed by some stores on weighted produce.
    // e.g. "(T) 0.01" = tare weight, "(G) 1.53" = gross, "(N) 1.52" = net.
    // These match lineItemPattern (short label + decimal) and must be skipped explicitly.
    private static let tareAnnotationPattern = /^\([TGN]\)/
    // (N) net weight line with unit price: "(N) 1.52 1b x 0.49/1b"
    // Group 1: net qty, Group 2: unit, Group 3: unitPrice
    private static let nWeightPattern =
        /^\(N\)\s+(\d+[\.,]\d+)\s*(lb|oz|kg|1b|ib)\s+[xX]\s+(\d+[\.,]\d+)\s*\/?\s*(?:lb|oz|kg|1b|ib)/

    // MARK: - Section bounds

    private struct SectionBounds {
        let nameStart: Int
        let nameEnd: Int      // exclusive; stops at VISA/payment block
        let priceStart: Int?  // nil = no separate price block found
        let priceEnd: Int?    // inclusive
        let footerStart: Int
        let foundVisa: Bool   // true when nameEnd was set by a VISA/payment line
        var isSplitColumn: Bool { priceStart != nil }
    }

    // MARK: - Public API

    func parse(_ ocrLines: [OCRLine]) -> ParsedReceipt {
        let rawText = ocrLines.map(\.text).joined(separator: "\n")
        let lines = ocrLines.map { $0.text.trimmingCharacters(in: .whitespaces) }

        #if DEBUG
        var dbg = "=== parse \(Date()) ===\n"
        func d(_ s: String) { dbg += s + "\n"; ScanningLog.parse.debug("\(s, privacy: .public)") }
        func w(_ s: String) { dbg += "⚠️ " + s + "\n"; ScanningLog.parse.warning("\(s, privacy: .public)") }
        #else
        func d(_ s: String) { ScanningLog.parse.debug("\(s, privacy: .public)") }
        func w(_ s: String) { ScanningLog.parse.warning("\(s, privacy: .public)") }
        #endif

        guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            w("parse: empty input")
            return ParsedReceipt(rawOcrText: rawText, merchantName: nil, purchaseDate: nil,
                                 lineItems: [], subtotal: nil, tax: nil, total: nil,
                                 parseConfidence: 0, reconciliationStatus: .unverified)
        }

        d("parse: \(lines.count) lines")
        for (i, line) in lines.enumerated() { d("  [\(i)] \(line)") }

        // Phase 1: Merchant
        let merchantName = extractMerchant(from: lines)
        d("merchant: \(merchantName ?? "<nil>")")

        // Phase 2: Date
        let (purchaseDate, _) = extractDate(from: lines)
        d("date: \(purchaseDate?.description ?? "<nil>")")

        // Phase 3: Section bounds
        let bounds = findSectionBounds(in: lines)
        d("bounds: nameStart=\(bounds.nameStart) nameEnd=\(bounds.nameEnd) priceStart=\(bounds.priceStart.map { "\($0)" } ?? "nil") priceEnd=\(bounds.priceEnd.map { "\($0)" } ?? "nil") footerStart=\(bounds.footerStart) splitColumn=\(bounds.isSplitColumn)")

        // Phase 4 & 5: Items
        // Sort by bounding box position so display order matches receipt order.
        // In Vision coords (bottom-left origin) higher minY = higher on the page = earlier item.
        // Items without bboxes (multi-page OCR) are placed after bbox items, preserving parse order.
        let lineItems = extractItems(from: lines, ocrLines: ocrLines, bounds: bounds, log: d)
            .sorted {
                switch ($0.boundingBox, $1.boundingBox) {
                case (let a?, let b?): return a.minY > b.minY
                case (_?, nil):        return true
                case (nil, _?):        return false
                case (nil, nil):       return false
                }
            }
        d("items: \(lineItems.count) parsed")
        for (i, item) in lineItems.enumerated() {
            var info = "  [\(i)] \(item.canonicalName) = \(item.lineTotal)"
            if item.rawName.uppercased() != item.canonicalName { info += "  raw=\"\(item.rawName)\"" }
            if let sku = item.sku { info += "  sku=\(sku)" }
            if case .byWeight(let qty, let unit) = item.itemType {
                info += "  \(String(format: "%.2f", qty)) \(unit.rawValue)"
                if let up = item.unitPrice { info += " × \(up)/\(unit.rawValue)" }
            }
            if let tc = item.taxCode { info += "  [\(tc)]" }
            if item.isDiscount { info += "  DISC" }
            d(info)
        }

        // Phase 6: Footer
        let footerLines = Array(lines[bounds.footerStart...])
        // Log at .log level (always visible in Console.app) so footer content is traceable
        // even without "Include Debug Messages" enabled.
        ScanningLog.parse.log("footer: \(footerLines.count, privacy: .public) lines (footerStart=\(bounds.footerStart, privacy: .public))")
        for (i, line) in footerLines.enumerated() {
            ScanningLog.parse.log("  footer[\(i, privacy: .public)] \"\(line, privacy: .public)\"")
        }

        let subtotal = extractSubtotal(from: footerLines)
        let total    = extractTotal(from: footerLines)
        // Derive tax from total − subtotal when both are available; it's more reliable
        // than regex-scanning the footer because ALDI prints "D-Taxable @7.750%" (the rate,
        // not the amount) on the same line as the label, confusing the regex.
        let tax: Decimal? = {
            if let t = total, let s = subtotal, t > s { return t - s }
            return extractTax(from: footerLines.joined(separator: "\n"))
        }()
        ScanningLog.parse.log("footer parsed: subtotal=\(subtotal?.description ?? "<nil>", privacy: .public) tax=\(tax?.description ?? "<nil>", privacy: .public) total=\(total?.description ?? "<nil>", privacy: .public)")

        // Phase 7: Reconciliation
        let reconciliation = reconcile(items: lineItems, subtotal: subtotal)

        // Phase 8: Confidence
        let avgItemConf = lineItems.isEmpty ? 0.0 :
            lineItems.map(\.confidence).reduce(0, +) / Double(lineItems.count)
        let confidence = computeConfidence(
            hasMerchant: merchantName != nil, hasDate: purchaseDate != nil,
            itemCount: lineItems.count, avgItemConfidence: avgItemConf,
            hasTotal: total != nil, reconciliation: reconciliation)
        d("result: confidence=\(confidence) reconciliation=\(reconciliation.rawValue)")

        #if DEBUG
        flushDebugLog(dbg)
        #endif

        return ParsedReceipt(
            rawOcrText: rawText, merchantName: merchantName, purchaseDate: purchaseDate,
            lineItems: lineItems, subtotal: subtotal, tax: tax, total: total,
            parseConfidence: confidence, reconciliationStatus: reconciliation)
    }

    // Internal shim: wraps a raw string as OCRLines with uniform confidence.
    // Used by tests and DEBUG previews; not for production OCR output.
    func parse(_ rawText: String) -> ParsedReceipt {
        let ocrLines = rawText.components(separatedBy: .newlines)
            .map { OCRLine(text: $0, confidence: 1.0, boundingBox: nil) }
        return parse(ocrLines)
    }

    #if DEBUG
    private func flushDebugLog(_ content: String) {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let url = docs.appendingPathComponent("parse_debug.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            if let data = content.data(using: .utf8) { handle.write(data) }
            try? handle.close()
        } else {
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }
    #endif

    static func canonicalize(_ name: String) -> String {
        var result = name.uppercased()
        result = result.replacing(skuPrefixPattern, with: "")
        result = result.replacing(noiseTokenPattern, with: "")
        result = result.replacing(weightFragPattern, with: "")
        return result.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    static func extractSKU(from string: String) -> String? {
        guard let m = try? skuCapturePattern.prefixMatch(in: string) else { return nil }
        return String(m.1)
    }

    // MARK: - Phase implementations

    private func extractMerchant(from lines: [String]) -> String? {
        for line in lines.prefix(5) {
            guard !line.isEmpty else { continue }
            guard (try? Self.merchantPattern.wholeMatch(in: line)) != nil else { continue }
            let digitRatio = Double(line.filter(\.isNumber).count) / Double(line.count)
            if digitRatio < 0.3 { return line }
        }
        return nil
    }

    private func extractDate(from lines: [String]) -> (Date?, Int?) {
        var visaLineIndex: Int? = nil
        var allMatches: [(Date, Int)] = []
        for (i, line) in lines.enumerated() {
            if (try? Self.visaPattern.firstMatch(in: line)) != nil { visaLineIndex = i }
            if let match = try? Self.datePattern.firstMatch(in: line),
               let date = makeDate(month: String(match.1), day: String(match.2), year: String(match.3)) {
                allMatches.append((date, i))
            }
        }
        if let visaIdx = visaLineIndex, !allMatches.isEmpty {
            let nearest = allMatches.min(by: { abs($0.1 - visaIdx) < abs($1.1 - visaIdx) })
            return (nearest?.0, visaLineIndex)
        }
        return (allMatches.first?.0, visaLineIndex)
    }

    private func makeDate(month: String, day: String, year: String) -> Date? {
        guard let m = Int(month), let d = Int(day), var y = Int(year) else { return nil }
        if y < 100 { y += y < 50 ? 2000 : 1900 }
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d
        return Calendar(identifier: .gregorian).date(from: comps)
    }

    // MARK: - Section detection

    private func findSectionBounds(in lines: [String]) -> SectionBounds {
        var nameStart = 0
        var nameEnd = lines.count
        var priceStart: Int? = nil
        var priceEnd: Int? = nil

        // nameStart: after cashier line, or first line-item match
        for (i, line) in lines.enumerated() {
            if (try? Self.cashierPattern.firstMatch(in: line)) != nil {
                nameStart = i + 1
                ScanningLog.parse.debug("bounds: cashier at \(i, privacy: .public) → nameStart=\(nameStart, privacy: .public)")
                break
            }
        }
        if nameStart == 0 {
            for (i, line) in lines.enumerated() {
                if (try? Self.lineItemPattern.wholeMatch(in: line)) != nil {
                    nameStart = i
                    ScanningLog.parse.debug("bounds: first lineItem at \(i, privacy: .public) → nameStart=\(nameStart, privacy: .public)")
                    break
                }
            }
        }

        // Try to find VISA/payment block → that's where name section ends in split-column format
        var visaLine: Int? = nil
        for i in nameStart..<lines.count {
            if (try? Self.visaPattern.firstMatch(in: lines[i])) != nil {
                visaLine = i
                ScanningLog.parse.debug("bounds: VISA at \(i, privacy: .public)")
                break
            }
        }

        if let vl = visaLine {
            nameEnd = vl

            // Find end of payment block: ++APPROVED++ within 20 lines of VISA
            var paymentEnd = vl
            for i in vl..<min(vl + 20, lines.count) {
                if (try? Self.approvedPattern.firstMatch(in: lines[i])) != nil {
                    paymentEnd = i
                    ScanningLog.parse.debug("bounds: APPROVED at \(i, privacy: .public)")
                    break
                }
            }

            // Price block start: first price-like line after payment block
            for i in (paymentEnd + 1)..<lines.count {
                if lines[i].isEmpty { continue }
                if extractPrice(from: lines[i]) != nil {
                    priceStart = i
                    ScanningLog.parse.debug("bounds: priceBlock starts at \(i, privacy: .public)")
                    break
                }
            }

            // Price block end: scan forward until a footer marker or large total amount.
            // Unlike the old approach, we don't stop at the first non-price line —
            // OCR occasionally drops a tax code, leaving a gap we must skip over.
            if let ps = priceStart {
                var pe = ps
                var i = ps
                while i < lines.count {
                    let line = lines[i]
                    if line.isEmpty { i += 1; continue }
                    if isFooterMarker(line) {
                        ScanningLog.parse.debug("bounds: footer marker at \(i, privacy: .public) — price block ends at \(pe, privacy: .public)")
                        break
                    }
                    if extractPrice(from: line) != nil { pe = i }
                    i += 1
                }
                priceEnd = pe
                ScanningLog.parse.debug("bounds: priceBlock ends at \(pe, privacy: .public)")
            }
        } else {
            // No VISA line: single-column format — SUBTOTAL ends the item section
            for i in nameStart..<lines.count {
                if (try? Self.subtotalInlinePattern.firstMatch(in: lines[i])) != nil {
                    nameEnd = i
                    ScanningLog.parse.debug("bounds: single-column SUBTOTAL at \(i, privacy: .public) → nameEnd=\(i, privacy: .public)")
                    break
                }
            }
            if nameEnd == lines.count {
                ScanningLog.parse.warning("bounds: single-column, SUBTOTAL not found — nameEnd defaulted to \(lines.count, privacy: .public)")
            }
        }

        // When there's a price block, footer begins after it (+1 skips the last price line).
        // When there's no price block (single-column or VISA-only), the SUBTOTAL line IS
        // nameEnd — include it in the footer so extractSubtotal can find it.
        var footerStart = min(priceEnd.map { $0 + 1 } ?? nameEnd, lines.count)

        // ALDI split-column: the SUBTOTAL label appears in the left column (between the VISA
        // line and the price block start), while its value appears in the right column (after
        // priceEnd). Walk footerStart back to the SUBTOTAL label so extractSubtotal sees both.
        if let ps = priceStart, nameEnd < ps,
           let idx = (nameEnd..<ps).first(where: {
               (try? Self.subtotalLabelPattern.wholeMatch(in: lines[$0])) != nil
           }) {
            footerStart = min(footerStart, idx)
            ScanningLog.parse.debug("bounds: SUBTOTAL label at \(idx, privacy: .public) before price block → footerStart adjusted to \(footerStart, privacy: .public)")
        }

        ScanningLog.parse.debug("bounds: footerStart=\(footerStart, privacy: .public)")
        return SectionBounds(nameStart: nameStart, nameEnd: nameEnd,
                             priceStart: priceStart, priceEnd: priceEnd,
                             footerStart: footerStart, foundVisa: visaLine != nil)
    }

    /// Returns true for lines that clearly belong to the receipt footer, not the price block.
    private func isFooterMarker(_ line: String) -> Bool {
        let upper = line.trimmingCharacters(in: .whitespaces).uppercased()
        if upper == "SUBTOTAL" || upper == "TOTAL" || upper.contains("AMOUNT DUE") { return true }
        if (try? Self.subtotalInlinePattern.firstMatch(in: line)) != nil { return true }
        // A standalone decimal ≥ $30 is a receipt total, not an item price
        if let val = Decimal(string: normalize(line.trimmingCharacters(in: .whitespaces)),
                             locale: Locale(identifier: "en_US_POSIX")), val >= 30 { return true }
        return false
    }

    /// Tries to parse a price from a line. Returns (price, taxCode?) or nil.
    private func extractPrice(from line: String) -> (price: Decimal, taxCode: String?)? {
        // Price with ASCII tax code: "2.69 FB", "0.56 Fb" (case-insensitive)
        if let pm = try? Self.priceWithCodePattern.wholeMatch(in: line),
           let price = Decimal(string: normalize(String(pm.1)), locale: Locale(identifier: "en_US_POSIX")) {
            return (price, String(pm.2).uppercased())
        }
        // Fallback for non-ASCII tax codes (e.g. OCR renders "FB" as Cyrillic "гВ")
        if let pm = try? Self.priceWithAnyCodePattern.wholeMatch(in: line),
           let price = Decimal(string: normalize(String(pm.1)), locale: Locale(identifier: "en_US_POSIX")),
           price > 0 && price < 30 {
            return (price, nil)
        }
        // Standalone price with no tax code: line must be exactly "X.XX"
        let candidate = normalize(line.trimmingCharacters(in: .whitespaces))
        if (try? Self.standalonePricePattern.wholeMatch(in: candidate)) != nil,
           let price = Decimal(string: candidate, locale: Locale(identifier: "en_US_POSIX")),
           price > 0 && price < 30 {
            return (price, nil)
        }
        return nil
    }

    // MARK: - Item extraction

    private func extractItems(from lines: [String], ocrLines: [OCRLine], bounds: SectionBounds, log: (String) -> Void = { _ in }) -> [ParsedLineItem] {
        if bounds.isSplitColumn {
            let items = extractSplitColumnItems(from: lines, ocrLines: ocrLines, bounds: bounds, log: log)
            if items.count > 0 { return items }
            // Price block was empty — OCR likely interleaved names and prices.
            // Fall through to mixed-column extraction of the name block.
            log("splitColumn yielded 0 items — retrying as mixed column")
        }
        if bounds.foundVisa {
            // VISA detected: name block contains interleaved names and prices.
            return extractMixedColumnItems(from: lines, ocrLines: ocrLines, start: bounds.nameStart, end: bounds.nameEnd, log: log)
        }
        return extractInlineItems(from: lines, ocrLines: ocrLines, start: bounds.nameStart, end: bounds.nameEnd)
    }

    /// Single-column format: each line has SKU? + name + price + taxcode?
    private func extractInlineItems(from lines: [String], ocrLines: [OCRLine], start: Int, end: Int) -> [ParsedLineItem] {
        guard start < end else { return [] }
        let section = Array(lines[start..<end])
        var items: [ParsedLineItem] = []
        var idx = 0
        while idx < section.count {
            let line = section[idx]
            // Skip tare/gross/net annotation lines — "(G) 1.53", "(N) 1.52", "(T) 0.01".
            // These match lineItemPattern (short label + decimal) and would be parsed as fake items.
            if (try? Self.tareAnnotationPattern.firstMatch(in: line)) != nil { idx += 1; continue }
            guard !line.isEmpty,
                  let match = try? Self.lineItemPattern.wholeMatch(in: line) else { idx += 1; continue }
            let sourceLineIndex = start + idx  // captured before any idx mutation
            let sku = Self.extractSKU(from: line)
            let rawName = String(match.1)
            let priceStr = normalize(String(match.2))
            let taxCode  = match.3.map(String.init)
            guard let price = Decimal(string: priceStr, locale: Locale(identifier: "en_US_POSIX")) else { idx += 1; continue }
            let isDiscount = (try? Self.discountPattern.firstMatch(in: rawName)) != nil || price < 0
            var weightQty: Double? = nil
            var weightUnit: WeightUnit? = nil
            var weightUnitPrice: Decimal? = nil
            // Step A: check rawName itself for embedded inline weight (e.g. "BANANAS 1.23 lb x 0.59/lb")
            if let wm = try? Self.inlineWeightDetailPattern.firstMatch(in: rawName) {
                weightQty       = Double(normalize(String(wm.1)))
                weightUnit      = normalizeUnit(String(wm.2))
                weightUnitPrice = Decimal(string: normalize(String(wm.3)), locale: Locale(identifier: "en_US_POSIX"))
            }
            // Step B: next-line weight sub-line overrides Step A if present
            let nextIdx = idx + 1
            if nextIdx < section.count,
               let wm = try? Self.weightSublinePattern.wholeMatch(in: section[nextIdx]) {
                weightQty = Double(normalize(String(wm.1)))
                let rawUnit = section[nextIdx].contains("lb") || section[nextIdx].contains("1b") ? "lb"
                           : section[nextIdx].contains("oz") ? "oz" : "kg"
                weightUnit = WeightUnit(rawValue: rawUnit) ?? .lb
                weightUnitPrice = Decimal(string: normalize(String(wm.2)), locale: Locale(identifier: "en_US_POSIX"))
                idx += 1
            }
            let itemType: ItemType = weightQty.map { .byWeight(quantity: $0, unit: weightUnit ?? .lb) } ?? .byCount(count: 1)
            let canonical = Self.canonicalize(rawName)
            items.append(ParsedLineItem(
                rawName: rawName, canonicalName: canonical,
                itemType: itemType, unitPrice: weightUnitPrice,
                lineTotal: price, isDiscount: isDiscount,
                confidence: itemConfidence(ocrLines: ocrLines, lineIndex: sourceLineIndex, canonical: canonical, isDiscount: isDiscount),
                taxCode: taxCode, sku: sku,
                boundingBox: sourceLineIndex < ocrLines.count ? ocrLines[sourceLineIndex].boundingBox : nil))
            idx += 1
        }
        return items
    }

    /// Split-column format: name block (nameStart..<nameEnd) zipped with price block (priceStart...priceEnd)
    private func extractSplitColumnItems(from lines: [String], ocrLines: [OCRLine], bounds: SectionBounds, log: (String) -> Void = { _ in }) -> [ParsedLineItem] {
        guard let priceStart = bounds.priceStart, let priceEnd = bounds.priceEnd else { return [] }

        // Collect name entries, attaching weight sub-lines to the preceding name
        struct NameEntry { var raw: String; var lineIndex: Int; var weightQty: Double?; var weightUnit: WeightUnit?; var weightUnitPrice: Decimal? }
        var names: [NameEntry] = []

        var pendingWeightQty: Double? = nil
        var pendingWeightUnit: WeightUnit? = nil

        #if DEBUG
        let useSkuGate = ReceiptParser.useSkuGatedNameCollection
        #else
        let useSkuGate = true
        #endif

        var i = bounds.nameStart
        while i < bounds.nameEnd {
            let line = lines[i]
            defer { i += 1 }
            guard !line.isEmpty else { continue }

            if useSkuGate {
                // Branch A — SKU prefix confirmed → real item line
                if (try? Self.skuCapturePattern.firstMatch(in: line)) != nil {
                    pendingWeightQty = nil; pendingWeightUnit = nil
                    var entry = NameEntry(raw: line, lineIndex: i, weightQty: nil, weightUnit: nil, weightUnitPrice: nil)
                    if let wm = try? Self.inlineWeightDetailPattern.firstMatch(in: line) {
                        entry.weightQty       = Double(normalize(String(wm.1)))
                        entry.weightUnit      = normalizeUnit(String(wm.2))
                        entry.weightUnitPrice = Decimal(string: normalize(String(wm.3)), locale: Locale(identifier: "en_US_POSIX"))
                    }
                    names.append(entry)
                    continue
                }
                // Branch B — no SKU → weight metadata for the preceding item (if any), else dropped
                guard !names.isEmpty else { continue }
                if let wm = try? Self.weightSublinePattern.wholeMatch(in: line) {
                    let qty  = Double(normalize(String(wm.1)))
                    let rawUnit = line.contains("lb") || line.contains("1b") ? "lb"
                               : line.contains("oz") ? "oz" : "kg"
                    let up   = Decimal(string: normalize(String(wm.2)), locale: Locale(identifier: "en_US_POSIX"))
                    names[names.count - 1].weightQty       = qty
                    names[names.count - 1].weightUnit      = WeightUnit(rawValue: rawUnit) ?? .lb
                    names[names.count - 1].weightUnitPrice = up
                    pendingWeightQty = nil; pendingWeightUnit = nil
                    continue
                }
                if let wf = try? Self.weightFrag1Pattern.wholeMatch(in: line) {
                    pendingWeightQty  = Double(normalize(String(wf.1)))
                    pendingWeightUnit = normalizeUnit(String(wf.2))
                    continue
                }
                if let wf = try? Self.weightFrag2Pattern.wholeMatch(in: line),
                   let qty = pendingWeightQty, let unit = pendingWeightUnit {
                    names[names.count - 1].weightQty       = qty
                    names[names.count - 1].weightUnit      = unit
                    names[names.count - 1].weightUnitPrice = Decimal(string: normalize(String(wf.1)),
                                                                      locale: Locale(identifier: "en_US_POSIX"))
                    pendingWeightQty = nil; pendingWeightUnit = nil
                    continue
                }
                // (N) net weight line: "(N) 1.52 1b x 0.49/1b" — the useful weight/price annotation
                if let wm = try? Self.nWeightPattern.firstMatch(in: line) {
                    let rawUnit = line.contains("lb") || line.contains("1b") ? "lb"
                               : line.contains("oz") ? "oz" : "kg"
                    names[names.count - 1].weightQty       = Double(normalize(String(wm.1)))
                    names[names.count - 1].weightUnit      = WeightUnit(rawValue: rawUnit) ?? .lb
                    names[names.count - 1].weightUnitPrice = Decimal(string: normalize(String(wm.3)),
                                                                      locale: Locale(identifier: "en_US_POSIX"))
                    pendingWeightQty = nil; pendingWeightUnit = nil
                    continue
                }
                // Tare annotations, OCR noise, separators — silently dropped
            } else {
                // Legacy blacklist approach (DEBUG only, for A/B comparison)
                if let wm = try? Self.weightSublinePattern.wholeMatch(in: line) {
                    if !names.isEmpty {
                        let qty  = Double(normalize(String(wm.1)))
                        let rawUnit = line.contains("lb") || line.contains("1b") ? "lb"
                                   : line.contains("oz") ? "oz" : "kg"
                        let up   = Decimal(string: normalize(String(wm.2)), locale: Locale(identifier: "en_US_POSIX"))
                        names[names.count - 1].weightQty       = qty
                        names[names.count - 1].weightUnit      = WeightUnit(rawValue: rawUnit) ?? .lb
                        names[names.count - 1].weightUnitPrice = up
                    }
                    pendingWeightQty = nil; pendingWeightUnit = nil
                    continue
                }
                if let wf = try? Self.weightFrag1Pattern.wholeMatch(in: line) {
                    pendingWeightQty  = Double(normalize(String(wf.1)))
                    pendingWeightUnit = normalizeUnit(String(wf.2))
                    continue
                }
                if let wf = try? Self.weightFrag2Pattern.wholeMatch(in: line),
                   let qty = pendingWeightQty, let unit = pendingWeightUnit, !names.isEmpty {
                    names[names.count - 1].weightQty       = qty
                    names[names.count - 1].weightUnit      = unit
                    names[names.count - 1].weightUnitPrice = Decimal(string: normalize(String(wf.1)),
                                                                      locale: Locale(identifier: "en_US_POSIX"))
                    pendingWeightQty = nil; pendingWeightUnit = nil
                    continue
                }
                pendingWeightQty = nil; pendingWeightUnit = nil
                if let wm = try? Self.nWeightPattern.firstMatch(in: line), !names.isEmpty {
                    let rawUnit = line.contains("lb") || line.contains("1b") ? "lb"
                               : line.contains("oz") ? "oz" : "kg"
                    names[names.count - 1].weightQty       = Double(normalize(String(wm.1)))
                    names[names.count - 1].weightUnit      = WeightUnit(rawValue: rawUnit) ?? .lb
                    names[names.count - 1].weightUnitPrice = Decimal(string: normalize(String(wm.3)),
                                                                      locale: Locale(identifier: "en_US_POSIX"))
                    continue
                }
                if (try? Self.tareAnnotationPattern.firstMatch(in: line)) != nil { continue }
                let alphaCount = line.filter { $0.isLetter }.count
                guard alphaCount >= 4 else { continue }
                var legacyEntry = NameEntry(raw: line, lineIndex: i, weightQty: nil, weightUnit: nil, weightUnitPrice: nil)
                if let wm = try? Self.inlineWeightDetailPattern.firstMatch(in: line) {
                    legacyEntry.weightQty       = Double(normalize(String(wm.1)))
                    legacyEntry.weightUnit      = normalizeUnit(String(wm.2))
                    legacyEntry.weightUnitPrice = Decimal(string: normalize(String(wm.3)), locale: Locale(identifier: "en_US_POSIX"))
                }
                names.append(legacyEntry)
            }
        }

        // Collect price entries — use extractPrice() to capture both coded ("2.69 FB")
        // and standalone ("4.69") prices that OCR occasionally drops the tax code from.
        // lineIndex is retained so we can match by Y-proximity.
        //
        // OCR sometimes splits a price across two lines at the decimal point:
        //   "1"  →  ".79 FB"   (should be "1.79 FB")
        // Track a bare-integer pending line and stitch it to the next line if that
        // line starts with "." — producing a valid price string to pass to extractPrice.
        struct PriceEntry { var price: Decimal; var taxCode: String?; var lineIndex: Int }
        var prices: [PriceEntry] = []
        var pendingSplitInteger: (digits: String, lineIndex: Int)? = nil
        for i in priceStart...priceEnd {
            let line = lines[i]
            guard !line.isEmpty else { continue }
            // Bare integer: likely the integer part of a split price (e.g. "1" before ".79 FB")
            if (try? /^\d{1,3}$/.wholeMatch(in: line)) != nil {
                pendingSplitInteger = (line, i)
                continue
            }
            // Stitch pending integer to a decimal-fragment line (e.g. "1" + ".79 FB" → "1.79 FB")
            let resolvedLine: String
            let resolvedLineIndex: Int
            if let pending = pendingSplitInteger, line.hasPrefix(".") {
                resolvedLine = pending.digits + line
                resolvedLineIndex = pending.lineIndex
            } else {
                resolvedLine = line
                resolvedLineIndex = i
            }
            pendingSplitInteger = nil
            guard let ep = extractPrice(from: resolvedLine) else { continue }
            prices.append(PriceEntry(price: ep.price, taxCode: ep.taxCode, lineIndex: resolvedLineIndex))
        }

        ScanningLog.parse.debug("splitColumn: \(names.count, privacy: .public) names, \(prices.count, privacy: .public) prices")
        log("splitColumn: \(names.count) names, \(prices.count) prices")
        for (i, n) in names.enumerated() {
            var info = "  name[\(i)] \"\(n.raw)\""
            if let qty = n.weightQty, let unit = n.weightUnit {
                info += "  \(String(format: "%.2f", qty)) \(unit.rawValue)"
                if let up = n.weightUnitPrice { info += " × \(up)/\(unit.rawValue)" }
            }
            log(info)
        }
        for (i, p) in prices.enumerated() {
            log("  price[\(i)] \(p.price)\(p.taxCode.map { " \($0)" } ?? "") lineIdx=\(p.lineIndex)")
        }

        // Match each name to the closest unmatched price by Y-midpoint (Vision coords, bottom-left origin).
        // This is resilient to extra non-priced lines (tare annotations, weight fragments) in either
        // column: index-based zip misaligns every subsequent item when counts diverge, while
        // Y-proximity matching skips over the extra lines and preserves correct attribution.
        // Falls back to index-zip when bboxes are unavailable (tests / raw-text shim).
        let namesMidY: [CGFloat?] = names.map { ne in
            guard ne.lineIndex < ocrLines.count else { return nil }
            return ocrLines[ne.lineIndex].boundingBox?.midY
        }
        let pricesMidY: [CGFloat?] = prices.map { pe in
            guard pe.lineIndex < ocrLines.count else { return nil }
            return ocrLines[pe.lineIndex].boundingBox?.midY
        }
        let useProximity = !names.isEmpty && !prices.isEmpty
            && namesMidY.allSatisfy({ $0 != nil })
            && pricesMidY.allSatisfy({ $0 != nil })

        var items: [ParsedLineItem] = []

        if useProximity {
            // Sort prices by ascending Y-midpoint for binary-search-based nearest-neighbor matching.
            let sortedPIs = prices.indices.sorted { pricesMidY[$0]! < pricesMidY[$1]! }
            var usedPriceIndices = Set<Int>()

            for (ni, nl) in names.enumerated() {
                let nameMidY = namesMidY[ni]!

                // Binary search: find insertion point for nameMidY in the sorted price Y values.
                var lo = 0, hi = sortedPIs.count
                while lo < hi {
                    let mid = (lo + hi) / 2
                    if pricesMidY[sortedPIs[mid]]! < nameMidY { lo = mid + 1 } else { hi = mid }
                }

                // Expand outward from insertion point, always advancing the closer pointer first.
                // The first unmatched price encountered is the closest unmatched one.
                var bestIdx: Int? = nil
                var left = lo - 1
                var right = lo
                while left >= 0 || right < sortedPIs.count {
                    let ld = left  >= 0              ? abs(pricesMidY[sortedPIs[left]]!  - nameMidY) : CGFloat.infinity
                    let rd = right < sortedPIs.count ? abs(pricesMidY[sortedPIs[right]]! - nameMidY) : CGFloat.infinity
                    let useLeft = ld <= rd
                    let pi = sortedPIs[useLeft ? left : right]
                    if !usedPriceIndices.contains(pi) { bestIdx = pi; break }
                    if useLeft { left -= 1 } else { right += 1 }
                }

                guard let pi = bestIdx else {
                    log("splitColumn: no price match for \"\(nl.raw)\" — skipping")
                    continue
                }
                usedPriceIndices.insert(pi)
                let pl = prices[pi]
                let nameConf  = nl.lineIndex < ocrLines.count ? ocrLines[nl.lineIndex].confidence : 0.7
                let priceConf = pl.lineIndex < ocrLines.count ? ocrLines[pl.lineIndex].confidence : 0.7
                if priceConf < 0.95 {
                    log("splitColumn: low price conf \(String(format: "%.3f", priceConf)) at lineIdx=\(pl.lineIndex) \"\(lines[pl.lineIndex])\" for \"\(nl.raw)\"")
                }
                let ncStr = String(format: "%.3f", nameConf)
                let pcStr = String(format: "%.3f", priceConf)
                ScanningLog.parse.log("splitColumn match: \"\(nl.raw, privacy: .public)\" → \(pl.price, privacy: .public) nameConf=\(ncStr, privacy: .public) priceConf=\(pcStr, privacy: .public)")
                let isDiscount = (try? Self.discountPattern.firstMatch(in: nl.raw)) != nil || pl.price < 0
                let canonical  = Self.canonicalize(nl.raw)
                let sku = Self.extractSKU(from: nl.raw)
                items.append(ParsedLineItem(
                    rawName: nl.raw, canonicalName: canonical,
                    itemType: nl.weightQty.map { .byWeight(quantity: $0, unit: nl.weightUnit ?? .lb) } ?? .byCount(count: 1),
                    unitPrice: nl.weightUnitPrice,
                    lineTotal: pl.price, isDiscount: isDiscount,
                    confidence: itemConfidence(ocrLines: ocrLines, lineIndex: nl.lineIndex, canonical: canonical, isDiscount: isDiscount, priceLineIndex: pl.lineIndex),
                    taxCode: pl.taxCode, sku: sku,
                    boundingBox: nl.lineIndex < ocrLines.count ? ocrLines[nl.lineIndex].boundingBox : nil))
            }
        } else {
            // Index-based zip fallback (no bboxes — tests, raw-text shim)
            let count = min(names.count, prices.count)
            for i in 0..<count {
                let nl = names[i]; let pl = prices[i]
                let isDiscount = (try? Self.discountPattern.firstMatch(in: nl.raw)) != nil || pl.price < 0
                let canonical  = Self.canonicalize(nl.raw)
                let sku = Self.extractSKU(from: nl.raw)
                items.append(ParsedLineItem(
                    rawName: nl.raw, canonicalName: canonical,
                    itemType: nl.weightQty.map { .byWeight(quantity: $0, unit: nl.weightUnit ?? .lb) } ?? .byCount(count: 1),
                    unitPrice: nl.weightUnitPrice,
                    lineTotal: pl.price, isDiscount: isDiscount,
                    confidence: itemConfidence(ocrLines: ocrLines, lineIndex: nl.lineIndex, canonical: canonical, isDiscount: isDiscount, priceLineIndex: pl.lineIndex),
                    taxCode: pl.taxCode, sku: sku,
                    boundingBox: nl.lineIndex < ocrLines.count ? ocrLines[nl.lineIndex].boundingBox : nil))
            }
        }
        return items
    }

    /// Mixed-column format: OCR interleaved names and prices in the same block.
    /// Scans [start, end) collecting names and prices independently, then zips by index.
    private func extractMixedColumnItems(from lines: [String], ocrLines: [OCRLine], start: Int, end: Int, log: (String) -> Void = { _ in }) -> [ParsedLineItem] {
        struct NameEntry { var raw: String; var lineIndex: Int; var weightQty: Double?; var weightUnit: WeightUnit?; var weightUnitPrice: Decimal? }
        struct PriceEntry { var price: Decimal; var taxCode: String?; var lineIndex: Int }
        var names: [NameEntry] = []
        var prices: [PriceEntry] = []
        var pendingWeightQty: Double? = nil
        var pendingWeightUnit: WeightUnit? = nil

        var i = start
        while i < end {
            let line = lines[i]
            defer { i += 1 }
            guard !line.isEmpty else { continue }

            // Full single-line weight sub-line
            if let wm = try? Self.weightSublinePattern.wholeMatch(in: line) {
                if !names.isEmpty {
                    let rawUnit = line.contains("lb") || line.contains("1b") ? "lb"
                               : line.contains("oz") ? "oz" : "kg"
                    names[names.count - 1].weightQty       = Double(normalize(String(wm.1)))
                    names[names.count - 1].weightUnit      = WeightUnit(rawValue: rawUnit) ?? .lb
                    names[names.count - 1].weightUnitPrice = Decimal(string: normalize(String(wm.2)),
                                                                       locale: Locale(identifier: "en_US_POSIX"))
                }
                pendingWeightQty = nil; pendingWeightUnit = nil
                continue
            }
            // Split weight fragment 1
            if let wf = try? Self.weightFrag1Pattern.wholeMatch(in: line) {
                pendingWeightQty  = Double(normalize(String(wf.1)))
                pendingWeightUnit = normalizeUnit(String(wf.2))
                continue
            }
            // Split weight fragment 2
            if let wf = try? Self.weightFrag2Pattern.wholeMatch(in: line),
               let qty = pendingWeightQty, let unit = pendingWeightUnit, !names.isEmpty {
                names[names.count - 1].weightQty       = qty
                names[names.count - 1].weightUnit      = unit
                names[names.count - 1].weightUnitPrice = Decimal(string: normalize(String(wf.1)),
                                                                  locale: Locale(identifier: "en_US_POSIX"))
                pendingWeightQty = nil; pendingWeightUnit = nil
                continue
            }
            pendingWeightQty = nil; pendingWeightUnit = nil

            // (N) net weight line: "(N) 1.52 1b x 0.49/1b" — attach weight/price to preceding item
            if let wm = try? Self.nWeightPattern.firstMatch(in: line), !names.isEmpty {
                let rawUnit = line.contains("lb") || line.contains("1b") ? "lb"
                           : line.contains("oz") ? "oz" : "kg"
                names[names.count - 1].weightQty       = Double(normalize(String(wm.1)))
                names[names.count - 1].weightUnit      = WeightUnit(rawValue: rawUnit) ?? .lb
                names[names.count - 1].weightUnitPrice = Decimal(string: normalize(String(wm.3)),
                                                                  locale: Locale(identifier: "en_US_POSIX"))
                continue
            }
            // Skip tare/gross/net annotation lines — "(G) 1.531b - (T) 0.01lb", "(N) 1.52 1b x 0.49/1b"
            if (try? Self.tareAnnotationPattern.firstMatch(in: line)) != nil { continue }

            // Price check before name check (price lines have few alpha chars)
            if let ep = extractPrice(from: line) {
                prices.append(PriceEntry(price: ep.price, taxCode: ep.taxCode, lineIndex: i))
                continue
            }
            // Name check
            guard line.filter({ $0.isLetter }).count >= 4 else { continue }
            var entry = NameEntry(raw: line, lineIndex: i, weightQty: nil, weightUnit: nil, weightUnitPrice: nil)
            if let wm = try? Self.inlineWeightDetailPattern.firstMatch(in: line) {
                entry.weightQty       = Double(normalize(String(wm.1)))
                entry.weightUnit      = normalizeUnit(String(wm.2))
                entry.weightUnitPrice = Decimal(string: normalize(String(wm.3)), locale: Locale(identifier: "en_US_POSIX"))
            }
            names.append(entry)
        }

        ScanningLog.parse.debug("mixedColumn: \(names.count, privacy: .public) names, \(prices.count, privacy: .public) prices")
        log("mixedColumn: \(names.count) names, \(prices.count) prices")
        for (i, n) in names.enumerated() {
            var info = "  name[\(i)] \"\(n.raw)\""
            if let qty = n.weightQty, let unit = n.weightUnit {
                info += "  \(String(format: "%.2f", qty)) \(unit.rawValue)"
                if let up = n.weightUnitPrice { info += " × \(up)/\(unit.rawValue)" }
            }
            log(info)
        }
        for (i, p) in prices.enumerated() {
            log("  price[\(i)] \(p.price)\(p.taxCode.map { " \($0)" } ?? "")")
        }

        var items: [ParsedLineItem] = []
        let count = min(names.count, prices.count)
        for i in 0..<count {
            let nl = names[i]; let pl = prices[i]
            let isDiscount = (try? Self.discountPattern.firstMatch(in: nl.raw)) != nil || pl.price < 0
            let canonical  = Self.canonicalize(nl.raw)
            let sku = Self.extractSKU(from: nl.raw)
            let sourceLineIndex = nl.lineIndex
            items.append(ParsedLineItem(
                rawName: nl.raw, canonicalName: canonical,
                itemType: nl.weightQty.map { .byWeight(quantity: $0, unit: nl.weightUnit ?? .lb) } ?? .byCount(count: 1),
                unitPrice: nl.weightUnitPrice,
                lineTotal: pl.price, isDiscount: isDiscount,
                confidence: itemConfidence(ocrLines: ocrLines, lineIndex: sourceLineIndex, canonical: canonical, isDiscount: isDiscount, priceLineIndex: pl.lineIndex),
                taxCode: pl.taxCode, sku: sku,
                boundingBox: sourceLineIndex < ocrLines.count ? ocrLines[sourceLineIndex].boundingBox : nil))
        }
        return items
    }

    // MARK: - Footer extraction

    private func extractSubtotal(from footerLines: [String]) -> Decimal? {
        let text = footerLines.joined(separator: "\n")
        // Inline: "SUBTOTAL 164.28"
        if let m = try? Self.subtotalInlinePattern.firstMatch(in: text) {
            let val = Decimal(string: normalize(String(m.1)), locale: Locale(identifier: "en_US_POSIX"))
            ScanningLog.parse.log("extractSubtotal: inline match → \(val?.description ?? "nil", privacy: .public)")
            return val
        }
        ScanningLog.parse.log("extractSubtotal: no inline SUBTOTAL match — scanning \(footerLines.count, privacy: .public) lines for label")
        // Split-line: "SUBTOTAL" alone, value on a subsequent line
        for (i, line) in footerLines.enumerated() {
            if (try? Self.subtotalLabelPattern.wholeMatch(in: line)) != nil {
                ScanningLog.parse.log("extractSubtotal: label at footer[\(i, privacy: .public)]")
                for j in (i + 1)..<min(i + 10, footerLines.count) {
                    let candidate = normalize(footerLines[j].trimmingCharacters(in: .whitespaces))
                    // Require a bare decimal (e.g. "116.39") — reject "50 ITEMS" even though
                    // Decimal(string:) greedily parses its leading digits as 50.
                    guard (try? Self.bareDecimalPattern.wholeMatch(in: candidate)) != nil else {
                        ScanningLog.parse.log("extractSubtotal:   footer[\(j, privacy: .public)] \"\(footerLines[j], privacy: .public)\" → skipped (not bare decimal)")
                        continue
                    }
                    let parsed = Decimal(string: candidate, locale: Locale(identifier: "en_US_POSIX"))
                    ScanningLog.parse.log("extractSubtotal:   footer[\(j, privacy: .public)] \"\(footerLines[j], privacy: .public)\" → candidate=\"\(candidate, privacy: .public)\" parsed=\(parsed?.description ?? "nil", privacy: .public)")
                    if let val = parsed, val > 0 {
                        ScanningLog.parse.log("extractSubtotal: split-line match → \(val, privacy: .public)")
                        return val
                    }
                }
            }
        }
        ScanningLog.parse.log("extractSubtotal: → nil")
        return nil
    }

    private func extractTotal(from footerLines: [String]) -> Decimal? {
        let text = footerLines.joined(separator: "\n")
        // "TOTAL 171.17" or "TOTAL $171.17"
        if let m = try? Self.totalPattern.firstMatch(in: text) {
            let val = Decimal(string: normalize(String(m.1)), locale: Locale(identifier: "en_US_POSIX"))
            ScanningLog.parse.log("extractTotal: TOTAL pattern → \(val?.description ?? "nil", privacy: .public)")
            return val
        }
        // "$171.17" or "$ 171.17"
        if let m = try? Self.dollarAmountPattern.firstMatch(in: text) {
            let val = Decimal(string: normalize(String(m.1)), locale: Locale(identifier: "en_US_POSIX"))
            ScanningLog.parse.log("extractTotal: dollar pattern → \(val?.description ?? "nil", privacy: .public)")
            return val
        }
        ScanningLog.parse.log("extractTotal: → nil")
        return nil
    }

    private func extractTax(from text: String) -> Decimal? {
        var total = Decimal.zero
        var found = false
        var searchStart = text.startIndex
        while let range = text.range(
            of: #"[BD]-Taxable[^\n]*?(\d+\.\d{2})"#,
            options: .regularExpression,
            range: searchStart..<text.endIndex
        ) {
            let segment = String(text[range])
            if let numRange = segment.range(of: #"\d+\.\d{2}"#, options: [.regularExpression, .backwards]),
               let val = Decimal(string: String(segment[numRange]), locale: Locale(identifier: "en_US_POSIX")) {
                total += val
                found = true
            }
            searchStart = range.upperBound
        }
        return found ? total : nil
    }

    // MARK: - Helpers

    /// Normalize OCR artifacts: comma decimal separator → period
    private func normalize(_ s: String) -> String {
        s.replacingOccurrences(of: ",", with: ".")
    }

    /// Normalize OCR unit strings: "1b" and "ib" are common OCR misreads of "lb"
    private func normalizeUnit(_ raw: String) -> WeightUnit {
        switch raw.lowercased() {
        case "1b", "ib", "lb": return .lb
        case "oz": return .oz
        case "kg": return .kg
        default: return .lb
        }
    }

    private func reconcile(items: [ParsedLineItem], subtotal: Decimal?) -> ReconciliationStatus {
        guard let subtotal else { return .unverified }
        let itemSum = items.reduce(Decimal.zero) { $0 + $1.lineTotal }
        return abs(itemSum - subtotal) <= Decimal(string: "0.02")! ? .reconciled : .discrepancy
    }

    // priceLineIndex: when the price is on a separate line (split/mixed column), its OCR
    // confidence is multiplied in. A misread price digit lowers the item's overall confidence
    // even if the name line was read perfectly. Pass nil for inline items (same line).
    private func itemConfidence(ocrLines: [OCRLine], lineIndex: Int, canonical: String,
                                isDiscount: Bool, priceLineIndex: Int? = nil) -> Double {
        let nameConf  = lineIndex < ocrLines.count ? ocrLines[lineIndex].confidence : 0.7
        let priceConf = priceLineIndex.map { $0 < ocrLines.count ? ocrLines[$0].confidence : 0.7 } ?? 1.0
        let base = nameConf * priceConf
        let factor: Double
        if canonical.count < 3                                        { factor = 0.50 }
        else if canonical.allSatisfy({ $0.isNumber && $0.isASCII })  { factor = 0.60 }
        else if isDiscount                                            { factor = 0.90 }
        else                                                          { factor = 1.00 }
        return min(base * factor, 1.0)
    }

    private func computeConfidence(
        hasMerchant: Bool, hasDate: Bool, itemCount: Int,
        avgItemConfidence: Double, hasTotal: Bool, reconciliation: ReconciliationStatus
    ) -> Double {
        var score = 0.0
        if hasMerchant   { score += 0.15 }
        if hasDate       { score += 0.10 }
        if itemCount > 0 { score += 0.20 }  // reduced from 0.25; avgItemConfidence weight increased
        score += avgItemConfidence * 0.30   // increased from 0.25; meaningful now that it's real OCR data
        if hasTotal      { score += 0.10 }
        if reconciliation == .reconciled { score += 0.15 }
        return min(score, 1.0)
    }
}
