//
//  InsightsView.swift
//  StapleIntelligence
//
//  Created by Zack Sparks on 3/2/26.
//

import SwiftUI
import SwiftData
import Charts

enum InsightRange: String, CaseIterable {
    case fourWeeks = "4W"
    case threeMonths = "3M"
    case sixMonths = "6M"

    var dateInterval: DateInterval {
        let now = Date()
        let cal = Calendar.current
        switch self {
        case .fourWeeks:
            return DateInterval(start: now.addingTimeInterval(-4 * 7 * 24 * 3600), end: now)
        case .threeMonths:
            let start = cal.date(byAdding: .month, value: -3, to: now) ?? now
            return DateInterval(start: start, end: now)
        case .sixMonths:
            let start = cal.date(byAdding: .month, value: -6, to: now) ?? now
            return DateInterval(start: start, end: now)
        }
    }
}

struct InsightsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var receipts: [Receipt]
    @AppStorage("insights.range") private var selectedRange = InsightRange.fourWeeks

    @State private var trendData: [DateBucketTotal] = []
    @State private var topItems: [ItemSpend] = []
    @State private var priceMoversData: [PriceMover] = []
    @State private var merchantData: [MerchantShare] = []
    @State private var selectedItem: ItemSpend? = nil

    private var engine: InsightsEngine { InsightsEngine(modelContext: modelContext) }

    var body: some View {
        NavigationStack {
            Group {
                if receipts.isEmpty {
                    ContentUnavailableView(
                        "No Insights Yet",
                        systemImage: "lightbulb",
                        description: Text("Scan more receipts to unlock spending insights.")
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            Picker("Range", selection: $selectedRange) {
                                ForEach(InsightRange.allCases, id: \.self) { range in
                                    Text(range.rawValue).tag(range)
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding()

                            VStack(spacing: 24) {
                                SpendingTrendChart(data: trendData)
                                TopItemsSection(items: topItems, onSelect: { selectedItem = $0 })
                                if !priceMoversData.isEmpty {
                                    PriceMoversSection(movers: priceMoversData)
                                }
                                MerchantBreakdownSection(merchants: Array(merchantData.prefix(5)))
                            }
                            .padding(.horizontal)
                            .padding(.bottom)
                        }
                    }
                }
            }
            .navigationTitle("Insights")
            .task(id: receipts.count * 31 + selectedRange.hashValue) {
                recompute()
            }
            .sheet(item: $selectedItem) { item in
                PriceHistorySheet(item: item, range: selectedRange.dateInterval, engine: engine)
            }
        }
    }

    private func recompute() {
        let range = selectedRange.dateInterval
        trendData = (try? engine.monthlySpend(range: range)) ?? []
        topItems = (try? engine.topItemsBySpend(range: range)) ?? []
        priceMoversData = (try? engine.priceMovers(range: range)) ?? []
        merchantData = (try? engine.merchantBreakdown(range: range)) ?? []
    }
}

private struct SpendingTrendChart: View {
    let data: [DateBucketTotal]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Spending Trend")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Chart(data) { bucket in
                BarMark(
                    x: .value("Month", bucket.date, unit: .month),
                    y: .value("$", NSDecimalNumber(decimal: bucket.total).doubleValue)
                )
                .foregroundStyle(Color.accentColor)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { value in
                    if let date = value.as(Date.self) {
                        AxisValueLabel {
                            Text(date, format: .dateTime.month(.abbreviated))
                                .font(.caption2)
                        }
                    }
                }
            }
            .frame(height: 160)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct TopItemsSection: View {
    let items: [ItemSpend]
    let onSelect: (ItemSpend) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top Items")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                Button {
                    onSelect(item)
                } label: {
                    HStack {
                        Text("\(index + 1)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .trailing)
                        Text(item.canonicalName)
                            .font(.body)
                            .foregroundStyle(.primary)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(item.total, format: .currency(code: "USD"))
                                .font(.body.monospacedDigit())
                                .foregroundStyle(.primary)
                            Text("\(item.purchaseCount)x")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if index < items.count - 1 {
                    Divider().padding(.leading, 32)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct PriceMoversSection: View {
    let movers: [PriceMover]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Price Changes (last 4 weeks)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ForEach(movers) { mover in
                HStack {
                    Text(mover.canonicalName)
                        .font(.body)
                    Spacer()
                    let isUp = mover.delta >= .zero
                    let absVal = mover.delta < .zero ? -mover.delta : mover.delta
                    Text("\(isUp ? "+" : "-")\(absVal, format: .currency(code: "USD"))")
                        .font(.body.monospacedDigit())
                        .foregroundStyle(isUp ? .red : .green)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct MerchantBreakdownSection: View {
    let merchants: [MerchantShare]

    var body: some View {
        if !merchants.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("By Merchant")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ForEach(merchants) { merchant in
                    VStack(spacing: 4) {
                        HStack {
                            Text(merchant.displayName)
                            Spacer()
                            Text(merchant.total, format: .currency(code: "USD"))
                                .font(.body.monospacedDigit())
                        }
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.accentColor.opacity(0.25))
                                .frame(width: geo.size.width, height: 4)
                                .overlay(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.accentColor)
                                        .frame(width: geo.size.width * merchant.fraction)
                                }
                        }
                        .frame(height: 4)
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

private struct PriceHistorySheet: View {
    let item: ItemSpend
    let range: DateInterval
    let engine: InsightsEngine

    @State private var history: [PricePoint] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if history.isEmpty {
                    ContentUnavailableView("No History", systemImage: "chart.line.uptrend.xyaxis")
                } else {
                    Chart(history) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Price", NSDecimalNumber(decimal: point.unitPrice).doubleValue)
                        )
                        .foregroundStyle(Color.accentColor)
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Price", NSDecimalNumber(decimal: point.unitPrice).doubleValue)
                        )
                        .foregroundStyle(Color.accentColor)
                    }
                    .chartYAxis {
                        AxisMarks(format: .currency(code: "USD"))
                    }
                    .frame(height: 200)
                    .padding()
                }
                Spacer()
            }
            .navigationTitle(item.canonicalName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            history = (try? engine.itemPriceHistory(itemId: item.id, range: range)) ?? []
        }
    }
}

#Preview {
    InsightsView()
        .modelContainer(for: [Receipt.self, LineItem.self, Merchant.self], inMemory: true)
}
