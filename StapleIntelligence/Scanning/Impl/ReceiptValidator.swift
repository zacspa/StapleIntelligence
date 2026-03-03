//
//  ReceiptValidator.swift
//  StapleIntelligence
//
//  Created by Zack Sparks on 3/3/26.
//

import Foundation

struct ReceiptValidator {

    func validate(_ receipt: ParsedReceipt) -> ReceiptValidationResult {
        var issues: [ReceiptValidationIssue] = []

        // MARK: Critical

        if receipt.lineItems.isEmpty {
            issues.append(.init(kind: .noItemsParsed, severity: .critical))
        }

        if receipt.parseConfidence < 0.35 {
            issues.append(.init(kind: .globalConfidenceCritical, severity: .critical))
        }

        // MARK: Error

        if receipt.reconciliationStatus == .discrepancy {
            issues.append(.init(kind: .reconciliationFailed, severity: .error))
        }

        if let subtotal = receipt.subtotal, let tax = receipt.tax, let total = receipt.total {
            let diff = abs((subtotal + tax) - total)
            if diff > Decimal(string: "0.02")! {
                issues.append(.init(kind: .totalsMismatch, severity: .error))
            }
        }

        // MARK: Warning

        if (receipt.merchantName ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append(.init(kind: .missingMerchant, severity: .warning))
        }

        if receipt.purchaseDate == nil {
            issues.append(.init(kind: .missingDate, severity: .warning))
        }

        if let subtotal = receipt.subtotal, subtotal != 0, let tax = receipt.tax {
            let rate = tax / subtotal
            if rate < 0 || rate > Decimal(string: "0.20")! {
                issues.append(.init(kind: .implausibleTaxRate, severity: .warning))
            }
        }

        let duplicateCount: Int = {
            var seen = [String: Int]()
            for item in receipt.lineItems {
                let key = "\(item.rawName)||\(item.lineTotal)"
                seen[key, default: 0] += 1
            }
            return seen.values.filter { $0 >= 2 }.reduce(0) { $0 + $1 }
        }()
        if duplicateCount > 0 {
            issues.append(.init(kind: .duplicateItems(count: duplicateCount), severity: .warning))
        }

        // MARK: Info (aggregated)

        let lowConfidenceCount = receipt.lineItems.filter { $0.confidence < 0.6 }.count
        if lowConfidenceCount > 0 {
            issues.append(.init(kind: .lowConfidenceItems(count: lowConfidenceCount), severity: .info))
        }

        let zeroPriceCount = receipt.lineItems.filter { $0.lineTotal == 0 && !$0.isDiscount }.count
        if zeroPriceCount > 0 {
            issues.append(.init(kind: .itemsWithZeroPrice(count: zeroPriceCount), severity: .info))
        }

        let allDigitsCount = receipt.lineItems.filter { $0.canonicalName.allSatisfy(\.isNumber) }.count
        if allDigitsCount > 0 {
            issues.append(.init(kind: .itemNamesAllDigits(count: allDigitsCount), severity: .info))
        }

        let tooShortCount = receipt.lineItems.filter { !$0.canonicalName.isEmpty && $0.canonicalName.count <= 2 }.count
        if tooShortCount > 0 {
            issues.append(.init(kind: .itemNamesTooShort(count: tooShortCount), severity: .info))
        }

        let allowedCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 /-.")
        let nonAlphaCount = receipt.lineItems.filter {
            $0.rawName.unicodeScalars.contains { !allowedCharacters.contains($0) }
        }.count
        if nonAlphaCount > 0 {
            issues.append(.init(kind: .itemNamesNonAlpha(count: nonAlphaCount), severity: .info))
        }

        return ReceiptValidationResult(issues: issues)
    }
}
