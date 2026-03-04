//
//  ReceiptValidator.swift
//  StapleIntelligence
//
//  Created by Zack Sparks on 3/3/26.
//

import Foundation
import CoreGraphics
import OSLog

struct ReceiptValidator {

    private let log = ScanningLog.validation

    func validate(_ receipt: ParsedReceipt) -> ReceiptValidationResult {
        var issues: [ReceiptValidationIssue] = []
        log.log("validation starting — items: \(receipt.lineItems.count, privacy: .public), parseConf: \(receipt.parseConfidence, privacy: .public), reconciliation: \(receipt.reconciliationStatus.rawValue, privacy: .public)")
        log.log("  merchant: \(receipt.merchantName ?? "<nil>", privacy: .public), date: \(receipt.purchaseDate?.description ?? "<nil>", privacy: .public)")
        log.log("  subtotal: \(receipt.subtotal?.description ?? "<nil>", privacy: .public), tax: \(receipt.tax?.description ?? "<nil>", privacy: .public), total: \(receipt.total?.description ?? "<nil>", privacy: .public)")

        // Per-item confidence and bbox availability
        let itemsWithBBox = receipt.lineItems.filter { $0.boundingBox != nil }.count
        log.log("  bboxCoverage: \(itemsWithBBox, privacy: .public)/\(receipt.lineItems.count, privacy: .public) items have bounding boxes")
        for (i, item) in receipt.lineItems.enumerated() {
            log.log("  item[\(i, privacy: .public)] conf=\(String(format: "%.3f", item.confidence), privacy: .public) total=\(item.lineTotal, privacy: .public) bbox=\(item.boundingBox != nil ? "yes" : "no", privacy: .public) name=\"\(item.canonicalName, privacy: .public)\"")
        }

        // MARK: Critical

        if receipt.lineItems.isEmpty {
            log.log("  → noItemsParsed [critical]")
            issues.append(.init(kind: .noItemsParsed, severity: .critical))
        }

        if receipt.parseConfidence < 0.35 {
            log.log("  → globalConfidenceCritical: \(receipt.parseConfidence, privacy: .public) < 0.35 [critical]")
            issues.append(.init(kind: .globalConfidenceCritical, severity: .critical))
        }

        // MARK: Error

        // Union of all item bounding boxes — used to show the full items section when
        // totals don't reconcile, letting the user see what might be missing.
        let allItemBoxes = receipt.lineItems.compactMap(\.boundingBox)
        let itemsSectionBox: CGRect? = allItemBoxes.isEmpty ? nil :
            allItemBoxes.dropFirst().reduce(allItemBoxes[0]) { $0.union($1) }
        log.log("  itemsSectionBox: \(itemsSectionBox.map { "(\(String(format: "%.3f", $0.minX)),\(String(format: "%.3f", $0.minY)) \(String(format: "%.3f", $0.width))×\(String(format: "%.3f", $0.height))" } ?? "nil", privacy: .public)")

        let itemSum = receipt.lineItems.reduce(Decimal.zero) { $0 + $1.lineTotal }
        log.log("  reconciliation: itemSum=\(itemSum, privacy: .public) vs subtotal=\(receipt.subtotal?.description ?? "<nil>", privacy: .public) → \(receipt.reconciliationStatus.rawValue, privacy: .public)")
        if receipt.reconciliationStatus == .discrepancy {
            log.log("  → reconciliationFailed: diff=\(abs(itemSum - (receipt.subtotal ?? 0)), privacy: .public) [error]")
            issues.append(.init(kind: .reconciliationFailed, severity: .error, associatedBoundingBox: itemsSectionBox))
        }

        if let subtotal = receipt.subtotal, let tax = receipt.tax, let total = receipt.total {
            let computed = subtotal + tax
            let diff = abs(computed - total)
            log.log("  totalsMismatch check: subtotal(\(subtotal, privacy: .public)) + tax(\(tax, privacy: .public)) = \(computed, privacy: .public) vs total(\(total, privacy: .public)) diff=\(diff, privacy: .public)")
            if diff > Decimal(string: "0.02")! {
                log.log("  → totalsMismatch [error]")
                issues.append(.init(kind: .totalsMismatch, severity: .error, associatedBoundingBox: itemsSectionBox))
            }
        } else {
            log.log("  totalsMismatch check: skipped — missing subtotal/tax/total")
        }

        // MARK: Warning

        if (receipt.merchantName ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
            log.log("  → missingMerchant [warning]")
            issues.append(.init(kind: .missingMerchant, severity: .warning))
        }

        if receipt.purchaseDate == nil {
            log.log("  → missingDate [warning]")
            issues.append(.init(kind: .missingDate, severity: .warning))
        }

        if let subtotal = receipt.subtotal, subtotal != 0, let tax = receipt.tax {
            let rate = tax / subtotal
            log.log("  taxRate check: tax(\(tax, privacy: .public)) / subtotal(\(subtotal, privacy: .public)) = \(rate, privacy: .public)")
            if rate < 0 || rate > Decimal(string: "0.20")! {
                log.log("  → implausibleTaxRate: \(rate, privacy: .public) outside [0, 0.20] [warning]")
                issues.append(.init(kind: .implausibleTaxRate, severity: .warning))
            }
        } else {
            log.log("  taxRate check: skipped — missing subtotal or tax")
        }

        let (duplicateCount, duplicateBBox): (Int, CGRect?) = {
            var seen = [String: Int]()
            var firstDupBox: CGRect? = nil
            for item in receipt.lineItems {
                let key = "\(item.rawName)||\(item.lineTotal)"
                seen[key, default: 0] += 1
                if seen[key] == 2 && firstDupBox == nil {
                    firstDupBox = item.boundingBox
                    log.log("  duplicate found: \"\(item.canonicalName, privacy: .public)\" @ \(item.lineTotal, privacy: .public)")
                }
            }
            return (seen.values.filter { $0 >= 2 }.reduce(0) { $0 + $1 }, firstDupBox)
        }()
        if duplicateCount > 0 {
            log.log("  → duplicateItems: \(duplicateCount, privacy: .public) [warning]")
            issues.append(.init(kind: .duplicateItems(count: duplicateCount), severity: .warning, associatedBoundingBox: duplicateBBox))
        }

        // MARK: Info (aggregated)

        let lowConfidenceCount = receipt.lineItems.filter { $0.confidence < 0.9 }.count
        log.log("  lowConf check: \(lowConfidenceCount, privacy: .public) items below 0.9 threshold")
        for item in receipt.lineItems where item.confidence < 0.9 {
            log.log("    lowConf item: conf=\(String(format: "%.3f", item.confidence), privacy: .public) \"\(item.canonicalName, privacy: .public)\"")
        }
        if lowConfidenceCount > 0 {
            let box = receipt.lineItems.first(where: { $0.confidence < 0.9 })?.boundingBox
            log.log("  → lowConfidenceItems: \(lowConfidenceCount, privacy: .public) [info]")
            issues.append(.init(kind: .lowConfidenceItems(count: lowConfidenceCount), severity: .info, associatedBoundingBox: box))
        }

        let zeroPriceCount = receipt.lineItems.filter { $0.lineTotal == 0 && !$0.isDiscount }.count
        if zeroPriceCount > 0 {
            log.log("  → itemsWithZeroPrice: \(zeroPriceCount, privacy: .public) [info]")
            let box = receipt.lineItems.first(where: { $0.lineTotal == 0 && !$0.isDiscount })?.boundingBox
            issues.append(.init(kind: .itemsWithZeroPrice(count: zeroPriceCount), severity: .info, associatedBoundingBox: box))
        }

        let allDigitsCount = receipt.lineItems.filter { $0.canonicalName.allSatisfy(\.isNumber) }.count
        if allDigitsCount > 0 {
            log.log("  → itemNamesAllDigits: \(allDigitsCount, privacy: .public) [info]")
            let box = receipt.lineItems.first(where: { $0.canonicalName.allSatisfy({ $0.isNumber && $0.isASCII }) })?.boundingBox
            issues.append(.init(kind: .itemNamesAllDigits(count: allDigitsCount), severity: .info, associatedBoundingBox: box))
        }

        let tooShortCount = receipt.lineItems.filter { !$0.canonicalName.isEmpty && $0.canonicalName.count <= 2 }.count
        if tooShortCount > 0 {
            log.log("  → itemNamesTooShort: \(tooShortCount, privacy: .public) [info]")
            let box = receipt.lineItems.first(where: { !$0.canonicalName.isEmpty && $0.canonicalName.count <= 2 })?.boundingBox
            issues.append(.init(kind: .itemNamesTooShort(count: tooShortCount), severity: .info, associatedBoundingBox: box))
        }

        let allowedCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 /-.")
        let nonAlphaCount = receipt.lineItems.filter {
            $0.rawName.unicodeScalars.contains { !allowedCharacters.contains($0) }
        }.count
        if nonAlphaCount > 0 {
            log.log("  → itemNamesNonAlpha: \(nonAlphaCount, privacy: .public) [info]")
            let box = receipt.lineItems.first(where: {
                $0.rawName.unicodeScalars.contains { !allowedCharacters.contains($0) }
            })?.boundingBox
            issues.append(.init(kind: .itemNamesNonAlpha(count: nonAlphaCount), severity: .info, associatedBoundingBox: box))
        }

        let result = ReceiptValidationResult(issues: issues)
        if issues.isEmpty {
            log.log("validation passed — no issues")
        } else {
            log.log("validation complete — issueCount: \(issues.count, privacy: .public), totalWeight: \(result.totalWeight, privacy: .public), requiresReview: \(result.requiresReview, privacy: .public), preferRescan: \(result.preferRescan, privacy: .public)")
            for issue in result.sortedIssues {
                log.log("  issue: \(issue.title, privacy: .public) [severity: \(issue.severity.rawValue, privacy: .public), hasBBox: \(issue.associatedBoundingBox != nil ? "yes" : "no", privacy: .public)]")
            }
        }
        return result
    }
}
