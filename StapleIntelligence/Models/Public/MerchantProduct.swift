//
//  MerchantProduct.swift
//  StapleIntelligence
//
//  Created by Zack Sparks on 3/2/26.
//

import Foundation
import SwiftData

/// SKU-keyed product catalog entry for a merchant.
///
/// Built up over time as receipts are scanned: when the parser encounters a SKU that
/// matches an existing `MerchantProduct`, it uses the stored `canonicalName` rather
/// than the raw OCR text, improving name consistency across receipts.
///
/// `normalizedMerchantName` mirrors `Merchant.normalizedName` and is intentionally
/// a plain string (not a SwiftData relationship) to allow lookup without a live
/// `Merchant` object.
@Model
final class MerchantProduct {
    var id: UUID
    var normalizedMerchantName: String  // uppercase+trimmed, matches Merchant.normalizedName
    var sku: String
    var canonicalName: String           // best-known clean name; survives OCR noise
    var firstSeenAt: Date
    var lastSeenAt: Date

    init(normalizedMerchantName: String, sku: String, canonicalName: String) {
        self.id = UUID()
        self.normalizedMerchantName = normalizedMerchantName
        self.sku = sku
        self.canonicalName = canonicalName
        let now = Date()
        self.firstSeenAt = now
        self.lastSeenAt = now
    }
}
