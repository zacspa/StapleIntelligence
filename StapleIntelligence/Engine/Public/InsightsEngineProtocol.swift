//
//  InsightsEngineProtocol.swift
//  StapleIntelligence
//
//  Created by Zack Sparks on 3/2/26.
//

import Foundation

/// Pure on-device analytics contract.
///
/// All methods are synchronous and deterministic — they fetch from the local SwiftData
/// store and return value-type result models. No networking, no side effects.
/// `FakeInsightsEngine` implements this protocol for Previews and tests.
protocol InsightsEngineProtocol {
    /// Total spend bucketed by calendar week, sorted chronologically.
    func weeklySpend(range: DateInterval) throws -> [DateBucketTotal]

    /// Total spend bucketed by calendar month, sorted chronologically.
    func monthlySpend(range: DateInterval) throws -> [DateBucketTotal]

    /// Top items ranked by total spend, discounts excluded.
    func topItemsBySpend(range: DateInterval) throws -> [ItemSpend]

    /// Unit-price history for one item (identified by the first `LineItem.id` with
    /// the matching `canonicalName`), sorted chronologically.
    func itemPriceHistory(itemId: UUID, range: DateInterval) throws -> [PricePoint]

    /// Items whose rolling 4-week average unit price changed by more than $0.10
    /// **and** more than 5% relative to the prior 4-week window.
    /// Sorted by absolute delta descending (largest movers first).
    func priceMovers(range: DateInterval) throws -> [PriceMover]

    /// Per-merchant share of total spend, sorted by spend descending.
    /// Receipts with no merchant are grouped under a synthetic "Unknown" entry.
    func merchantBreakdown(range: DateInterval) throws -> [MerchantShare]
}
