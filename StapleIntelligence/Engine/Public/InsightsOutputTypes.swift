//
//  InsightsOutputTypes.swift
//  StapleIntelligence
//
//  Created by Zack Sparks on 3/2/26.
//

import Foundation

struct DateBucketTotal: Identifiable {
    var id: Date { date }
    let date: Date
    let total: Decimal
}

struct ItemSpend: Identifiable {
    let id: UUID
    let canonicalName: String
    let total: Decimal
    let purchaseCount: Int
}

struct PricePoint: Identifiable {
    var id: Date { date }
    let date: Date
    let unitPrice: Decimal
}

struct PriceMover: Identifiable {
    let id: UUID
    let canonicalName: String
    let previousAvg: Decimal
    let currentAvg: Decimal

    var delta: Decimal { currentAvg - previousAvg }
}

struct MerchantShare: Identifiable {
    let id: UUID
    let displayName: String
    let total: Decimal
    let fraction: Double
}
