//
//  ReceiptValidator.swift
//  StapleIntelligence
//
//  Created by Zack Sparks on 3/3/26.
//

import Foundation
import CoreGraphics
import OSLog

/// Runs a battery of checks on a `ParsedReceipt` and returns a `ReceiptValidationResult`.
///
/// **Checks are split into four tiers** (critical → error → warning → info) with
/// additive severity weights. Whether to run most checks is user-configurable via
/// `UserDefaults` keys mirrored in `SettingsView`. Two checks always run regardless
/// of settings: `checkNoItems` and `checkGlobalConfidence`.
///
/// **Bounding box usage**: many checks attach Vision-coordinate `CGRect` instances to
/// their issue instances. These are passed through to `ValidationReviewView`, which
/// crops the relevant receipt region and shows it as a visual card alongside the
/// issue description.
struct ReceiptValidator {

    private let log = ScanningLog.validation

    // MARK: - Public API

    func validate(_ receipt: ParsedReceipt) -> ReceiptValidationResult {
        log.log("validation starting — items: \(receipt.lineItems.count, privacy: .public), parseConf: \(receipt.parseConfidence, privacy: .public), reconciliation: \(receipt.reconciliationStatus.rawValue, privacy: .public)")
        log.log("  merchant: \(receipt.merchantName ?? "<nil>", privacy: .public), date: \(receipt.purchaseDate?.description ?? "<nil>", privacy: .public)")
        log.log("  subtotal: \(receipt.subtotal?.description ?? "<nil>", privacy: .public), tax: \(receipt.tax?.description ?? "<nil>", privacy: .public), total: \(receipt.total?.description ?? "<nil>", privacy: .public)")
        let itemsWithBBox = receipt.lineItems.filter { $0.boundingBox != nil }.count
        log.log("  bboxCoverage: \(itemsWithBBox, privacy: .public)/\(receipt.lineItems.count, privacy: .public) items have bounding boxes")
        for (i, item) in receipt.lineItems.enumerated() {
            log.log("  item[\(i, privacy: .public)] conf=\(String(format: "%.3f", item.confidence), privacy: .public) total=\(item.lineTotal, privacy: .public) bbox=\(item.boundingBox != nil ? "yes" : "no", privacy: .public) name=\"\(item.canonicalName, privacy: .public)\"")
        }

        let bottomRegion = Self.bottomRegion(for: receipt.lineItems)
        log.log("  bottomRegion: \(bottomRegion.map { "(\(String(format: "%.3f", $0.minX)),\(String(format: "%.3f", $0.minY)) \(String(format: "%.3f", $0.width))×\(String(format: "%.3f", $0.height))" } ?? "nil", privacy: .public)")

        let issues = [
            checkNoItems(receipt.lineItems),
            checkGlobalConfidence(receipt.parseConfidence),
            Self.detectPriceConflicts ? checkSkuPriceConflicts(receipt.lineItems) : nil,
            Self.detectReconciliation ? checkReconciliation(status: receipt.reconciliationStatus, items: receipt.lineItems, bottomRegion: bottomRegion) : nil,
            Self.detectReconciliation ? checkTotalsMismatch(subtotal: receipt.subtotal, tax: receipt.tax, total: receipt.total, bottomRegion: bottomRegion) : nil,
            Self.detectMissingData ? checkMissingMerchant(receipt.merchantName) : nil,
            Self.detectMissingData ? checkMissingDate(receipt.purchaseDate, headerRegion: Self.headerRegion(for: receipt.lineItems)) : nil,
            Self.detectTaxRate ? checkTaxRate(subtotal: receipt.subtotal, tax: receipt.tax) : nil,
            Self.detectDuplicates ? checkDuplicateItems(receipt.lineItems) : nil,
            Self.detectItemQuality ? checkLowConfidenceItems(receipt.lineItems) : nil,
            Self.detectItemQuality ? checkZeroPriceItems(receipt.lineItems) : nil,
            Self.detectItemQuality ? checkAllDigitNames(receipt.lineItems) : nil,
            Self.detectItemQuality ? checkTooShortNames(receipt.lineItems) : nil,
            Self.detectItemQuality ? checkNonAlphaNames(receipt.lineItems) : nil,
        ].compactMap { $0 }

        let result = ReceiptValidationResult(issues: issues)
        if issues.isEmpty {
            log.log("validation passed — no issues")
        } else {
            log.log("validation complete — issueCount: \(issues.count, privacy: .public), totalWeight: \(result.totalWeight, privacy: .public), requiresReview: \(result.requiresReview, privacy: .public), preferRescan: \(result.preferRescan, privacy: .public)")
            for issue in result.sortedIssues {
                log.log("  issue: \(issue.title, privacy: .public) [severity: \(issue.severity.rawValue, privacy: .public), instances: \(issue.instances.count, privacy: .public), hasBBox: \(issue.firstBBox != nil ? "yes" : "no", privacy: .public)]")
            }
        }
        return result
    }

    // MARK: - Bbox helpers

    // Fallback header region used when no item bounding boxes are available.
    private static let headerRegionFallback = CGRect(x: 0, y: 0.85, width: 1.0, height: 0.15)

    // In Vision coords (bottom-left origin), the highest maxY among all item boxes is the
    // upper edge of the first item — everything above it is the receipt header.
    static func headerRegion(for items: [ParsedLineItem]) -> CGRect {
        guard let topItemBox = items.compactMap(\.boundingBox).max(by: { $0.maxY < $1.maxY }),
              topItemBox.maxY < 1.0
        else { return headerRegionFallback }
        let y = topItemBox.maxY
        return CGRect(x: 0, y: y, width: 1.0, height: 1.0 - y)
    }

    // Crop from the bottom-most item's upper edge (maxY) down to the footer (y=0),
    // showing the last item + totals section where discrepancies typically live.
    static func bottomRegion(for items: [ParsedLineItem]) -> CGRect? {
        items.compactMap(\.boundingBox)
            .min(by: { $0.minY < $1.minY })
            .map { CGRect(x: 0, y: 0, width: 1.0, height: $0.maxY) }
    }

    // MARK: - Critical checks

    func checkNoItems(_ items: [ParsedLineItem]) -> ReceiptValidationIssue? {
        guard items.isEmpty else { return nil }
        log.log("  → noItemsParsed [critical]")
        return .init(kind: .noItemsParsed, severity: .critical, instances: [])
    }

    func checkGlobalConfidence(_ confidence: Double) -> ReceiptValidationIssue? {
        guard confidence < 0.35 else { return nil }
        log.log("  → globalConfidenceCritical: \(confidence, privacy: .public) < 0.35 [critical]")
        return .init(kind: .globalConfidenceCritical, severity: .critical, instances: [])
    }

    // MARK: - Error checks

    // Same SKU at more than one unit price — likely an OCR digit error in the price column.
    // Checked before reconciliation since a conflict is the probable cause of a sum discrepancy.
    // One instance per conflicting SKU; each instance holds the two items' bboxes for stacked crops.
    func checkSkuPriceConflicts(_ items: [ParsedLineItem]) -> ReceiptValidationIssue? {
        struct SKUEntry { var price: Decimal; var bbox: CGRect? }
        var skuEntries: [String: SKUEntry] = [:]
        var conflictSKUs = Set<String>()
        var instances: [ValidationIssueInstance] = []

        for item in items {
            guard let sku = item.sku else { continue }
            let price = item.unitPrice ?? item.lineTotal
            if let entry = skuEntries[sku] {
                if entry.price != price && !conflictSKUs.contains(sku) {
                    conflictSKUs.insert(sku)
                    log.log("  skuPriceConflict: SKU \(sku, privacy: .public) saw \(entry.price, privacy: .public) then \(price, privacy: .public)")
                    let sortedPrices = [entry.price, price].sorted(by: <)
                    instances.append(.init(
                        bboxes: [entry.bbox, item.boundingBox].compactMap { $0 },
                        skuConflict: .init(sku: sku, prices: sortedPrices)
                    ))
                }
            } else {
                skuEntries[sku] = SKUEntry(price: price, bbox: item.boundingBox)
            }
        }

        guard !conflictSKUs.isEmpty else { return nil }
        log.log("  → skuPriceConflict: \(conflictSKUs.count, privacy: .public) SKUs [error]")
        return .init(kind: .skuPriceConflict(count: conflictSKUs.count), severity: .error, instances: instances)
    }

    func checkReconciliation(status: ReconciliationStatus, items: [ParsedLineItem],
                             bottomRegion: CGRect?) -> ReceiptValidationIssue? {
        guard status == .discrepancy else { return nil }
        let itemSum = items.reduce(Decimal.zero) { $0 + $1.lineTotal }
        log.log("  → reconciliationFailed: itemSum=\(itemSum, privacy: .public) [error]")
        let instances: [ValidationIssueInstance] = bottomRegion.map { [.init(bboxes: [$0])] } ?? []
        return .init(kind: .reconciliationFailed, severity: .error, instances: instances)
    }

    func checkTotalsMismatch(subtotal: Decimal?, tax: Decimal?, total: Decimal?,
                             bottomRegion: CGRect?) -> ReceiptValidationIssue? {
        guard let subtotal, let tax, let total else {
            log.log("  totalsMismatch check: skipped — missing subtotal/tax/total")
            return nil
        }
        let diff = abs(subtotal + tax - total)
        log.log("  totalsMismatch check: subtotal(\(subtotal, privacy: .public)) + tax(\(tax, privacy: .public)) = \(subtotal + tax, privacy: .public) vs total(\(total, privacy: .public)) diff=\(diff, privacy: .public)")
        guard diff > Decimal(string: "0.02")! else { return nil }
        log.log("  → totalsMismatch [error]")
        let instances: [ValidationIssueInstance] = bottomRegion.map { [.init(bboxes: [$0])] } ?? []
        return .init(kind: .totalsMismatch, severity: .error, instances: instances)
    }

    // MARK: - Warning checks

    func checkMissingMerchant(_ name: String?) -> ReceiptValidationIssue? {
        guard (name ?? "").trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        log.log("  → missingMerchant [warning]")
        return .init(kind: .missingMerchant, severity: .warning, instances: [])
    }

    func checkMissingDate(_ date: Date?, headerRegion: CGRect) -> ReceiptValidationIssue? {
        guard date == nil else { return nil }
        log.log("  → missingDate [warning]")
        return .init(kind: .missingDate, severity: .warning, instances: [.init(bboxes: [headerRegion])])
    }

    func checkTaxRate(subtotal: Decimal?, tax: Decimal?) -> ReceiptValidationIssue? {
        guard let subtotal, subtotal != 0, let tax else {
            log.log("  taxRate check: skipped — missing subtotal or tax")
            return nil
        }
        let rate = tax / subtotal
        log.log("  taxRate check: tax(\(tax, privacy: .public)) / subtotal(\(subtotal, privacy: .public)) = \(rate, privacy: .public)")
        guard rate < 0 || rate > Decimal(string: "0.20")! else { return nil }
        log.log("  → implausibleTaxRate: \(rate, privacy: .public) outside [0, 0.20] [warning]")
        return .init(kind: .implausibleTaxRate, severity: .warning, instances: [])
    }

    func checkDuplicateItems(_ items: [ParsedLineItem]) -> ReceiptValidationIssue? {
        struct DupEntry { var count: Int; var bbox: CGRect?; var name: String; var total: Decimal }
        var seen = [String: DupEntry]()
        for item in items {
            let key = "\(item.rawName)||\(item.lineTotal)"
            if seen[key] == nil {
                seen[key] = DupEntry(count: 1, bbox: item.boundingBox, name: item.canonicalName, total: item.lineTotal)
            } else {
                seen[key]!.count += 1
                if seen[key]!.count == 2 {
                    log.log("  duplicate found: \"\(item.canonicalName, privacy: .public)\" @ \(item.lineTotal, privacy: .public)")
                }
            }
        }
        let dupeEntries = seen.values.filter { $0.count >= 2 }
        guard !dupeEntries.isEmpty else { return nil }
        let count = dupeEntries.reduce(0) { $0 + $1.count }
        let instances = dupeEntries.map { ValidationIssueInstance(bboxes: [$0.bbox].compactMap { $0 }) }
        log.log("  → duplicateItems: \(count, privacy: .public) [warning]")
        return .init(kind: .duplicateItems(count: count), severity: .warning, instances: instances)
    }

    // MARK: - Info checks

    func checkLowConfidenceItems(_ items: [ParsedLineItem]) -> ReceiptValidationIssue? {
        let low = items.filter { $0.confidence < 0.9 }
        log.log("  lowConf check: \(low.count, privacy: .public) items below 0.9 threshold")
        for item in low {
            log.log("    lowConf item: conf=\(String(format: "%.3f", item.confidence), privacy: .public) \"\(item.canonicalName, privacy: .public)\"")
        }
        guard !low.isEmpty else { return nil }
        log.log("  → lowConfidenceItems: \(low.count, privacy: .public) [info]")
        let instances = low.map { ValidationIssueInstance(bboxes: [$0.boundingBox].compactMap { $0 }) }
        return .init(kind: .lowConfidenceItems(count: low.count), severity: .info, instances: instances)
    }

    func checkZeroPriceItems(_ items: [ParsedLineItem]) -> ReceiptValidationIssue? {
        let zero = items.filter { $0.lineTotal == 0 && !$0.isDiscount }
        guard !zero.isEmpty else { return nil }
        log.log("  → itemsWithZeroPrice: \(zero.count, privacy: .public) [info]")
        let instances = zero.map { ValidationIssueInstance(bboxes: [$0.boundingBox].compactMap { $0 }) }
        return .init(kind: .itemsWithZeroPrice(count: zero.count), severity: .info, instances: instances)
    }

    func checkAllDigitNames(_ items: [ParsedLineItem]) -> ReceiptValidationIssue? {
        let allDigits = items.filter { $0.canonicalName.allSatisfy(\.isNumber) }
        guard !allDigits.isEmpty else { return nil }
        log.log("  → itemNamesAllDigits: \(allDigits.count, privacy: .public) [info]")
        let instances = allDigits.map { ValidationIssueInstance(bboxes: [$0.boundingBox].compactMap { $0 }) }
        return .init(kind: .itemNamesAllDigits(count: allDigits.count), severity: .info, instances: instances)
    }

    func checkTooShortNames(_ items: [ParsedLineItem]) -> ReceiptValidationIssue? {
        let tooShort = items.filter { !$0.canonicalName.isEmpty && $0.canonicalName.count <= 2 }
        guard !tooShort.isEmpty else { return nil }
        log.log("  → itemNamesTooShort: \(tooShort.count, privacy: .public) [info]")
        let instances = tooShort.map { ValidationIssueInstance(bboxes: [$0.boundingBox].compactMap { $0 }) }
        return .init(kind: .itemNamesTooShort(count: tooShort.count), severity: .info, instances: instances)
    }

    func checkNonAlphaNames(_ items: [ParsedLineItem]) -> ReceiptValidationIssue? {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 /-.")
        let nonAlpha = items.filter { $0.rawName.unicodeScalars.contains { !allowed.contains($0) } }
        guard !nonAlpha.isEmpty else { return nil }
        log.log("  → itemNamesNonAlpha: \(nonAlpha.count, privacy: .public) [info]")
        let instances = nonAlpha.map { ValidationIssueInstance(bboxes: [$0.boundingBox].compactMap { $0 }) }
        return .init(kind: .itemNamesNonAlpha(count: nonAlpha.count), severity: .info, instances: instances)
    }
}

// MARK: - User-configurable detection settings

extension ReceiptValidator {
    static var detectReconciliation: Bool {
        get { UserDefaults.standard.object(forKey: "validator.reconciliation") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "validator.reconciliation") }
    }
    static var detectPriceConflicts: Bool {
        get { UserDefaults.standard.object(forKey: "validator.priceConflicts") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "validator.priceConflicts") }
    }
    static var detectMissingData: Bool {
        get { UserDefaults.standard.object(forKey: "validator.missingData") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "validator.missingData") }
    }
    static var detectTaxRate: Bool {
        get { UserDefaults.standard.object(forKey: "validator.taxRate") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "validator.taxRate") }
    }
    static var detectDuplicates: Bool {
        get { UserDefaults.standard.object(forKey: "validator.duplicates") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "validator.duplicates") }
    }
    static var detectItemQuality: Bool {
        get { UserDefaults.standard.object(forKey: "validator.itemQuality") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "validator.itemQuality") }
    }
}
