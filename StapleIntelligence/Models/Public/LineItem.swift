//
//  LineItem.swift
//  StapleIntelligence
//
//  Created by Zack Sparks on 3/2/26.
//

import Foundation
import SwiftData

enum WeightUnit: String, Codable { case lb, oz, kg }

enum ItemType {
    case byCount(count: Int)
    case byWeight(quantity: Double, unit: WeightUnit)
}

@Model
final class LineItem {
    var id: UUID
    var rawName: String
    var canonicalName: String

    // ItemType backing storage (SwiftData cannot store enums with associated values)
    private var itemTypeModeRaw: String
    private var itemTypeCount: Int?
    private var itemTypeWeightQuantity: Double?
    private var itemTypeWeightUnit: String?

    var itemType: ItemType {
        get {
            if itemTypeModeRaw == "byWeight",
               let qty = itemTypeWeightQuantity,
               let unitStr = itemTypeWeightUnit,
               let wu = WeightUnit(rawValue: unitStr) {
                return .byWeight(quantity: qty, unit: wu)
            }
            return .byCount(count: itemTypeCount ?? 1)
        }
        set {
            switch newValue {
            case .byCount(let count):
                itemTypeModeRaw = "byCount"
                itemTypeCount = count
                itemTypeWeightQuantity = nil
                itemTypeWeightUnit = nil
            case .byWeight(let qty, let unit):
                itemTypeModeRaw = "byWeight"
                itemTypeCount = nil
                itemTypeWeightQuantity = qty
                itemTypeWeightUnit = unit.rawValue
            }
        }
    }

    var isWeightItem: Bool {
        if case .byWeight = itemType { return true }
        return false
    }

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
    var sku: String?
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        rawName: String,
        canonicalName: String,
        itemType: ItemType = .byCount(count: 1),
        unitPrice: Decimal? = nil,
        lineTotal: Decimal,
        isDiscount: Bool = false,
        confidence: Double = 0,
        sku: String? = nil,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.rawName = rawName
        self.canonicalName = canonicalName
        switch itemType {
        case .byCount(let count):
            self.itemTypeModeRaw = "byCount"
            self.itemTypeCount = count
            self.itemTypeWeightQuantity = nil
            self.itemTypeWeightUnit = nil
        case .byWeight(let qty, let unit):
            self.itemTypeModeRaw = "byWeight"
            self.itemTypeCount = nil
            self.itemTypeWeightQuantity = qty
            self.itemTypeWeightUnit = unit.rawValue
        }
        self.unitPriceStorage = unitPrice.map { "\($0)" }
        self.lineTotalStorage = "\(lineTotal)"
        self.isDiscount = isDiscount
        self.confidence = confidence
        self.sku = sku
        self.sortOrder = sortOrder
    }
}
