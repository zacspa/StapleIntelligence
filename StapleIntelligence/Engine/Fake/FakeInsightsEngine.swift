//
//  FakeInsightsEngine.swift
//  StapleIntelligence
//
//  Created by Zack Sparks on 3/2/26.
//

import Foundation

struct FakeInsightsEngine: InsightsEngineProtocol {
    var weeklySpendData: [DateBucketTotal] = []
    var monthlySpendData: [DateBucketTotal] = []
    var topItemsData: [ItemSpend] = []
    var priceHistoryData: [PricePoint] = []
    var priceMoversData: [PriceMover] = []
    var merchantBreakdownData: [MerchantShare] = []

    func weeklySpend(range: DateInterval) throws -> [DateBucketTotal] { weeklySpendData }
    func monthlySpend(range: DateInterval) throws -> [DateBucketTotal] { monthlySpendData }
    func topItemsBySpend(range: DateInterval) throws -> [ItemSpend] { topItemsData }
    func itemPriceHistory(itemId: UUID, range: DateInterval) throws -> [PricePoint] { priceHistoryData }
    func priceMovers(range: DateInterval) throws -> [PriceMover] { priceMoversData }
    func merchantBreakdown(range: DateInterval) throws -> [MerchantShare] { merchantBreakdownData }
}
