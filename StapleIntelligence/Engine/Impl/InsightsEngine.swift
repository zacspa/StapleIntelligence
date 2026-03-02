//
//  InsightsEngine.swift
//  StapleIntelligence
//
//  Created by Zack Sparks on 3/2/26.
//

import Foundation
import SwiftData

struct InsightsEngine: InsightsEngineProtocol {
    let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func weeklySpend(range: DateInterval) throws -> [DateBucketTotal] { [] }
    func monthlySpend(range: DateInterval) throws -> [DateBucketTotal] { [] }
    func topItemsBySpend(range: DateInterval) throws -> [ItemSpend] { [] }
    func itemPriceHistory(itemId: UUID, range: DateInterval) throws -> [PricePoint] { [] }
    func priceMovers(range: DateInterval) throws -> [PriceMover] { [] }
    func merchantBreakdown(range: DateInterval) throws -> [MerchantShare] { [] }
}
