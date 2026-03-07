//
//  ReceiptLayoutTemplate.swift
//  StapleIntelligence
//

import Foundation
import SwiftData

/// A persisted receipt layout template.
///
/// Templates are **always merchant-bound** — `merchantNormalizedName` is required and
/// cannot be blank. Templates are matched to incoming receipts by comparing normalized
/// merchant names; the highest `useCount` template wins when multiple exist for the same
/// merchant.
///
/// `fields` and `ocrLines` are JSON-encoded because SwiftData cannot directly store
/// arrays of custom `Codable` structs.
@Model
final class ReceiptLayoutTemplate {
    var id: UUID
    var templateName: String
    /// Uppercase, trimmed merchant key used for template lookup.
    var merchantNormalizedName: String
    /// JSON-encoded `[TemplateField]`.
    var fieldsJSON: String
    /// JSON-encoded `[CodableOCRLine]` from the original labeling session.
    /// Stored so the labeler can re-open the template in edit mode without re-running OCR.
    var ocrLinesJSON: String
    /// Absolute file-system path to the receipt image used during labeling.
    var referenceImageURL: String?
    var createdAt: Date
    var lastUsedAt: Date?
    var useCount: Int

    // MARK: - Computed wrappers

    var fields: [TemplateField] {
        get {
            guard let data = fieldsJSON.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([TemplateField].self, from: data)
            else { return [] }
            return decoded
        }
        set {
            let data = (try? JSONEncoder().encode(newValue)) ?? Data()
            fieldsJSON = String(data: data, encoding: .utf8) ?? "[]"
        }
    }

    var ocrLines: [OCRLine] {
        get {
            guard let data = ocrLinesJSON.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([CodableOCRLine].self, from: data)
            else { return [] }
            return decoded.map(\.ocrLine)
        }
        set {
            let codable = newValue.map(CodableOCRLine.init)
            let data = (try? JSONEncoder().encode(codable)) ?? Data()
            ocrLinesJSON = String(data: data, encoding: .utf8) ?? "[]"
        }
    }

    init(
        id: UUID = UUID(),
        templateName: String,
        merchantNormalizedName: String,
        fields: [TemplateField] = [],
        ocrLines: [OCRLine] = [],
        referenceImageURL: String? = nil,
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil,
        useCount: Int = 0
    ) {
        self.id = id
        self.templateName = templateName
        self.merchantNormalizedName = merchantNormalizedName
        self.referenceImageURL = referenceImageURL
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.useCount = useCount
        // Initialize JSON fields before using the computed setters
        self.fieldsJSON = "[]"
        self.ocrLinesJSON = "[]"
        self.fields = fields
        self.ocrLines = ocrLines
    }
}
