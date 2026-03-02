//
//  Merchant.swift
//  StapleIntelligence
//
//  Created by Zack Sparks on 3/2/26.
//

import Foundation
import SwiftData

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
