//
//  Merchant.swift
//  StapleIntelligence
//
//  Created by Zack Sparks on 3/2/26.
//

import Foundation
import SwiftData

/// A grocery store or retailer, shared across all receipts from that store.
///
/// `normalizedName` is the uppercase+trimmed key used for deduplication lookups
/// (`FetchDescriptor` predicate). When saving a receipt, the app first fetches by
/// `normalizedName`; it creates a new `Merchant` only on a miss.
///
/// The inverse relationship to `Receipt.merchant` uses `.nullify` so deleting a
/// merchant does not cascade-delete its receipts.
@Model
final class Merchant {
    var id: UUID
    var displayName: String
    var normalizedName: String
    var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \Receipt.merchant)
    var receipts: [Receipt] = []

    init(
        id: UUID = UUID(),
        displayName: String,
        normalizedName: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.normalizedName = normalizedName
        self.createdAt = createdAt
    }
}
