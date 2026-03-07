//
//  ScanningTypes.swift
//  StapleIntelligence
//
//  Created by Zack Sparks on 3/2/26.
//

import Foundation
import CoreGraphics

// MARK: - OCR line type

struct OCRLine: Sendable {
    let text: String
    let confidence: Double
    let boundingBox: CGRect?  // nil for pages > 0 (multi-page; see OCR service)
}

// MARK: - Transient parsed value types

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
