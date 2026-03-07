//
//  ReceiptTemplateTests.swift
//  StapleIntelligenceTests
//

import Testing
import Foundation
import CoreGraphics
import SwiftData
@testable import StapleIntelligence

// MARK: - CodableCGRect

struct CodableCGRectTests {

    @Test func roundtripsViaJSON() throws {
        let original = CodableCGRect(CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.3))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CodableCGRect.self, from: data)
        #expect(decoded == original)
    }

    @Test func cgRectPropertyMatchesInput() {
        let rect = CGRect(x: 0.15, y: 0.25, width: 0.6, height: 0.4)
        let codable = CodableCGRect(rect)
        #expect(abs(codable.cgRect.minX - 0.15) < 1e-9)
        #expect(abs(codable.cgRect.minY - 0.25) < 1e-9)
        #expect(abs(codable.cgRect.width  - 0.6)  < 1e-9)
        #expect(abs(codable.cgRect.height - 0.4)  < 1e-9)
    }

    @Test func equalityOnSameValues() {
        let a = CodableCGRect(CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4))
        let b = CodableCGRect(CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4))
        #expect(a == b)
    }

    @Test func inequalityOnDifferentValues() {
        let a = CodableCGRect(CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4))
        let b = CodableCGRect(CGRect(x: 0.5, y: 0.2, width: 0.3, height: 0.4))
        #expect(a != b)
    }
}

// MARK: - TemplateField

struct TemplateFieldTests {

    @Test func roundtripsViaJSON() throws {
        let field = TemplateField(
            id: UUID(),
            label: .lineItemName,
            region: CGRect(x: 0.05, y: 0.55, width: 0.65, height: 0.25),
            anchorText: "Apple Juice"
        )
        let data = try JSONEncoder().encode(field)
        let decoded = try JSONDecoder().decode(TemplateField.self, from: data)
        #expect(decoded.id == field.id)
        #expect(decoded.label == field.label)
        #expect(decoded.region == field.region)
        #expect(decoded.anchorText == field.anchorText)
    }

    @Test func nilAnchorTextRoundtrips() throws {
        let field = TemplateField(label: .total, region: CGRect(x: 0.5, y: 0.1, width: 0.5, height: 0.1))
        let data = try JSONEncoder().encode(field)
        let decoded = try JSONDecoder().decode(TemplateField.self, from: data)
        #expect(decoded.anchorText == nil)
    }

    @Test func allLabelsRoundtrip() throws {
        for label in ReceiptFieldLabel.allCases {
            let field = TemplateField(label: label, region: CGRect(x: 0, y: 0, width: 1, height: 1))
            let data = try JSONEncoder().encode(field)
            let decoded = try JSONDecoder().decode(TemplateField.self, from: data)
            #expect(decoded.label == label)
        }
    }
}

// MARK: - CodableOCRLine

struct CodableOCRLineTests {

    @Test func roundtripsWithBoundingBox() throws {
        let bbox = CGRect(x: 0.1, y: 0.8, width: 0.6, height: 0.05)
        let line = OCRLine(text: "GROCERY STORE", confidence: 0.97, boundingBox: bbox)
        let codable = CodableOCRLine(line)

        let data = try JSONEncoder().encode(codable)
        let decoded = try JSONDecoder().decode(CodableOCRLine.self, from: data)

        #expect(decoded.text == "GROCERY STORE")
        #expect(abs(decoded.confidence - 0.97) < 1e-9)
        let decodedBox = try #require(decoded.boundingBox)
        #expect(abs(decodedBox.x - 0.1) < 1e-9)
        #expect(abs(decodedBox.y - 0.8) < 1e-9)
    }

    @Test func roundtripsWithNilBoundingBox() throws {
        let line = OCRLine(text: "Multi-page line", confidence: 0.9, boundingBox: nil)
        let codable = CodableOCRLine(line)
        let data = try JSONEncoder().encode(codable)
        let decoded = try JSONDecoder().decode(CodableOCRLine.self, from: data)
        #expect(decoded.boundingBox == nil)
    }

    @Test func ocrLinePropertyPreservesValues() {
        let bbox = CGRect(x: 0.2, y: 0.6, width: 0.5, height: 0.06)
        let line = OCRLine(text: "Whole Milk", confidence: 0.95, boundingBox: bbox)
        let recovered = CodableOCRLine(line).ocrLine
        #expect(recovered.text == "Whole Milk")
        #expect(abs(recovered.confidence - 0.95) < 1e-9)
        let box = try? #require(recovered.boundingBox)
        #expect(box != nil)
    }
}

// MARK: - ReceiptFieldLabel metadata

struct ReceiptFieldLabelTests {

    @Test func allCasesHaveDisplayNames() {
        for label in ReceiptFieldLabel.allCases {
            #expect(!label.displayName.isEmpty)
        }
    }

    @Test func allCasesHaveSystemImages() {
        for label in ReceiptFieldLabel.allCases {
            #expect(!label.systemImage.isEmpty)
        }
    }

    @Test func displayNamesAreUnique() {
        let names = ReceiptFieldLabel.allCases.map(\.displayName)
        #expect(Set(names).count == names.count)
    }

    @Test func rawValuesMatchExpected() {
        #expect(ReceiptFieldLabel.merchantName.rawValue  == "merchantName")
        #expect(ReceiptFieldLabel.lineItemName.rawValue  == "lineItemName")
        #expect(ReceiptFieldLabel.lineItemPrice.rawValue == "lineItemPrice")
        #expect(ReceiptFieldLabel.ignore.rawValue        == "ignore")
    }
}

// MARK: - ReceiptLayoutTemplate computed properties

struct ReceiptLayoutTemplateTests {

    @Test func emptyInitHasEmptyFields() {
        let template = ReceiptLayoutTemplate(
            templateName: "Test",
            merchantNormalizedName: "ALDI"
        )
        #expect(template.fields.isEmpty)
        #expect(template.ocrLines.isEmpty)
    }

    @Test func fieldsSetterAndGetterRoundtrip() {
        let template = ReceiptLayoutTemplate(
            templateName: "Test",
            merchantNormalizedName: "ALDI"
        )
        let fields: [TemplateField] = [
            TemplateField(label: .merchantName,  region: CGRect(x: 0, y: 0.9, width: 1, height: 0.1)),
            TemplateField(label: .lineItemPrice, region: CGRect(x: 0.7, y: 0.4, width: 0.3, height: 0.4)),
        ]
        template.fields = fields

        let recovered = template.fields
        #expect(recovered.count == 2)
        #expect(recovered[0].label == .merchantName)
        #expect(recovered[1].label == .lineItemPrice)
    }

    @Test func ocrLinesSetterAndGetterRoundtrip() {
        let template = ReceiptLayoutTemplate(
            templateName: "Test",
            merchantNormalizedName: "WHOLE FOODS"
        )
        let lines = [
            OCRLine(text: "WHOLE FOODS",  confidence: 0.99, boundingBox: CGRect(x: 0.1, y: 0.9, width: 0.6, height: 0.05)),
            OCRLine(text: "Organic Milk", confidence: 0.95, boundingBox: nil),
        ]
        template.ocrLines = lines

        let recovered = template.ocrLines
        #expect(recovered.count == 2)
        #expect(recovered[0].text == "WHOLE FOODS")
        #expect(recovered[1].text == "Organic Milk")
        #expect(recovered[0].boundingBox != nil)
        #expect(recovered[1].boundingBox == nil)
    }

    @Test func fieldsPassedToInitRoundtrip() {
        let fields: [TemplateField] = [
            TemplateField(label: .total, region: CGRect(x: 0.5, y: 0.1, width: 0.5, height: 0.1), anchorText: "TOTAL"),
        ]
        let template = ReceiptLayoutTemplate(
            templateName: "My Template",
            merchantNormalizedName: "TRADER JOES",
            fields: fields
        )
        #expect(template.fields.count == 1)
        #expect(template.fields[0].label == .total)
        #expect(template.fields[0].anchorText == "TRADER JOES".contains("TRADER") ? "TOTAL" : nil)
    }

    @Test func useCountDefaultsToZero() {
        let template = ReceiptLayoutTemplate(templateName: "T", merchantNormalizedName: "M")
        #expect(template.useCount == 0)
    }
}

// MARK: - TemplateMatchingService

struct TemplateMatchingServiceTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([ReceiptLayoutTemplate.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    @Test func returnsNilWhenContextIsEmpty() throws {
        let context = try makeContext()
        let service = TemplateMatchingService()
        #expect(service.findTemplate(for: "ALDI", in: context) == nil)
    }

    @Test func returnsNilForDifferentMerchant() throws {
        let context = try makeContext()
        context.insert(ReceiptLayoutTemplate(templateName: "ALDI", merchantNormalizedName: "ALDI"))
        let service = TemplateMatchingService()
        #expect(service.findTemplate(for: "WHOLE FOODS", in: context) == nil)
    }

    @Test func findsExactMerchantMatch() throws {
        let context = try makeContext()
        let t = ReceiptLayoutTemplate(templateName: "ALDI Layout", merchantNormalizedName: "ALDI")
        context.insert(t)
        let service = TemplateMatchingService()
        let result = service.findTemplate(for: "ALDI", in: context)
        #expect(result?.templateName == "ALDI Layout")
    }

    @Test func matchIsCaseInsensitive() throws {
        let context = try makeContext()
        context.insert(ReceiptLayoutTemplate(templateName: "T", merchantNormalizedName: "ALDI"))
        let service = TemplateMatchingService()
        // Query with different casing should still match
        #expect(service.findTemplate(for: "aldi", in: context) != nil)
        #expect(service.findTemplate(for: "Aldi", in: context) != nil)
        #expect(service.findTemplate(for: "ALDI", in: context) != nil)
    }

    @Test func returnsHighestUseCountWhenMultipleMatch() throws {
        let context = try makeContext()
        let low  = ReceiptLayoutTemplate(templateName: "v1", merchantNormalizedName: "ALDI", useCount: 3)
        let high = ReceiptLayoutTemplate(templateName: "v2", merchantNormalizedName: "ALDI", useCount: 15)
        let mid  = ReceiptLayoutTemplate(templateName: "v3", merchantNormalizedName: "ALDI", useCount: 8)
        context.insert(low); context.insert(high); context.insert(mid)

        let service = TemplateMatchingService()
        let result = service.findTemplate(for: "ALDI", in: context)
        #expect(result?.templateName == "v2")
        #expect(result?.useCount == 15)
    }

    @Test func doesNotReturnPartialMerchantMatch() throws {
        let context = try makeContext()
        // "ALDI STORE" should NOT match a query for "ALDI"
        context.insert(ReceiptLayoutTemplate(templateName: "T", merchantNormalizedName: "ALDI STORE"))
        let service = TemplateMatchingService()
        #expect(service.findTemplate(for: "ALDI", in: context) == nil)
    }
}

// MARK: - TemplateParser

struct TemplateParserTests {
    let parser = TemplateParser()

    // MARK: Fixture

    /// A synthetic receipt with clearly separated regions:
    ///
    /// Vision coords (y=0 at bottom, y=1 at top):
    ///
    ///   y=0.90..0.95  GROCERY STORE  (merchant)
    ///   y=0.80..0.85  01/15/26       (date)
    ///   y=0.68..0.73  Apple Juice    (item name, left column)
    ///   y=0.68..0.73  3.99           (item price, right column)
    ///   y=0.60..0.65  Whole Milk     (item name, left column)
    ///   y=0.60..0.65  4.49           (item price, right column)
    ///   y=0.48..0.53  COUPON 0.50    (discount — full width)
    ///   y=0.36..0.41  7.98           (subtotal value)
    ///   y=0.26..0.31  7.48           (total value: 8.48 - 0.50 - tax handled externally)
    ///   y=0.12..0.17  Thank you!     (ignore region)
    private var lines: [OCRLine] {[
        OCRLine(text: "GROCERY STORE", confidence: 0.99,
                boundingBox: CGRect(x: 0.10, y: 0.90, width: 0.60, height: 0.05)),
        OCRLine(text: "01/15/26",      confidence: 0.99,
                boundingBox: CGRect(x: 0.10, y: 0.80, width: 0.30, height: 0.05)),
        OCRLine(text: "Apple Juice",   confidence: 0.95,
                boundingBox: CGRect(x: 0.05, y: 0.68, width: 0.55, height: 0.05)),
        OCRLine(text: "3.99",          confidence: 0.99,
                boundingBox: CGRect(x: 0.72, y: 0.68, width: 0.20, height: 0.05)),
        OCRLine(text: "Whole Milk",    confidence: 0.95,
                boundingBox: CGRect(x: 0.05, y: 0.60, width: 0.55, height: 0.05)),
        OCRLine(text: "4.49",          confidence: 0.99,
                boundingBox: CGRect(x: 0.72, y: 0.60, width: 0.20, height: 0.05)),
        OCRLine(text: "COUPON 0.50",   confidence: 0.95,
                boundingBox: CGRect(x: 0.05, y: 0.48, width: 0.80, height: 0.05)),
        // subtotal: 3.99 + 4.49 - 0.50 = 7.98
        OCRLine(text: "7.98",          confidence: 0.99,
                boundingBox: CGRect(x: 0.72, y: 0.36, width: 0.20, height: 0.05)),
        OCRLine(text: "7.98",          confidence: 0.99,
                boundingBox: CGRect(x: 0.72, y: 0.26, width: 0.20, height: 0.05)),
        OCRLine(text: "Thank you!",    confidence: 0.99,
                boundingBox: CGRect(x: 0.05, y: 0.12, width: 0.80, height: 0.05)),
    ]}

    private var template: ReceiptLayoutTemplate {
        ReceiptLayoutTemplate(
            templateName: "Grocery Store Standard",
            merchantNormalizedName: "GROCERY STORE",
            fields: [
                TemplateField(label: .merchantName,  region: CGRect(x: 0.00, y: 0.87, width: 1.00, height: 0.13)),
                TemplateField(label: .purchaseDate,  region: CGRect(x: 0.00, y: 0.77, width: 1.00, height: 0.10)),
                TemplateField(label: .lineItemName,  region: CGRect(x: 0.00, y: 0.56, width: 0.68, height: 0.17)),
                TemplateField(label: .lineItemPrice, region: CGRect(x: 0.68, y: 0.56, width: 0.32, height: 0.17)),
                TemplateField(label: .discount,      region: CGRect(x: 0.00, y: 0.44, width: 1.00, height: 0.10)),
                TemplateField(label: .subtotal,      region: CGRect(x: 0.68, y: 0.32, width: 0.32, height: 0.10)),
                TemplateField(label: .total,         region: CGRect(x: 0.68, y: 0.22, width: 0.32, height: 0.10)),
                TemplateField(label: .ignore,        region: CGRect(x: 0.00, y: 0.08, width: 1.00, height: 0.10)),
            ]
        )
    }

    // MARK: - Merchant

    @Test func merchantNameExtracted() {
        let result = parser.parse(ocrLines: lines, template: template)
        #expect(result.merchantName == "GROCERY STORE")
    }

    @Test func merchantNameNilWhenNoFieldMatches() {
        // Template with no merchantName field
        let emptyTemplate = ReceiptLayoutTemplate(
            templateName: "Empty",
            merchantNormalizedName: "X",
            fields: []
        )
        let result = parser.parse(ocrLines: lines, template: emptyTemplate)
        #expect(result.merchantName == nil)
    }

    // MARK: - Date

    @Test func purchaseDateExtracted() throws {
        let result = parser.parse(ocrLines: lines, template: template)
        let date = try #require(result.purchaseDate)
        let comps = Calendar(identifier: .gregorian)
            .dateComponents([.year, .month, .day], from: date)
        #expect(comps.year  == 2026)
        #expect(comps.month == 1)
        #expect(comps.day   == 15)
    }

    @Test func purchaseDateNilWhenNoneDateText() {
        let noDateLines = [OCRLine(text: "no date here", confidence: 0.9,
                                   boundingBox: CGRect(x: 0.1, y: 0.82, width: 0.4, height: 0.05))]
        let simpleTemplate = ReceiptLayoutTemplate(
            templateName: "T", merchantNormalizedName: "M",
            fields: [TemplateField(label: .purchaseDate,
                                   region: CGRect(x: 0, y: 0.78, width: 1, height: 0.10))]
        )
        let result = parser.parse(ocrLines: noDateLines, template: simpleTemplate)
        #expect(result.purchaseDate == nil)
    }

    @Test func twoDigitYearBelow50ResolvedTo2000s() throws {
        let twoDigitLines = [OCRLine(text: "03/22/25", confidence: 0.99,
                                     boundingBox: CGRect(x: 0.1, y: 0.82, width: 0.3, height: 0.05))]
        let simpleTemplate = ReceiptLayoutTemplate(
            templateName: "T", merchantNormalizedName: "M",
            fields: [TemplateField(label: .purchaseDate,
                                   region: CGRect(x: 0, y: 0.78, width: 1, height: 0.10))]
        )
        let result = parser.parse(ocrLines: twoDigitLines, template: simpleTemplate)
        let date = try #require(result.purchaseDate)
        let year = Calendar(identifier: .gregorian).component(.year, from: date)
        #expect(year == 2025)
    }

    // MARK: - Line items

    @Test func lineItemsExtracted() {
        let result = parser.parse(ocrLines: lines, template: template)
        let nonDiscount = result.lineItems.filter { !$0.isDiscount }
        #expect(nonDiscount.count == 2)
    }

    @Test func lineItemNamesCanonicalised() {
        let result = parser.parse(ocrLines: lines, template: template)
        let names = result.lineItems.filter { !$0.isDiscount }.map(\.canonicalName)
        #expect(names.contains("APPLE JUICE"))
        #expect(names.contains("WHOLE MILK"))
    }

    @Test func lineItemPricesCorrect() {
        let result = parser.parse(ocrLines: lines, template: template)
        let byName = Dictionary(
            uniqueKeysWithValues: result.lineItems
                .filter { !$0.isDiscount }
                .map { ($0.canonicalName, $0.lineTotal) }
        )
        #expect(byName["APPLE JUICE"] == Decimal(string: "3.99"))
        #expect(byName["WHOLE MILK"]  == Decimal(string: "4.49"))
    }

    @Test func lineItemsSpatiallyPairedByYMidpoint() {
        // Apple Juice (y=0.705) should pair with 3.99 (y=0.705), not 4.49 (y=0.625).
        // Whole Milk  (y=0.625) should pair with 4.49.
        let result = parser.parse(ocrLines: lines, template: template)
        let nonDiscount = result.lineItems.filter { !$0.isDiscount }
        let appleJuice = nonDiscount.first { $0.canonicalName == "APPLE JUICE" }
        let wholeMilk  = nonDiscount.first { $0.canonicalName == "WHOLE MILK" }
        #expect(appleJuice?.lineTotal == Decimal(string: "3.99"))
        #expect(wholeMilk?.lineTotal  == Decimal(string: "4.49"))
    }

    @Test func lineItemWithoutMatchingPriceIsSkipped() {
        // Add an extra name line with no corresponding price in the price region
        let extraLines = lines + [
            OCRLine(text: "Orphan Item", confidence: 0.9,
                    boundingBox: CGRect(x: 0.05, y: 0.64, width: 0.55, height: 0.03))
        ]
        // Rebuild template so the extra name is outside the name region (no price can match)
        let tightTemplate = ReceiptLayoutTemplate(
            templateName: "T", merchantNormalizedName: "M",
            fields: [
                TemplateField(label: .lineItemName,
                              region: CGRect(x: 0, y: 0.66, width: 0.68, height: 0.10)),
                TemplateField(label: .lineItemPrice,
                              region: CGRect(x: 0.68, y: 0.66, width: 0.32, height: 0.10)),
            ]
        )
        let result = parser.parse(ocrLines: extraLines, template: tightTemplate)
        // Only Apple Juice falls in the tight range; Whole Milk and Orphan are outside.
        // Apple Juice pairs with 3.99 (only price in range).
        #expect(result.lineItems.count == 1)
        #expect(result.lineItems[0].canonicalName == "APPLE JUICE")
    }

    @Test func lineItemWithNilBoundingBoxIsIgnored() {
        // OCR lines from page > 0 have nil bbox and must not be matched to any field.
        let linesWithNilBbox = lines + [
            OCRLine(text: "INVISIBLE ITEM", confidence: 0.99, boundingBox: nil),
            OCRLine(text: "9.99", confidence: 0.99, boundingBox: nil),
        ]
        let result = parser.parse(ocrLines: linesWithNilBbox, template: template)
        let names = result.lineItems.map(\.canonicalName)
        #expect(!names.contains("INVISIBLE ITEM"))
    }

    // MARK: - Discount items

    @Test func discountLineExtracted() {
        let result = parser.parse(ocrLines: lines, template: template)
        let discounts = result.lineItems.filter(\.isDiscount)
        #expect(discounts.count == 1)
    }

    @Test func discountLineTotalIsNegative() {
        let result = parser.parse(ocrLines: lines, template: template)
        let discount = result.lineItems.first(where: \.isDiscount)
        guard let total = discount?.lineTotal else { Issue.record("No discount found"); return }
        #expect(total < .zero)
    }

    @Test func discountLineTotalIsCorrectMagnitude() {
        let result = parser.parse(ocrLines: lines, template: template)
        let discount = result.lineItems.first(where: \.isDiscount)
        #expect(discount?.lineTotal == Decimal(string: "-0.50"))
    }

    // MARK: - Totals

    @Test func subtotalExtracted() {
        let result = parser.parse(ocrLines: lines, template: template)
        #expect(result.subtotal == Decimal(string: "7.98"))
    }

    @Test func totalExtracted() {
        let result = parser.parse(ocrLines: lines, template: template)
        #expect(result.total == Decimal(string: "7.98"))
    }

    @Test func subtotalNilWhenNoSubtotalField() {
        let noSubtotalTemplate = ReceiptLayoutTemplate(
            templateName: "T", merchantNormalizedName: "M",
            fields: [TemplateField(label: .total, region: CGRect(x: 0.68, y: 0.22, width: 0.32, height: 0.10))]
        )
        let result = parser.parse(ocrLines: lines, template: noSubtotalTemplate)
        #expect(result.subtotal == nil)
    }

    @Test func priceFromDollarAmountFormat() {
        // Price line with $ prefix (e.g. "$3.99") should be parsed correctly.
        let dollarLines = [OCRLine(text: "$3.99", confidence: 0.99,
                                   boundingBox: CGRect(x: 0.72, y: 0.68, width: 0.20, height: 0.05))]
        let t = ReceiptLayoutTemplate(
            templateName: "T", merchantNormalizedName: "M",
            fields: [TemplateField(label: .total, region: CGRect(x: 0.68, y: 0.64, width: 0.32, height: 0.10))]
        )
        let result = parser.parse(ocrLines: dollarLines, template: t)
        #expect(result.total == Decimal(string: "3.99"))
    }

    @Test func priceFromTaxCodeFormat() {
        // Price line with tax code (e.g. "2.69 FB") should be parsed correctly.
        let taxCodeLines = [OCRLine(text: "2.69 FB", confidence: 0.99,
                                    boundingBox: CGRect(x: 0.72, y: 0.68, width: 0.20, height: 0.05))]
        let t = ReceiptLayoutTemplate(
            templateName: "T", merchantNormalizedName: "M",
            fields: [TemplateField(label: .lineItemPrice, region: CGRect(x: 0.68, y: 0.64, width: 0.32, height: 0.10))]
        )
        // Need a matching name to get a line item
        let nameLines = taxCodeLines + [OCRLine(text: "Garlic Bread", confidence: 0.95,
                                                boundingBox: CGRect(x: 0.05, y: 0.68, width: 0.55, height: 0.05))]
        let nameField = TemplateField(label: .lineItemName, region: CGRect(x: 0, y: 0.64, width: 0.68, height: 0.10))
        let tWithName = ReceiptLayoutTemplate(
            templateName: "T", merchantNormalizedName: "M",
            fields: [nameField,
                     TemplateField(label: .lineItemPrice, region: CGRect(x: 0.68, y: 0.64, width: 0.32, height: 0.10))]
        )
        let result = parser.parse(ocrLines: nameLines, template: tWithName)
        #expect(result.lineItems.first?.lineTotal == Decimal(string: "2.69"))
    }

    // MARK: - Ignore field

    @Test func ignoreFieldLinesAreNotIncluded() {
        let result = parser.parse(ocrLines: lines, template: template)
        let rawNames = result.lineItems.map(\.rawName)
        #expect(!rawNames.contains("Thank you!"))
    }

    // MARK: - Reconciliation

    @Test func reconciledWhenItemSumMatchesSubtotal() {
        // 3.99 + 4.49 - 0.50 = 7.98 = subtotal
        let result = parser.parse(ocrLines: lines, template: template)
        #expect(result.reconciliationStatus == .reconciled)
    }

    @Test func unverifiedWhenNoSubtotal() {
        let noSubTemplate = ReceiptLayoutTemplate(
            templateName: "T", merchantNormalizedName: "M",
            fields: [
                TemplateField(label: .lineItemName,  region: CGRect(x: 0.00, y: 0.56, width: 0.68, height: 0.17)),
                TemplateField(label: .lineItemPrice, region: CGRect(x: 0.68, y: 0.56, width: 0.32, height: 0.17)),
            ]
        )
        let result = parser.parse(ocrLines: lines, template: noSubTemplate)
        #expect(result.reconciliationStatus == .unverified)
    }

    @Test func discrepancyWhenSumMismatchesSubtotal() {
        // Use a subtotal line that doesn't match the item sum
        let mismatchLines = [
            OCRLine(text: "Widget",  confidence: 0.9,  boundingBox: CGRect(x: 0.05, y: 0.68, width: 0.55, height: 0.05)),
            OCRLine(text: "5.00",    confidence: 0.99, boundingBox: CGRect(x: 0.72, y: 0.68, width: 0.20, height: 0.05)),
            OCRLine(text: "99.99",   confidence: 0.99, boundingBox: CGRect(x: 0.72, y: 0.36, width: 0.20, height: 0.05)),
        ]
        let mismatchTemplate = ReceiptLayoutTemplate(
            templateName: "T", merchantNormalizedName: "M",
            fields: [
                TemplateField(label: .lineItemName,  region: CGRect(x: 0.00, y: 0.64, width: 0.68, height: 0.10)),
                TemplateField(label: .lineItemPrice, region: CGRect(x: 0.68, y: 0.64, width: 0.32, height: 0.10)),
                TemplateField(label: .subtotal,      region: CGRect(x: 0.68, y: 0.32, width: 0.32, height: 0.10)),
            ]
        )
        let result = parser.parse(ocrLines: mismatchLines, template: mismatchTemplate)
        #expect(result.reconciliationStatus == .discrepancy)
    }

    // MARK: - Confidence

    @Test func allFieldsMatchedGivesMaxConfidence() {
        // merchant + date + total + ≥3 items → score 5/5 = 1.0
        let threeItemLines = lines + [
            OCRLine(text: "Bread",  confidence: 0.95, boundingBox: CGRect(x: 0.05, y: 0.64, width: 0.55, height: 0.02)),
            OCRLine(text: "1.99",   confidence: 0.99, boundingBox: CGRect(x: 0.72, y: 0.64, width: 0.20, height: 0.02)),
        ]
        // Extend the item regions slightly to capture the extra item
        let fullTemplate = ReceiptLayoutTemplate(
            templateName: "T", merchantNormalizedName: "GROCERY STORE",
            fields: [
                TemplateField(label: .merchantName,  region: CGRect(x: 0.00, y: 0.87, width: 1.00, height: 0.13)),
                TemplateField(label: .purchaseDate,  region: CGRect(x: 0.00, y: 0.77, width: 1.00, height: 0.10)),
                TemplateField(label: .lineItemName,  region: CGRect(x: 0.00, y: 0.56, width: 0.68, height: 0.20)),
                TemplateField(label: .lineItemPrice, region: CGRect(x: 0.68, y: 0.56, width: 0.32, height: 0.20)),
                TemplateField(label: .total,         region: CGRect(x: 0.68, y: 0.22, width: 0.32, height: 0.10)),
            ]
        )
        let result = parser.parse(ocrLines: threeItemLines, template: fullTemplate)
        #expect(result.parseConfidence == 1.0)
    }

    @Test func emptyTemplateGivesZeroConfidence() {
        let empty = ReceiptLayoutTemplate(templateName: "T", merchantNormalizedName: "M", fields: [])
        let result = parser.parse(ocrLines: lines, template: empty)
        #expect(result.parseConfidence == 0.0)
    }

    @Test func merchantOnlyGivesPartialConfidence() {
        let merchantOnly = ReceiptLayoutTemplate(
            templateName: "T", merchantNormalizedName: "GROCERY STORE",
            fields: [TemplateField(label: .merchantName,
                                   region: CGRect(x: 0.00, y: 0.87, width: 1.00, height: 0.13))]
        )
        let result = parser.parse(ocrLines: lines, template: merchantOnly)
        // score=1 (merchant), total=5 → 0.2
        #expect(result.parseConfidence == 0.2)
    }

    @Test func rawOcrTextIsJoinedLines() {
        let twoLines = [
            OCRLine(text: "LINE ONE", confidence: 0.9, boundingBox: nil),
            OCRLine(text: "LINE TWO", confidence: 0.9, boundingBox: nil),
        ]
        let result = parser.parse(ocrLines: twoLines, template: template)
        #expect(result.rawOcrText == "LINE ONE\nLINE TWO")
    }

    // MARK: - SKU extraction

    @Test func skuExtractedFromItemName() {
        let skuLines = [
            OCRLine(text: "569229 Garlic Breadsticks", confidence: 0.95,
                    boundingBox: CGRect(x: 0.05, y: 0.68, width: 0.55, height: 0.05)),
            OCRLine(text: "1.95",                     confidence: 0.99,
                    boundingBox: CGRect(x: 0.72, y: 0.68, width: 0.20, height: 0.05)),
        ]
        let skuTemplate = ReceiptLayoutTemplate(
            templateName: "T", merchantNormalizedName: "ALDI",
            fields: [
                TemplateField(label: .lineItemName,  region: CGRect(x: 0.00, y: 0.64, width: 0.68, height: 0.10)),
                TemplateField(label: .lineItemPrice, region: CGRect(x: 0.68, y: 0.64, width: 0.32, height: 0.10)),
            ]
        )
        let result = parser.parse(ocrLines: skuLines, template: skuTemplate)
        let item = result.lineItems.first
        #expect(item?.sku == "569229")
        #expect(item?.canonicalName == "GARLIC BREADSTICKS")
    }
}
