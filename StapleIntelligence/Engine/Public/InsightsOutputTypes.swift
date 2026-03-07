//
//  InsightsOutputTypes.swift
//  StapleIntelligence
//
//  Created by Zack Sparks on 3/2/26.
//

import Foundation

/// A single spend total for one calendar bucket (week or month).
struct DateBucketTotal: Identifiable {
    var id: Date { date }
    /// The start of the calendar period (week start or month start).
    let date: Date
    let total: Decimal
}

/// Aggregated spend for one canonical product name across the query range.
struct ItemSpend: Identifiable {
    /// The `id` of the first `LineItem` with this `canonicalName` (used to look up price history).
    let id: UUID
    let canonicalName: String
    let total: Decimal
    let purchaseCount: Int
}

/// Unit price of an item at a specific purchase date.
struct PricePoint: Identifiable {
    var id: Date { date }
    let date: Date
    /// For weight items: `unitPrice` (per lb/oz/kg). For count items: `unitPrice ?? lineTotal`.
    let unitPrice: Decimal
}

/// An item whose rolling average price moved significantly between the current
/// and previous 4-week windows (thresholds: >$0.10 absolute AND >5% relative).
struct PriceMover: Identifiable {
    /// The `id` of the first `LineItem` with this `canonicalName`.
    let id: UUID
    let canonicalName: String
    let previousAvg: Decimal
    let currentAvg: Decimal

    /// Signed delta: positive = price went up, negative = price went down.
    var delta: Decimal { currentAvg - previousAvg }
}

/// A merchant's share of total spend in the query range.
struct MerchantShare: Identifiable {
    let id: UUID
    let displayName: String
    let total: Decimal
    /// Fraction of grand total, in [0, 1]. Used to draw the proportional bar in the UI.
    let fraction: Double
}
