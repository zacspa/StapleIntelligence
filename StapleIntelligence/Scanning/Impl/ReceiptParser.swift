//
//  ReceiptParser.swift
//  StapleIntelligence
//
//  Created by Zack Sparks on 3/2/26.
//

import Foundation
import OSLog

struct ReceiptParser {

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

    private static let noiseTokenPattern    = /\b(FB|ND|FR|Ft|[ABDF])\b/
    private static let weightFragPattern    = /(?i)\s+\d+[\.,]\d+\s*(?:lb|oz|kg|1b|ib).*$/
    private static let skuPrefixPattern     = /^\d{3,9}\s+/

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

    func parse(_ rawText: String) -> ParsedReceipt {
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

        let lines = rawText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }

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
        let lineItems = extractItems(from: lines, bounds: bounds, log: d)
        d("items: \(lineItems.count) parsed")
        for (i, item) in lineItems.enumerated() {
            var info = "  [\(i)] \(item.canonicalName) = \(item.lineTotal)"
            if item.rawName.uppercased() != item.canonicalName { info += "  raw=\"\(item.rawName)\"" }
            if let qty = item.quantity, let unit = item.unit {
                info += "  \(String(format: "%.2f", qty)) \(unit)"
                if let up = item.unitPrice { info += " × \(up)/\(unit)" }
            }
            if let tc = item.taxCode { info += "  [\(tc)]" }
            if item.isDiscount { info += "  DISC" }
            d(info)
        }

        // Phase 6: Footer
        let footerLines = Array(lines[bounds.footerStart...])
        d("footer: \(footerLines.count) lines")
        for (i, line) in footerLines.enumerated() { d("  footer[\(i)] \(line)") }

        let subtotal = extractSubtotal(from: footerLines)
        let total    = extractTotal(from: footerLines)
        // Derive tax from total − subtotal when both are available; it's more reliable
        // than regex-scanning the footer because ALDI prints "D-Taxable @7.750%" (the rate,
        // not the amount) on the same line as the label, confusing the regex.
        let tax: Decimal? = {
            if let t = total, let s = subtotal, t > s { return t - s }
            return extractTax(from: footerLines.joined(separator: "\n"))
        }()
        d("footer parsed: subtotal=\(subtotal?.description ?? "<nil>") tax=\(tax?.description ?? "<nil>") total=\(total?.description ?? "<nil>")")

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

        let footerStart = min((priceEnd ?? nameEnd) + 1, lines.count)
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

    private func extractItems(from lines: [String], bounds: SectionBounds, log: (String) -> Void = { _ in }) -> [ParsedLineItem] {
        if bounds.isSplitColumn {
            let items = extractSplitColumnItems(from: lines, bounds: bounds, log: log)
            if items.count >= 9 { return items }
            // Price block had too few entries — OCR likely interleaved names and prices.
            // Fall through to mixed-column extraction of the name block.
            log("splitColumn yielded \(items.count) items — retrying as mixed column")
        }
        if bounds.foundVisa {
            // VISA detected: name block contains interleaved names and prices.
            return extractMixedColumnItems(from: lines, start: bounds.nameStart, end: bounds.nameEnd, log: log)
        }
        return extractInlineItems(from: lines, start: bounds.nameStart, end: bounds.nameEnd)
    }

    /// Single-column format: each line has SKU? + name + price + taxcode?
    private func extractInlineItems(from lines: [String], start: Int, end: Int) -> [ParsedLineItem] {
        guard start < end else { return [] }
        let section = Array(lines[start..<end])
        var items: [ParsedLineItem] = []
        var idx = 0
        while idx < section.count {
            let line = section[idx]
            guard !line.isEmpty,
                  let match = try? Self.lineItemPattern.wholeMatch(in: line) else { idx += 1; continue }
            let rawName = String(match.1)
            let priceStr = normalize(String(match.2))
            let taxCode  = match.3.map(String.init)
            guard let price = Decimal(string: priceStr, locale: Locale(identifier: "en_US_POSIX")) else { idx += 1; continue }
            let isDiscount = (try? Self.discountPattern.firstMatch(in: rawName)) != nil || price < 0
            var quantity: Double? = nil
            var unit: String? = nil
            var unitPrice: Decimal? = nil
            let nextIdx = idx + 1
            if nextIdx < section.count,
               let wm = try? Self.weightSublinePattern.wholeMatch(in: section[nextIdx]) {
                quantity = Double(normalize(String(wm.1)))
                unit = section[nextIdx].contains("lb") || section[nextIdx].contains("1b") ? "lb"
                     : section[nextIdx].contains("oz") ? "oz" : "kg"
                unitPrice = Decimal(string: normalize(String(wm.2)), locale: Locale(identifier: "en_US_POSIX"))
                idx += 1
            }
            let canonical = Self.canonicalize(rawName)
            items.append(ParsedLineItem(
                rawName: rawName, canonicalName: canonical, quantity: quantity, unit: unit,
                unitPrice: unitPrice, lineTotal: price, isDiscount: isDiscount,
                confidence: canonical.count < 3 ? 0.4 : (isDiscount ? 0.75 : 0.85),
                taxCode: taxCode))
            idx += 1
        }
        return items
    }

    /// Split-column format: name block (nameStart..<nameEnd) zipped with price block (priceStart...priceEnd)
    private func extractSplitColumnItems(from lines: [String], bounds: SectionBounds, log: (String) -> Void = { _ in }) -> [ParsedLineItem] {
        guard let priceStart = bounds.priceStart, let priceEnd = bounds.priceEnd else { return [] }

        // Collect name entries, attaching weight sub-lines to the preceding name
        struct NameEntry { var raw: String; var weightQty: Double?; var weightUnit: String?; var weightUnitPrice: Decimal? }
        var names: [NameEntry] = []

        var pendingWeightQty: Double? = nil
        var pendingWeightUnit: String? = nil

        var i = bounds.nameStart
        while i < bounds.nameEnd {
            let line = lines[i]
            defer { i += 1 }
            guard !line.isEmpty else { continue }
            // Full single-line weight sub-line (e.g. "1.51 lb x 1.95/lb")
            if let wm = try? Self.weightSublinePattern.wholeMatch(in: line) {
                if !names.isEmpty {
                    let qty  = Double(normalize(String(wm.1)))
                    let unit = line.contains("lb") || line.contains("1b") ? "lb"
                             : line.contains("oz") ? "oz" : "kg"
                    let up   = Decimal(string: normalize(String(wm.2)), locale: Locale(identifier: "en_US_POSIX"))
                    names[names.count - 1].weightQty       = qty
                    names[names.count - 1].weightUnit      = unit
                    names[names.count - 1].weightUnitPrice = up
                }
                pendingWeightQty = nil; pendingWeightUnit = nil
                continue
            }
            // Split weight fragment 1: "1.511b x" or "1.18 ib x" — stores pending metadata
            if let wf = try? Self.weightFrag1Pattern.wholeMatch(in: line) {
                pendingWeightQty  = Double(normalize(String(wf.1)))
                pendingWeightUnit = normalizeUnit(String(wf.2))
                continue
            }
            // Split weight fragment 2: "1.95/1b" — completes pending metadata on preceding item
            if let wf = try? Self.weightFrag2Pattern.wholeMatch(in: line),
               let qty = pendingWeightQty, let unit = pendingWeightUnit, !names.isEmpty {
                names[names.count - 1].weightQty       = qty
                names[names.count - 1].weightUnit      = unit
                names[names.count - 1].weightUnitPrice = Decimal(string: normalize(String(wf.1)),
                                                                  locale: Locale(identifier: "en_US_POSIX"))
                pendingWeightQty = nil; pendingWeightUnit = nil
                continue
            }
            // Not a weight fragment — clear stale pending state
            pendingWeightQty = nil; pendingWeightUnit = nil
            // Skip lines with too few alpha chars (catch-all for remaining OCR artifacts)
            let alphaCount = line.filter { $0.isLetter }.count
            guard alphaCount >= 4 else { continue }
            names.append(NameEntry(raw: line, weightQty: nil, weightUnit: nil, weightUnitPrice: nil))
        }

        // Collect price entries — use extractPrice() to capture both coded ("2.69 FB")
        // and standalone ("4.69") prices that OCR occasionally drops the tax code from.
        struct PriceEntry { var price: Decimal; var taxCode: String? }
        var prices: [PriceEntry] = []
        for i in priceStart...priceEnd {
            let line = lines[i]
            guard !line.isEmpty else { continue }
            guard let ep = extractPrice(from: line) else { continue }
            prices.append(PriceEntry(price: ep.price, taxCode: ep.taxCode))
        }

        ScanningLog.parse.debug("splitColumn: \(names.count, privacy: .public) names, \(prices.count, privacy: .public) prices")
        log("splitColumn: \(names.count) names, \(prices.count) prices")
        for (i, n) in names.enumerated() {
            var info = "  name[\(i)] \"\(n.raw)\""
            if let qty = n.weightQty, let unit = n.weightUnit {
                info += "  \(String(format: "%.2f", qty)) \(unit)"
                if let up = n.weightUnitPrice { info += " × \(up)/\(unit)" }
            }
            log(info)
        }
        for (i, p) in prices.enumerated() {
            log("  price[\(i)] \(p.price)\(p.taxCode.map { " \($0)" } ?? "")")
        }

        // Zip by index
        var items: [ParsedLineItem] = []
        let count = min(names.count, prices.count)
        for i in 0..<count {
            let nl = names[i]
            let pl = prices[i]
            let isDiscount = (try? Self.discountPattern.firstMatch(in: nl.raw)) != nil || pl.price < 0
            let canonical  = Self.canonicalize(nl.raw)
            items.append(ParsedLineItem(
                rawName: nl.raw, canonicalName: canonical,
                quantity: nl.weightQty, unit: nl.weightUnit, unitPrice: nl.weightUnitPrice,
                lineTotal: pl.price, isDiscount: isDiscount,
                confidence: canonical.count < 3 ? 0.4 : (isDiscount ? 0.75 : 0.85),
                taxCode: pl.taxCode))
        }
        return items
    }

    /// Mixed-column format: OCR interleaved names and prices in the same block.
    /// Scans [start, end) collecting names and prices independently, then zips by index.
    private func extractMixedColumnItems(from lines: [String], start: Int, end: Int, log: (String) -> Void = { _ in }) -> [ParsedLineItem] {
        struct NameEntry { var raw: String; var weightQty: Double?; var weightUnit: String?; var weightUnitPrice: Decimal? }
        struct PriceEntry { var price: Decimal; var taxCode: String? }
        var names: [NameEntry] = []
        var prices: [PriceEntry] = []
        var pendingWeightQty: Double? = nil
        var pendingWeightUnit: String? = nil

        var i = start
        while i < end {
            let line = lines[i]
            defer { i += 1 }
            guard !line.isEmpty else { continue }

            // Full single-line weight sub-line
            if let wm = try? Self.weightSublinePattern.wholeMatch(in: line) {
                if !names.isEmpty {
                    names[names.count - 1].weightQty       = Double(normalize(String(wm.1)))
                    names[names.count - 1].weightUnit      = line.contains("lb") || line.contains("1b") ? "lb"
                                                             : line.contains("oz") ? "oz" : "kg"
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

            // Price check before name check (price lines have few alpha chars)
            if let ep = extractPrice(from: line) {
                prices.append(PriceEntry(price: ep.price, taxCode: ep.taxCode))
                continue
            }
            // Name check
            guard line.filter({ $0.isLetter }).count >= 4 else { continue }
            names.append(NameEntry(raw: line, weightQty: nil, weightUnit: nil, weightUnitPrice: nil))
        }

        ScanningLog.parse.debug("mixedColumn: \(names.count, privacy: .public) names, \(prices.count, privacy: .public) prices")
        log("mixedColumn: \(names.count) names, \(prices.count) prices")
        for (i, n) in names.enumerated() {
            var info = "  name[\(i)] \"\(n.raw)\""
            if let qty = n.weightQty, let unit = n.weightUnit {
                info += "  \(String(format: "%.2f", qty)) \(unit)"
                if let up = n.weightUnitPrice { info += " × \(up)/\(unit)" }
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
            items.append(ParsedLineItem(
                rawName: nl.raw, canonicalName: canonical,
                quantity: nl.weightQty, unit: nl.weightUnit, unitPrice: nl.weightUnitPrice,
                lineTotal: pl.price, isDiscount: isDiscount,
                confidence: canonical.count < 3 ? 0.4 : (isDiscount ? 0.75 : 0.85),
                taxCode: pl.taxCode))
        }
        return items
    }

    // MARK: - Footer extraction

    private func extractSubtotal(from footerLines: [String]) -> Decimal? {
        let text = footerLines.joined(separator: "\n")
        // Inline: "SUBTOTAL 164.28"
        if let m = try? Self.subtotalInlinePattern.firstMatch(in: text) {
            return Decimal(string: normalize(String(m.1)), locale: Locale(identifier: "en_US_POSIX"))
        }
        // Split-line: "SUBTOTAL" alone, value on a subsequent line
        for (i, line) in footerLines.enumerated() {
            if (try? Self.subtotalLabelPattern.wholeMatch(in: line)) != nil {
                for j in (i + 1)..<min(i + 10, footerLines.count) {
                    let candidate = normalize(footerLines[j].trimmingCharacters(in: .whitespaces))
                    if let val = Decimal(string: candidate, locale: Locale(identifier: "en_US_POSIX")), val > 0 {
                        ScanningLog.parse.debug("subtotal: split-line match at footer[\(j, privacy: .public)] = \(val.description, privacy: .public)")
                        return val
                    }
                }
            }
        }
        return nil
    }

    private func extractTotal(from footerLines: [String]) -> Decimal? {
        let text = footerLines.joined(separator: "\n")
        // "TOTAL 171.17" or "TOTAL $171.17"
        if let m = try? Self.totalPattern.firstMatch(in: text) {
            return Decimal(string: normalize(String(m.1)), locale: Locale(identifier: "en_US_POSIX"))
        }
        // "$171.17" or "$ 171.17"
        if let m = try? Self.dollarAmountPattern.firstMatch(in: text) {
            return Decimal(string: normalize(String(m.1)), locale: Locale(identifier: "en_US_POSIX"))
        }
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
    private func normalizeUnit(_ raw: String) -> String {
        switch raw.lowercased() {
        case "1b", "ib", "lb": return "lb"
        case "oz": return "oz"
        case "kg": return "kg"
        default: return raw.lowercased()
        }
    }

    private func reconcile(items: [ParsedLineItem], subtotal: Decimal?) -> ReconciliationStatus {
        guard let subtotal else { return .unverified }
        let itemSum = items.reduce(Decimal.zero) { $0 + $1.lineTotal }
        return abs(itemSum - subtotal) <= Decimal(string: "0.02")! ? .reconciled : .discrepancy
    }

    private func computeConfidence(
        hasMerchant: Bool, hasDate: Bool, itemCount: Int,
        avgItemConfidence: Double, hasTotal: Bool, reconciliation: ReconciliationStatus
    ) -> Double {
        var score = 0.0
        if hasMerchant  { score += 0.15 }
        if hasDate      { score += 0.10 }
        if itemCount > 0 { score += 0.25 }
        score += avgItemConfidence * 0.25
        if hasTotal     { score += 0.10 }
        if reconciliation == .reconciled { score += 0.15 }
        return min(score, 1.0)
    }
}
