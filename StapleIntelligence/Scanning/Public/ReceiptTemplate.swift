//
//  ReceiptTemplate.swift
//  StapleIntelligence
//

import Foundation
import CoreGraphics

// MARK: - Field label enum

/// Semantic role assigned to an OCR bounding-box region during receipt template labeling.
enum ReceiptFieldLabel: String, Codable, CaseIterable {
    case merchantName
    case purchaseDate
    case lineItemName
    case lineItemPrice
    case subtotal
    case tax
    case total
    case discount
    case ignore

    var displayName: String {
        switch self {
        case .merchantName:  return "Merchant Name"
        case .purchaseDate:  return "Purchase Date"
        case .lineItemName:  return "Item Name"
        case .lineItemPrice: return "Item Price"
        case .subtotal:      return "Subtotal"
        case .tax:           return "Tax"
        case .total:         return "Total"
        case .discount:      return "Discount"
        case .ignore:        return "Ignore"
        }
    }

    var systemImage: String {
        switch self {
        case .merchantName:  return "storefront"
        case .purchaseDate:  return "calendar"
        case .lineItemName:  return "tag"
        case .lineItemPrice: return "dollarsign.circle"
        case .subtotal:      return "sum"
        case .tax:           return "percent"
        case .total:         return "cart"
        case .discount:      return "minus.circle"
        case .ignore:        return "xmark.circle"
        }
    }
}

// MARK: - Codable geometry

/// A `CGRect` wrapper that is `Codable`.
///
/// Stores **Vision-normalized coordinates**: origin at the bottom-left corner of the image,
/// with `x` and `y` values in the range 0–1. This matches `OCRLine.boundingBox` and the
/// coordinate space used by `VNRecognizeTextRequest` observations.
///
/// When rendering bounding boxes onto a UIKit or SwiftUI image (which uses a top-left origin),
/// the Y axis must be flipped: `displayMinY = (1 − vision.maxY) × displayHeight`.
struct CodableCGRect: Codable, Equatable {
    var x, y, width, height: Double
    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }

    init(_ r: CGRect) {
        x = r.origin.x
        y = r.origin.y
        width = r.width
        height = r.height
    }
}

// MARK: - Template field

/// A single labeled region within a `ReceiptLayoutTemplate`.
struct TemplateField: Codable, Identifiable {
    var id: UUID
    var label: ReceiptFieldLabel
    /// Bounding region in Vision-normalized coordinates (bottom-left origin, 0–1 range).
    var region: CodableCGRect
    /// Representative OCR text captured during labeling (for future confidence checks).
    var anchorText: String?

    init(id: UUID = UUID(), label: ReceiptFieldLabel, region: CGRect, anchorText: String? = nil) {
        self.id = id
        self.label = label
        self.region = CodableCGRect(region)
        self.anchorText = anchorText
    }
}

// MARK: - Codable OCR line

/// A `Codable` wrapper around `OCRLine` for persisting the OCR lines captured during a
/// labeling session.
///
/// `OCRLine` cannot be directly encoded because `CGRect` does not conform to `Codable`.
/// `CodableOCRLine` bridges this by storing `boundingBox` as `CodableCGRect?`.
///
/// **Why persist OCR lines?** `ReceiptLayoutTemplate` stores the OCR lines from the
/// labeling session so that `ReceiptTemplateLabelerView` can re-open a template in edit
/// mode without re-running OCR on the reference image. The stored lines are used to
/// reconstruct the bounding-box overlays and pre-populate the existing label assignments.
struct CodableOCRLine: Codable {
    var text: String
    var confidence: Double
    var boundingBox: CodableCGRect?

    init(_ line: OCRLine) {
        self.text = line.text
        self.confidence = line.confidence
        self.boundingBox = line.boundingBox.map(CodableCGRect.init)
    }

    var ocrLine: OCRLine {
        OCRLine(text: text, confidence: confidence, boundingBox: boundingBox?.cgRect)
    }
}
