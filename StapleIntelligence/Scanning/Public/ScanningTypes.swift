//
//  ScanningTypes.swift
//  StapleIntelligence
//
//  Created by Zack Sparks on 3/2/26.
//

import Foundation
import CoreGraphics

// MARK: - OCR line type

/// A single recognized text observation from VisionKit.
///
/// `boundingBox` uses Vision's bottom-left coordinate system (normalized 0–1).
/// It is `nil` for pages beyond the first because multi-page crop coordinates
/// would silently reference the wrong image.
struct OCRLine: Sendable {
    let text: String
    let confidence: Double
    let boundingBox: CGRect?  // nil for pages > 0 (multi-page; see OCR service)
}

// MARK: - Transient parsed value types

/// Transient (non-persisted) representation of one line item produced by `ReceiptParser`.
/// Converted to a `LineItem` SwiftData model by `ReceiptPersistenceService` after review.
struct ParsedLineItem {
    let rawName: String
    let canonicalName: String
    let itemType: ItemType
    let unitPrice: Decimal?
    let lineTotal: Decimal
    let isDiscount: Bool
    let confidence: Double
    let taxCode: String?
    let sku: String?
    let boundingBox: CGRect?  // Vision-normalized bottom-left origin; nil if unavailable

    var isWeightItem: Bool {
        if case .byWeight = itemType { return true }
        return false
    }
}

/// Transient (non-persisted) result of a full `ReceiptParser` run.
/// `Identifiable` so it can drive a `.sheet(item:)` in `ReceiptsView`.
struct ParsedReceipt: Identifiable {
    let id: UUID = UUID()
    let rawOcrText: String
    let merchantName: String?
    let purchaseDate: Date?
    let lineItems: [ParsedLineItem]
    let subtotal: Decimal?
    let tax: Decimal?
    let total: Decimal?
    let parseConfidence: Double
    let reconciliationStatus: ReconciliationStatus
}

// MARK: - Error types

/// Camera/document-scanning errors (code range 1000–1099).
/// `recoverable` indicates whether the user can retry without changing settings.
enum ScanError: Error {
    case userCancelled           // 1001
    case cameraPermissionDenied  // 1002
    case noPages                 // 1003
    case underlyingError(Error)  // 1099

    var code: Int {
        switch self {
        case .userCancelled:          return 1001
        case .cameraPermissionDenied: return 1002
        case .noPages:                return 1003
        case .underlyingError:        return 1099
        }
    }

    var recoverable: Bool {
        switch self {
        case .userCancelled:          return true
        case .cameraPermissionDenied: return false
        case .noPages:                return true
        case .underlyingError:        return false
        }
    }
}

/// Vision OCR errors (code range 2000–2099).
enum OCRError: Error {
    case noTextFound                         // 2001
    case belowConfidenceThreshold(Double)    // 2002
    case requestFailed(Error)                // 2099

    var code: Int {
        switch self {
        case .noTextFound:                return 2001
        case .belowConfidenceThreshold:   return 2002
        case .requestFailed:              return 2099
        }
    }

    var recoverable: Bool {
        switch self {
        case .noTextFound:              return true
        case .belowConfidenceThreshold: return true
        case .requestFailed:            return false
        }
    }
}

/// Receipt-parsing errors (code range 3000–3099). Always recoverable — the user can rescan.
enum ParseError: Error {
    case emptyInput                       // 3001
    case noLineItemsFound(lineCount: Int) // 3002

    var code: Int {
        switch self {
        case .emptyInput:         return 3001
        case .noLineItemsFound:   return 3002
        }
    }

    var recoverable: Bool { true }
}

/// SwiftData / image persistence errors (code range 4000–4099). Never recoverable.
enum PersistenceError: Error {
    case imageWriteFailed(pageIndex: Int, underlyingCode: Int)     // 4001
    case modelContextSaveFailed(underlyingCode: Int)               // 4002

    var code: Int {
        switch self {
        case .imageWriteFailed:         return 4001
        case .modelContextSaveFailed:   return 4002
        }
    }

    var recoverable: Bool { false }
}
