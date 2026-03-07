//
//  ReceiptValidation.swift
//  StapleIntelligence
//
//  Created by Zack Sparks on 3/3/26.
//

import Foundation
import CoreGraphics

// MARK: - Severity

/// Numeric weight assigned to each issue. The raw values are additive:
/// a single `error` (4) alone triggers review; two `warning`s (2+2=4) do the same.
/// `critical` (8) alone sets `preferRescan`. See `ReceiptValidationResult`.
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
    case skuPriceConflict(count: Int)

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

// MARK: - Issue instance

/// Per-instance metadata for a SKU price conflict — the two prices that disagreed.
struct SKUConflictInfo {
    let sku: String
    let prices: [Decimal]  // the two conflicting prices, sorted ascending
}

/// One swipeable page of a validation issue card.
/// `bboxes` holds one or more Vision-coordinate rects cropped into a single composite image:
/// one rect → single strip; two rects → two strips stacked vertically (skuPriceConflict).
/// `skuConflict` is non-nil only for skuPriceConflict instances.
struct ValidationIssueInstance {
    let bboxes: [CGRect]
    let skuConflict: SKUConflictInfo?

    init(bboxes: [CGRect], skuConflict: SKUConflictInfo? = nil) {
        self.bboxes = bboxes
        self.skuConflict = skuConflict
    }
}

// MARK: - Issue

struct ReceiptValidationIssue {
    let kind: ValidationIssueKind
    let severity: ValidationSeverity
    /// Per-instance bounding boxes. Empty for receipt-level issues with no image crops.
    let instances: [ValidationIssueInstance]

    init(kind: ValidationIssueKind, severity: ValidationSeverity,
         instances: [ValidationIssueInstance] = []) {
        self.kind = kind
        self.severity = severity
        self.instances = instances
    }

    /// Convenience: the first bbox of the first instance (used for relevance checks).
    var firstBBox: CGRect? { instances.first?.bboxes.first }

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
        case .skuPriceConflict(let n):      return "SKU Price Conflict (\(n))"
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
        case .skuPriceConflict(let n):
            return "\(n) SKU\(n == 1 ? "" : "s") appear\(n == 1 ? "s" : "") at more than one price on this receipt. This usually means OCR misread a digit in the price column. Check the flagged items carefully."
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

/// Aggregated outcome of a `ReceiptValidator` run.
///
/// **Review thresholds** (based on additive severity weights):
/// - `requiresReview` (weight ≥ 4): show `ValidationReviewView` before saving.
///   Triggered by any single `error`/`critical`, or two or more `warning`s.
/// - `preferRescan` (critical present, OR weight ≥ 12): the "Rescan" action is
///   shown as the primary CTA in `ValidationReviewView`.
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
