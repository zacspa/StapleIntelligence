//
//  Receipt.swift
//  StapleIntelligence
//
//  Created by Zack Sparks on 3/2/26.
//

import Foundation
import SwiftData

/// Persisted record of a single scanned receipt.
///
/// **Decimal-as-String storage**: SwiftData cannot store `Decimal` natively, so `subtotal`,
/// `tax`, and `total` are backed by private `String?` properties (`*Storage`). The public
/// computed properties convert on access using `en_US_POSIX` locale to guarantee `.`
/// as the decimal separator regardless of device locale.
///
/// **URL storage**: `imageURLs` is similarly backed by `[String]` because SwiftData
/// cannot persist `URL` arrays.
///
/// `lineItems` are cascade-deleted when the receipt is deleted.
@Model
final class Receipt {
    var id: UUID
    var merchant: Merchant?
    var purchaseDate: Date?
    var currency: String

    private var subtotalStorage: String?
    var subtotal: Decimal? {
        get { subtotalStorage.flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) } }
        set { subtotalStorage = newValue.map { "\($0)" } }
    }

    private var taxStorage: String?
    var tax: Decimal? {
        get { taxStorage.flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) } }
        set { taxStorage = newValue.map { "\($0)" } }
    }

    private var totalStorage: String?
    var total: Decimal? {
        get { totalStorage.flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) } }
        set { totalStorage = newValue.map { "\($0)" } }
    }

    var rawOcrText: String
    var parseConfidence: Double
    var reconciliationStatus: ReconciliationStatus

    private var imageURLStrings: [String]
    var imageURLs: [URL] {
        get { imageURLStrings.compactMap { URL(string: $0) } }
        set { imageURLStrings = newValue.map { $0.absoluteString } }
    }

    var createdAt: Date

    @Relationship(deleteRule: .cascade)
    var lineItems: [LineItem] = []

    init(
        id: UUID = UUID(),
        merchant: Merchant? = nil,
        purchaseDate: Date? = nil,
        currency: String = "USD",
        lineItems: [LineItem] = [],
        subtotal: Decimal? = nil,
        tax: Decimal? = nil,
        total: Decimal? = nil,
        rawOcrText: String = "",
        parseConfidence: Double = 0,
        reconciliationStatus: ReconciliationStatus = .unverified,
        imageURLs: [URL] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.merchant = merchant
        self.purchaseDate = purchaseDate
        self.currency = currency
        self.lineItems = lineItems
        self.subtotalStorage = subtotal.map { "\($0)" }
        self.taxStorage = tax.map { "\($0)" }
        self.totalStorage = total.map { "\($0)" }
        self.rawOcrText = rawOcrText
        self.parseConfidence = parseConfidence
        self.reconciliationStatus = reconciliationStatus
        self.imageURLStrings = imageURLs.map { $0.absoluteString }
        self.createdAt = createdAt
    }
}
