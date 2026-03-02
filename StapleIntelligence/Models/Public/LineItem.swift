//
//  LineItem.swift
//  StapleIntelligence
//
//  Created by Zack Sparks on 3/2/26.
//

import Foundation
import SwiftData

@Model
final class LineItem {
    var id: UUID
    var receipt: Receipt?
    var rawName: String
    var canonicalName: String
    var quantity: Double?
    var unit: String?

    private var unitPriceStorage: String?
    var unitPrice: Decimal? {
        get { unitPriceStorage.flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) } }
        set { unitPriceStorage = newValue.map { "\($0)" } }
    }

    private var lineTotalStorage: String
    var lineTotal: Decimal {
        get { Decimal(string: lineTotalStorage, locale: Locale(identifier: "en_US_POSIX")) ?? .zero }
        set { lineTotalStorage = "\(newValue)" }
    }

    var isDiscount: Bool
    var confidence: Double

    init(
        id: UUID = UUID(),
        receipt: Receipt? = nil,
        rawName: String,
        canonicalName: String,
        quantity: Double? = nil,
        unit: String? = nil,
        unitPrice: Decimal? = nil,
        lineTotal: Decimal,
        isDiscount: Bool = false,
        confidence: Double = 0
    ) {
        self.id = id
        self.receipt = receipt
        self.rawName = rawName
        self.canonicalName = canonicalName
        self.quantity = quantity
        self.unit = unit
        self.unitPriceStorage = unitPrice.map { "\($0)" }
        self.lineTotalStorage = "\(lineTotal)"
        self.isDiscount = isDiscount
        self.confidence = confidence
    }
}
