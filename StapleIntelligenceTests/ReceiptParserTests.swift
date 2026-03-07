//
//  ReceiptParserTests.swift
//  StapleIntelligenceTests
//
//  Created by Zack Sparks on 3/2/26.
//

import Testing
import Foundation
@testable import StapleIntelligence

struct ReceiptParserTests {
    let parser = ReceiptParser()

    // MARK: - Canonicalize

    @Test func canonicalizeStripsLeadingSKU() {
        #expect(ReceiptParser.canonicalize("569229 Garlic Breadsticks") == "GARLIC BREADSTICKS")
    }

    @Test func canonicalizeRemovesNoiseToken() {
        #expect(ReceiptParser.canonicalize("Whole Milk FB") == "WHOLE MILK")
    }

    @Test func canonicalizeRemovesWeightFragment() {
        // Weight fragment pattern strips everything after the unit
        #expect(ReceiptParser.canonicalize("356508 Broccoli Crowns 1.51 lb x 1.95/lb") == "BROCCOLI CROWNS")
    }

    @Test func canonicalizeCollapsesWhitespace() {
        #expect(ReceiptParser.canonicalize("  organic   milk  ") == "ORGANIC MILK")
    }

    @Test func canonicalizeAlreadyClean() {
        #expect(ReceiptParser.canonicalize("Apple") == "APPLE")
    }

    @Test func canonicalizeMultipleNoiseTokens() {
        // ND (non-taxable) stripped
        #expect(ReceiptParser.canonicalize("343709 Premium Napkin ND") == "PREMIUM NAPKIN")
    }

    // MARK: - Empty / degenerate input

    @Test func emptyInputReturnsZeroConfidence() {
        let r = parser.parse("")
        #expect(r.parseConfidence == 0)
        #expect(r.reconciliationStatus == .unverified)
        #expect(r.lineItems.isEmpty)
    }

    @Test func whitespaceOnlyReturnsZeroConfidence() {
        let r = parser.parse("   \n\n   ")
        #expect(r.parseConfidence == 0)
    }

    // MARK: - Mixed-column (ALDI batched format)

    @Test func aldiMixedColumnExtractsMerchantAndDate() throws {
        let r = parser.parse(aldiMixedColumn)
        #expect(r.merchantName == "ALDI")
        let comps = Calendar(identifier: .gregorian)
            .dateComponents([.year, .month, .day], from: try #require(r.purchaseDate))
        #expect(comps.year == 2025)
        #expect(comps.month == 11)
        #expect(comps.day == 30)
    }

    @Test func aldiMixedColumnExtractsFiveItems() {
        let r = parser.parse(aldiMixedColumn)
        #expect(r.lineItems.count == 5)
    }

    @Test func aldiMixedColumnReconciles() {
        let r = parser.parse(aldiMixedColumn)
        #expect(r.subtotal == Decimal(string: "11.56"))
        #expect(r.reconciliationStatus == .reconciled)
    }

    @Test func aldiMixedColumnConfidenceAboveThreshold() {
        let r = parser.parse(aldiMixedColumn)
        #expect(r.parseConfidence > 0.8)
    }

    @Test func aldiMixedColumnWeightItemAttachedCorrectly() throws {
        let r = parser.parse(aldiMixedColumn)
        let broccoli = try #require(r.lineItems.first { $0.canonicalName == "BROCCOLI CROWNS" })
        guard case .byWeight(let qty, let unit) = broccoli.itemType else {
            Issue.record("Expected broccoli to be a byWeight item"); return
        }
        #expect(abs(qty - 1.51) < 0.001)
        #expect(unit == .lb)
        #expect(broccoli.unitPrice == Decimal(string: "1.95"))
        #expect(broccoli.lineTotal == Decimal(string: "2.94"))
    }

    @Test func aldiMixedColumnCanonicalNamesAreClean() {
        let r = parser.parse(aldiMixedColumn)
        let names = r.lineItems.map(\.canonicalName)
        #expect(names.contains("GARLIC BREADSTICKS"))
        #expect(names.contains("MAYONNAISE"))
        #expect(names.contains("SPAGHETTI"))
        #expect(names.contains("SHARP CHEDDAR"))
        // None should contain raw SKU digits
        #expect(names.allSatisfy { !$0.hasPrefix("3") && !$0.hasPrefix("5") })
    }

    // MARK: - Split-column

    @Test func splitColumnExtractsTenItems() {
        let r = parser.parse(splitColumn)
        #expect(r.lineItems.count == 10)
    }

    @Test func splitColumnReconciles() {
        let r = parser.parse(splitColumn)
        let sum = r.lineItems.reduce(Decimal.zero) { $0 + $1.lineTotal }
        #expect(sum == Decimal(string: "55.00"))
        #expect(r.subtotal == Decimal(string: "55.00"))
        #expect(r.reconciliationStatus == .reconciled)
    }

    // MARK: - Single-column

    @Test func singleColumnExtractsItems() {
        let r = parser.parse(singleColumn)
        #expect(r.merchantName == "GROCERY STORE")
        #expect(r.lineItems.count == 3)
    }

    @Test func singleColumnSubtotalFoundAndReconciles() {
        let r = parser.parse(singleColumn)
        #expect(r.subtotal == Decimal(string: "8.77"))
        #expect(r.reconciliationStatus == .reconciled)
    }

    // MARK: - Reconciliation

    @Test func reconciledWhenSumMatchesSubtotal() {
        #expect(parser.parse(reconciledReceipt).reconciliationStatus == .reconciled)
    }

    @Test func discrepancyWhenSumMismatches() {
        #expect(parser.parse(discrepancyReceipt).reconciliationStatus == .discrepancy)
    }

    @Test func unverifiedWhenNoSubtotal() {
        #expect(parser.parse(noSubtotalReceipt).reconciliationStatus == .unverified)
    }

    // MARK: - SKU extraction

    @Test func extractSKUFromALDILine() {
        #expect(ReceiptParser.extractSKU(from: "569229 Garlic Breadsticks") == "569229")
    }

    @Test func extractSKUReturnsNilForNoSKU() {
        #expect(ReceiptParser.extractSKU(from: "Organic Apples") == nil)
    }

    @Test func extractSKUReturnsNilForTooFewDigits() {
        #expect(ReceiptParser.extractSKU(from: "12 Short") == nil)
    }

    @Test func aldiMixedColumnItemsHaveSKUs() {
        let r = parser.parse(aldiMixedColumn)
        #expect(r.lineItems.allSatisfy { $0.sku != nil })
        #expect(r.lineItems.first?.sku == "569229")
    }

    @Test func singleColumnItemsWithoutSKUHaveNilSKU() {
        let r = parser.parse(singleColumn)
        // "Organic Apples 2.99" has no SKU prefix
        #expect(r.lineItems.allSatisfy { $0.sku == nil })
    }

    // MARK: - Date

    @Test func twoDigitYearBelow50ResolvedTo2000s() throws {
        let r = parser.parse(twoDigitYearReceipt)
        let comps = Calendar(identifier: .gregorian)
            .dateComponents([.year], from: try #require(r.purchaseDate))
        #expect(comps.year == 2025)
    }

    // MARK: - (N) net weight annotation format

    @Test func nWeightLineAttachedToPrecedingItem() throws {
        let receipt = parser.parse(aldiNWeightColumn)
        let bananas = try #require(receipt.lineItems.first { $0.canonicalName == "BANANAS" })
        guard case .byWeight(let qty, let unit) = bananas.itemType else {
            Issue.record("Expected BANANAS to be .byWeight"); return
        }
        #expect(abs(qty - 1.52) < 0.001)
        #expect(unit == .lb)
        #expect(bananas.unitPrice == Decimal(string: "0.49"))
        #expect(bananas.lineTotal == Decimal(string: "0.74"))
    }

    // MARK: - Inline weight (same-line format)

    @Test func inlineWeightOnSameLineExtracted() throws {
        let receipt = parser.parse("""
        STORE
        CASHIER 1
        BANANAS 1.23 lb x 0.59/lb  0.73 F
        MILK  2.99 FB
        SUBTOTAL 3.72
        TOTAL 3.72
        """)
        let bananas = try #require(receipt.lineItems.first { $0.canonicalName == "BANANAS" })
        guard case .byWeight(let qty, let unit) = bananas.itemType else {
            Issue.record("Expected BANANAS to be .byWeight"); return
        }
        #expect(abs(qty - 1.23) < 0.001)
        #expect(unit == .lb)
        #expect(bananas.unitPrice == Decimal(string: "0.59"))
        #expect(bananas.lineTotal == Decimal(string: "0.73"))

        let milk = try #require(receipt.lineItems.first { $0.canonicalName == "MILK" })
        if case .byCount(let count) = milk.itemType { #expect(count == 1) }
    }

    @Test func dateNearVisaLinePreferredOverHeaderDate() throws {
        // Receipt has "01/01/25" in a header line and "11/30/25" near VISA.
        // Parser picks the one closest to the VISA line.
        let r = parser.parse(twoDateReceipt)
        let comps = Calendar(identifier: .gregorian)
            .dateComponents([.month, .day], from: try #require(r.purchaseDate))
        #expect(comps.month == 11)
        #expect(comps.day == 30)
    }
}

// MARK: - Fixtures

private extension ReceiptParserTests {

    /// ALDI batched mixed-column: names in groups, prices after each group, weight sub-line.
    var aldiMixedColumn: String {
        """
        ALDI
        Store #20
        6336 Main Street
        Atlanta, GA
        Your cashier today was Bob
        569229 Garlic Breadsticks
        382062 Mayonnaise
        356508 Broccoli Crowns
        1.95 FB
        2.99 FB
        2.94 FB
        1.51 lb x 1.95/lb
        399573 Spaghetti
        382489 Sharp Cheddar
        1.89 FB
        1.79 FB
        VISA
        **x1234 ONLINE
        11/30/25 16:01 Ref # 0
        Auth # 03562D
        ++ APPROVED++
        SUBTOTAL 11.56
        TOTAL $11.56
        """
    }

    /// Split-column: ten names before VISA, ten prices after APPROVED, distinct blocks.
    var splitColumn: String {
        """
        SPLIT STORE
        123 Main Street
        Your cashier was Charlie
        Item One
        Item Two
        Item Three
        Item Four
        Item Five
        Item Six
        Item Seven
        Item Eight
        Item Nine
        Item Ten
        VISA
        **x9999
        01/15/25 10:00
        Auth # XYZ
        ++ APPROVED++
        1.00 FB
        2.00 FB
        3.00 FB
        4.00 FB
        5.00 FB
        6.00 FB
        7.00 FB
        8.00 FB
        9.00 FB
        10.00 FB
        SUBTOTAL 55.00
        TOTAL $55.00
        """
    }

    /// Single-column: each line has name + price, SUBTOTAL inline.
    var singleColumn: String {
        """
        GROCERY STORE
        123 Main Street
        Anytown GA
        Organic Apples 2.99
        Whole Milk 3.49
        Bread Loaf 2.29
        SUBTOTAL 8.77
        TOTAL 8.77
        """
    }

    var reconciledReceipt: String {
        """
        FRESH MART
        Apple Juice 3.00
        Orange Juice 4.00
        SUBTOTAL 7.00
        TOTAL 7.00
        """
    }

    /// Subtotal is intentionally wrong (9.00 vs actual sum 7.00).
    var discrepancyReceipt: String {
        """
        FRESH MART
        Apple Juice 3.00
        Orange Juice 4.00
        SUBTOTAL 9.00
        TOTAL 9.00
        """
    }

    /// No SUBTOTAL line — reconciliation must be .unverified.
    var noSubtotalReceipt: String {
        """
        FRESH MART
        Apple Juice 3.00
        Orange Juice 4.00
        """
    }

    /// "01/15/25" → year 25 < 50 → 2025.
    var twoDigitYearReceipt: String {
        """
        QUICK MART
        Snack Bar 1.99
        SUBTOTAL 1.99
        TOTAL 1.99
        01/15/25 10:00
        """
    }

    /// ALDI split-column with (G)/(T)/(N) weight annotation lines.
    /// (G) = gross, (T) = tare, (N) = net — only (N) has useful weight+unitPrice.
    var aldiNWeightColumn: String {
        """
        ALDI
        Store #20
        Your cashier today was Bob
        262747 Bananas LRW
        (G) 1.531b - (T) 0.011b
        (N) 1.52 1b x 0.49/1b
        VISA
        **x1234
        01/15/25 10:00
        ++ APPROVED++
        0.74 FB
        SUBTOTAL 0.74
        TOTAL $0.74
        """
    }

    /// Two dates: "01/01/25" in header text, "11/30/25" near VISA line.
    var twoDateReceipt: String {
        """
        ALDI
        Store #20
        Annual Report 01/01/25
        Your cashier today was Dave
        Sparkling Water 1.99
        1.99 FB
        VISA
        **x9999
        11/30/25 16:01 Ref # 0
        Auth # ABCDEF
        ++ APPROVED++
        SUBTOTAL 1.99
        TOTAL $1.99
        """
    }
}
