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

    private func receiptsInRange(_ range: DateInterval) -> [Receipt] {
        let all = (try? modelContext.fetch(FetchDescriptor<Receipt>())) ?? []
        return all.filter { r in
            guard let date = r.purchaseDate else { return false }
            return range.contains(date)
        }
    }

    func weeklySpend(range: DateInterval) throws -> [DateBucketTotal] {
        let cal = Calendar.current
        var buckets: [Date: Decimal] = [:]
        for receipt in receiptsInRange(range) {
            guard let date = receipt.purchaseDate, let total = receipt.total else { continue }
            guard let weekInterval = cal.dateInterval(of: .weekOfYear, for: date) else { continue }
            buckets[weekInterval.start, default: .zero] += total
        }
        return buckets.map { DateBucketTotal(date: $0.key, total: $0.value) }
            .sorted { $0.date < $1.date }
    }

    func monthlySpend(range: DateInterval) throws -> [DateBucketTotal] {
        let cal = Calendar.current
        var buckets: [Date: Decimal] = [:]
        for receipt in receiptsInRange(range) {
            guard let date = receipt.purchaseDate, let total = receipt.total else { continue }
            guard let monthInterval = cal.dateInterval(of: .month, for: date) else { continue }
            buckets[monthInterval.start, default: .zero] += total
        }
        return buckets.map { DateBucketTotal(date: $0.key, total: $0.value) }
            .sorted { $0.date < $1.date }
    }

    func topItemsBySpend(range: DateInterval) throws -> [ItemSpend] {
        var totals: [String: Decimal] = [:]
        var counts: [String: Int] = [:]
        var firstId: [String: UUID] = [:]
        for receipt in receiptsInRange(range) {
            for item in receipt.lineItems {
                guard !item.isDiscount else { continue }
                let name = item.canonicalName
                totals[name, default: .zero] += item.lineTotal
                counts[name, default: 0] += 1
                if firstId[name] == nil { firstId[name] = item.id }
            }
        }
        return totals.compactMap { name, total in
            guard let id = firstId[name] else { return nil }
            return ItemSpend(id: id, canonicalName: name, total: total, purchaseCount: counts[name, default: 0])
        }.sorted { $0.total > $1.total }
    }

    func itemPriceHistory(itemId: UUID, range: DateInterval) throws -> [PricePoint] {
        let allItems = (try? modelContext.fetch(FetchDescriptor<LineItem>())) ?? []
        guard let target = allItems.first(where: { $0.id == itemId }) else { return [] }
        let canonicalName = target.canonicalName
        var points: [PricePoint] = []
        for receipt in receiptsInRange(range) {
            guard let date = receipt.purchaseDate else { continue }
            for item in receipt.lineItems where item.canonicalName == canonicalName {
                let price: Decimal
                if item.isWeightItem {
                    guard let up = item.unitPrice else { continue }
                    price = up
                } else {
                    price = item.unitPrice ?? item.lineTotal
                }
                points.append(PricePoint(date: date, unitPrice: price))
            }
        }
        return points.sorted { $0.date < $1.date }
    }

    func priceMovers(range: DateInterval) throws -> [PriceMover] {
        let now = Date()
        let fourWeeks: TimeInterval = 4 * 7 * 24 * 3600
        let currentWindow = DateInterval(start: now.addingTimeInterval(-fourWeeks), end: now)
        let previousWindow = DateInterval(start: now.addingTimeInterval(-2 * fourWeeks), end: now.addingTimeInterval(-fourWeeks))

        var currentTotals: [String: Decimal] = [:]
        var currentCounts: [String: Int] = [:]
        var currentFirstIds: [String: UUID] = [:]
        for receipt in receiptsInRange(currentWindow) {
            for item in receipt.lineItems where !item.isDiscount {
                let name = item.canonicalName
                let price: Decimal
                if item.isWeightItem {
                    guard let up = item.unitPrice else { continue }
                    price = up
                } else {
                    price = item.unitPrice ?? item.lineTotal
                }
                currentTotals[name, default: .zero] += price
                currentCounts[name, default: 0] += 1
                if currentFirstIds[name] == nil { currentFirstIds[name] = item.id }
            }
        }

        var prevTotals: [String: Decimal] = [:]
        var prevCounts: [String: Int] = [:]
        for receipt in receiptsInRange(previousWindow) {
            for item in receipt.lineItems where !item.isDiscount {
                let name = item.canonicalName
                let price: Decimal
                if item.isWeightItem {
                    guard let up = item.unitPrice else { continue }
                    price = up
                } else {
                    price = item.unitPrice ?? item.lineTotal
                }
                prevTotals[name, default: .zero] += price
                prevCounts[name, default: 0] += 1
            }
        }

        var movers: [PriceMover] = []
        for (name, currentTotal) in currentTotals {
            guard let prevTotal = prevTotals[name] else { continue }
            let currentAvg = currentTotal / Decimal(max(currentCounts[name, default: 1], 1))
            let prevAvg = prevTotal / Decimal(max(prevCounts[name, default: 1], 1))
            let delta = currentAvg - prevAvg
            let absDelta = delta < .zero ? -delta : delta
            guard absDelta > Decimal(string: "0.10")! else { continue }
            let pctDelta = prevAvg != .zero ? absDelta / prevAvg : .zero
            guard pctDelta > Decimal(string: "0.05")! else { continue }
            guard let id = currentFirstIds[name] else { continue }
            movers.append(PriceMover(id: id, canonicalName: name, previousAvg: prevAvg, currentAvg: currentAvg))
        }
        return movers.sorted { ($0.currentAvg - $0.previousAvg) > ($1.currentAvg - $1.previousAvg) }
    }

    func merchantBreakdown(range: DateInterval) throws -> [MerchantShare] {
        let unknownId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        var totals: [UUID: Decimal] = [:]
        var names: [UUID: String] = [:]
        for receipt in receiptsInRange(range) {
            guard let total = receipt.total else { continue }
            let merchantId = receipt.merchant?.id ?? unknownId
            totals[merchantId, default: .zero] += total
            names[merchantId] = receipt.merchant?.displayName ?? "Unknown"
        }
        let grandTotal = totals.values.reduce(.zero, +)
        guard grandTotal > .zero else { return [] }
        return totals.map { id, total in
            MerchantShare(
                id: id,
                displayName: names[id] ?? "Unknown",
                total: total,
                fraction: (NSDecimalNumber(decimal: total / grandTotal)).doubleValue
            )
        }.sorted { $0.total > $1.total }
    }
}
