//
//  DemoDataSeeder.swift
//  StapleIntelligence
//

#if DEBUG
import SwiftData
import Foundation

/// Inserts synthetic historical grocery receipts for testing Dashboard and Insights views.
///
/// Data covers ~6 months (Sep 2025 – Mar 2026) across three merchants.
/// Several ALDI items (Sharp Cheddar, Organic Milk, Large Eggs, etc.) intentionally
/// have higher prices in the last 4 weeks to populate the Price Changes section.
struct DemoDataSeeder {

    // MARK: - Public entry point

    static func seed(into context: ModelContext) {
        let aldi       = findOrCreate("ALDI",        normalized: "ALDI",        in: context)
        let kroger     = findOrCreate("Kroger",      normalized: "KROGER",      in: context)
        let wholefoods = findOrCreate("Whole Foods", normalized: "WHOLE FOODS", in: context)

        for r in aldiReceipts(merchant: aldi)
                + krogerReceipts(merchant: kroger)
                + wholeFoodsReceipts(merchant: wholefoods) {
            context.insert(r)
        }
        try? context.save()
    }

    // MARK: - ALDI (weekly-ish, 13 receipts)
    //
    // Prices change after 2026-02-07 (the boundary between the two price-mover windows)
    // so the following items surface in the Price Changes section:
    //   Sharp Cheddar $1.79 → $2.29  (+28%)
    //   Organic 2% Milk $2.25 → $2.99  (+33%)
    //   Large Eggs $1.97 → $3.49  (+77%)
    //   Grape Tomatoes $1.65 → $2.49  (+51%)
    //   HAZ Coffee Creamer $2.39 → $2.99  (+25%)

    private static func aldiReceipts(merchant: Merchant) -> [Receipt] {
        [
            aldiBig  (merchant, date(2025,  9,  7), new: false),
            aldiSmall(merchant, date(2025,  9, 21), new: false),
            aldiBig  (merchant, date(2025, 10,  5), new: false),
            aldiSmall(merchant, date(2025, 10, 19), new: false),
            aldiBig  (merchant, date(2025, 11,  2), new: false),
            aldiSmall(merchant, date(2025, 11, 16), new: false),
            aldiBig  (merchant, date(2025, 11, 30), new: false),
            aldiSmall(merchant, date(2025, 12, 14), new: false),
            aldiBig  (merchant, date(2026,  1,  4), new: false),
            aldiSmall(merchant, date(2026,  1, 18), new: false),
            aldiBig  (merchant, date(2026,  2,  1), new: false),  // still in previous window
            aldiSmall(merchant, date(2026,  2, 15), new: true),   // current window, new prices
            aldiBig  (merchant, date(2026,  3,  1), new: true),   // current window, new prices
        ]
    }

    private static func aldiBig(_ merchant: Merchant, _ d: Date, new: Bool) -> Receipt {
        let cheddar  = new ? "2.29" : "1.79"
        let milk     = new ? "2.99" : "2.25"
        let eggs     = new ? "3.49" : "1.97"
        let creamer  = new ? "2.99" : "2.39"
        let tomatoes = new ? "2.49" : "1.65"

        let items = makeItems([
            ("Sharp Cheddar",       cheddar,  "382439"),
            ("Sharp Cheddar",       cheddar,  "382439"),
            ("Organic 2% Milk",     milk,     "416961"),
            ("Organic 2% Milk",     milk,     "416961"),
            ("Large Eggs",          eggs,     "406491"),
            ("Large Eggs",          eggs,     "406491"),
            ("Spaghetti",           "1.89",   "389573"),
            ("Spaghetti",           "1.89",   "389573"),
            ("Garlic Breadsticks",  "1.95",   "553229"),
            ("Assorted Hummus",     "2.50",   "343827"),
            ("Assorted Hummus",     "2.50",   "343827"),
            ("Grape Tomatoes",      tomatoes, "357377"),
            ("Organic Tofu",        "1.35",   "384101"),
            ("Organic Tofu",        "1.35",   "384101"),
            ("HAZ Coffee Creamer",  creamer,  "506562"),
            ("HAZ Coffee Creamer",  creamer,  "506562"),
            ("Yellow Onions",       "1.59",   "341878"),
            ("Mayonnaise",          "2.99",   "52002"),
            ("Sour Cream",          "1.79",   "382931"),
            ("Corn Flakes",         "2.09",   "306768"),
            ("Macaroni & Cheese",   "0.56",   "399590"),
            ("Unsalted Butter",     "3.29",   "420908"),
            ("Bone Broth",          "2.99",   "475137"),
            ("Bone Broth",          "2.99",   "475137"),
            ("Premium Napkins",     "2.29",   "343709"),
            ("Bath Tissue",         "8.99",   "530003"),
        ])
        return makeReceipt(merchant: merchant, date: d, items: items, taxAmount: "1.42")
    }

    private static func aldiSmall(_ merchant: Merchant, _ d: Date, new: Bool) -> Receipt {
        let cheddar  = new ? "2.29" : "1.79"
        let milk     = new ? "2.99" : "2.25"
        let eggs     = new ? "3.49" : "1.97"
        let tomatoes = new ? "2.49" : "1.65"

        let items = makeItems([
            ("Sharp Cheddar",      cheddar,  "382439"),
            ("Organic 2% Milk",    milk,     "416961"),
            ("Large Eggs",         eggs,     "406491"),
            ("Spaghetti",          "1.89",   "389573"),
            ("Grape Tomatoes",     tomatoes, "357377"),
            ("Organic Tofu",       "1.35",   "384101"),
            ("Garlic Breadsticks", "1.95",   "553229"),
            ("Yellow Onions",      "1.59",   "341878"),
            ("Sour Cream",         "1.79",   "382931"),
        ])
        return makeReceipt(merchant: merchant, date: d, items: items, taxAmount: "0")
    }

    // MARK: - Kroger (bi-weekly, 6 receipts)

    private static func krogerReceipts(merchant: Merchant) -> [Receipt] {
        [
            krogerRun(merchant, date(2025,  9, 28)),
            krogerRun(merchant, date(2025, 10, 26)),
            krogerRun(merchant, date(2025, 11, 23)),
            krogerRun(merchant, date(2025, 12, 28)),
            krogerRun(merchant, date(2026,  1, 25)),
            krogerRun(merchant, date(2026,  2, 22)),
        ]
    }

    private static func krogerRun(_ merchant: Merchant, _ d: Date) -> Receipt {
        let items = makeItems([
            ("Chicken Breast",   "9.47",  nil),
            ("Romaine Lettuce",  "2.49",  nil),
            ("Greek Yogurt",     "5.99",  nil),
            ("Sourdough Bread",  "3.49",  nil),
            ("Orange Juice",     "4.99",  nil),
            ("Pasta Sauce",      "2.99",  nil),
            ("Bananas",          "1.34",  nil),
            ("Cheddar Cheese",   "4.99",  nil),
            ("Ground Turkey",    "7.49",  nil),
            ("Frozen Peas",      "1.99",  nil),
        ])
        return makeReceipt(merchant: merchant, date: d, items: items, taxAmount: "0.55")
    }

    // MARK: - Whole Foods (monthly, 3 receipts)

    private static func wholeFoodsReceipts(merchant: Merchant) -> [Receipt] {
        [
            wholeFoodsRun(merchant, date(2025, 10, 12)),
            wholeFoodsRun(merchant, date(2025, 12,  7)),
            wholeFoodsRun(merchant, date(2026,  2,  8)),
        ]
    }

    private static func wholeFoodsRun(_ merchant: Merchant, _ d: Date) -> Receipt {
        let items = makeItems([
            ("Wild Salmon Fillet",  "18.99", nil),
            ("Kombucha",            "3.99",  nil),
            ("Almond Flour",        "8.99",  nil),
            ("Coconut Milk",        "2.49",  nil),
            ("Avocados",            "5.99",  nil),
            ("Baby Spinach",        "4.99",  nil),
            ("Cage Free Eggs",      "6.99",  nil),
            ("Grass Fed Butter",    "7.99",  nil),
            ("Oat Milk",            "4.49",  nil),
        ])
        return makeReceipt(merchant: merchant, date: d, items: items, taxAmount: "0.81")
    }

    // MARK: - Helpers

    private static func dec(_ s: String) -> Decimal {
        Decimal(string: s, locale: Locale(identifier: "en_US_POSIX")) ?? .zero
    }

    private static func makeItems(_ tuples: [(String, String, String?)]) -> [LineItem] {
        tuples.enumerated().map { index, t in
            let (name, priceStr, sku) = t
            let price = dec(priceStr)
            return LineItem(
                rawName: name,
                canonicalName: name,
                itemType: .byCount(count: 1),
                unitPrice: price,
                lineTotal: price,
                isDiscount: false,
                confidence: 0.95,
                sku: sku,
                sortOrder: index
            )
        }
    }

    private static func makeReceipt(merchant: Merchant, date: Date, items: [LineItem],
                                    taxAmount: String) -> Receipt {
        let tax      = dec(taxAmount)
        let subtotal = items.reduce(Decimal.zero) { $0 + $1.lineTotal }
        let total    = subtotal + tax
        return Receipt(
            merchant: merchant,
            purchaseDate: date,
            lineItems: items,
            subtotal: subtotal,
            tax: tax,
            total: total,
            parseConfidence: 0.94,
            reconciliationStatus: .reconciled
        )
    }

    private static func findOrCreate(_ display: String, normalized: String,
                                     in context: ModelContext) -> Merchant {
        var desc = FetchDescriptor<Merchant>(
            predicate: #Predicate { $0.normalizedName == normalized }
        )
        desc.fetchLimit = 1
        if let existing = try? context.fetch(desc).first { return existing }
        let m = Merchant(displayName: display, normalizedName: normalized)
        context.insert(m)
        return m
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
#endif
