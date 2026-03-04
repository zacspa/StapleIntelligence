//
//  ReceiptValidation.swift
//  StapleIntelligence
//
//  Created by Zack Sparks on 3/3/26.
//

import Foundation
import CoreGraphics

// MARK: - Severity

enum ValidationSeverity: Int, Comparable {
    case info = 1, warning = 2, error = 4, critical = 8

    static func < (lhs: ValidationSeverity, rhs: ValidationSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Issue kinds

enum ValidationIssueKind {
    // Critical
    case noItemsParsed
    case globalConfidenceCritical

    // Error
    case reconciliationFailed
    case totalsMismatch

    // Warning
    case missingMerchant
    case missingDate
    case implausibleTaxRate
    case duplicateItems(count: Int)

    // Info
    case lowConfidenceItems(count: Int)
    case itemsWithZeroPrice(count: Int)
    case itemNamesAllDigits(count: Int)
    case itemNamesTooShort(count: Int)
    case itemNamesNonAlpha(count: Int)
}

// MARK: - Issue

struct ReceiptValidationIssue {
    let kind: ValidationIssueKind
    let severity: ValidationSeverity
    let associatedBoundingBox: CGRect?  // set by validator; nil for receipt-level issues

    init(kind: ValidationIssueKind, severity: ValidationSeverity, associatedBoundingBox: CGRect? = nil) {
        self.kind = kind
        self.severity = severity
        self.associatedBoundingBox = associatedBoundingBox
    }

    var title: String {
        switch kind {
        case .noItemsParsed:                return "No Items Found"
        case .globalConfidenceCritical:     return "Very Low OCR Confidence"
        case .reconciliationFailed:         return "Totals Don't Reconcile"
        case .totalsMismatch:               return "Subtotal + Tax ≠ Total"
        case .missingMerchant:              return "No Merchant Name"
        case .missingDate:                  return "No Purchase Date"
        case .implausibleTaxRate:           return "Unusual Tax Rate"
        case .duplicateItems(let n):        return "Duplicate Items (\(n))"
        case .lowConfidenceItems(let n):    return "Low-Confidence Items (\(n))"
        case .itemsWithZeroPrice(let n):    return "Items With $0 Price (\(n))"
        case .itemNamesAllDigits(let n):    return "Items With Digit-Only Names (\(n))"
        case .itemNamesTooShort(let n):     return "Very Short Item Names (\(n))"
        case .itemNamesNonAlpha(let n):     return "Items With Unusual Characters (\(n))"
        }
    }

    var detail: String {
        switch kind {
        case .noItemsParsed:
            return "The parser couldn't find any line items. The receipt may be low-quality or in an unsupported format. Rescanning often helps."
        case .globalConfidenceCritical:
            return "OCR confidence is critically low, meaning the text was difficult to read. Item names and prices may be wrong. Consider rescanning with better lighting."
        case .reconciliationFailed:
            return "The sum of line items doesn't match the subtotal on the receipt. One or more items may be missing or have incorrect prices."
        case .totalsMismatch:
            return "Subtotal plus tax doesn't equal the total shown on the receipt. A value may have been misread."
        case .missingMerchant:
            return "No store name was found. You can type one in the Merchant field before saving."
        case .missingDate:
            return "No purchase date was detected. The current date will be used. You can adjust it in the Date field."
        case .implausibleTaxRate:
            return "The tax amount is outside the expected range (0–20% of subtotal). A value may have been misread."
        case .duplicateItems(let n):
            return "\(n) item\(n == 1 ? "" : "s") appear\(n == 1 ? "s" : "") more than once with the same name and price. This can happen when the parser misreads multi-line entries."
        case .lowConfidenceItems(let n):
            return "\(n) item\(n == 1 ? "" : "s") \(n == 1 ? "has" : "have") low OCR confidence. Names or prices may be inaccurate."
        case .itemsWithZeroPrice(let n):
            return "\(n) non-discount item\(n == 1 ? "" : "s") \(n == 1 ? "has" : "have") a $0 price. The price may have been missed."
        case .itemNamesAllDigits(let n):
            return "\(n) item\(n == 1 ? "" : "s") \(n == 1 ? "has a" : "have") name\(n == 1 ? "" : "s") made up entirely of digits, which usually means a barcode or SKU was misread as a product name."
        case .itemNamesTooShort(let n):
            return "\(n) item\(n == 1 ? "" : "s") \(n == 1 ? "has" : "have") a very short name (≤2 characters), which may indicate a parsing error."
        case .itemNamesNonAlpha(let n):
            return "\(n) item\(n == 1 ? "" : "s") \(n == 1 ? "contains" : "contain") unusual characters that are not typically found in product names."
        }
    }

    var iconName: String {
        switch severity {
        case .info:     return "info.circle"
        case .warning:  return "exclamationmark.triangle"
        case .error:    return "xmark.circle"
        case .critical: return "exclamationmark.octagon"
        }
    }

    var iconColor: String {
        switch severity {
        case .info:     return "blue"
        case .warning:  return "orange"
        case .error:    return "red"
        case .critical: return "red"
        }
    }
}

// MARK: - Result

struct ReceiptValidationResult {
    let issues: [ReceiptValidationIssue]

    var totalWeight: Int { issues.reduce(0) { $0 + $1.severity.rawValue } }
    var hasCritical: Bool { issues.contains { $0.severity == .critical } }
    var requiresReview: Bool { totalWeight >= 4 }
    var preferRescan: Bool { hasCritical || totalWeight >= 12 }

    var sortedIssues: [ReceiptValidationIssue] {
        issues.sorted { $0.severity > $1.severity }
    }
}
