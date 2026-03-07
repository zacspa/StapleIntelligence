//
//  DashboardView.swift
//  StapleIntelligence
//
//  Created by Zack Sparks on 3/2/26.
//

import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var receipts: [Receipt]

    @State private var weeklyData: [DateBucketTotal] = []
    @State private var monthTotal: Decimal = .zero
    @State private var prevMonthTotal: Decimal = .zero
    @State private var topMerchants: [MerchantShare] = []

    private var engine: InsightsEngine { InsightsEngine(modelContext: modelContext) }

    var body: some View {
        NavigationStack {
            Group {
                if receipts.isEmpty {
                    ContentUnavailableView(
                        "No Data Yet",
                        systemImage: "chart.bar",
                        description: Text("Scan receipts to see your spending dashboard.")
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            SpendSummaryCard(monthTotal: monthTotal, prevMonthTotal: prevMonthTotal)
                            WeeklySpendChart(data: weeklyData)
                            TopMerchantsSection(merchants: topMerchants)
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Dashboard")
            .task(id: receipts.count) {
                recompute()
            }
        }
    }

    private func recompute() {
        let cal = Calendar.current
        let now = Date()
        guard
            let thisMonthInterval = cal.dateInterval(of: .month, for: now),
            let prevMonthDate = cal.date(byAdding: .month, value: -1, to: now),
            let prevMonthInterval = cal.dateInterval(of: .month, for: prevMonthDate)
        else { return }

        let eightWeeksAgo = now.addingTimeInterval(-8 * 7 * 24 * 3600)
        weeklyData = (try? engine.weeklySpend(range: DateInterval(start: eightWeeksAgo, end: now))) ?? []

        let twoMonthRange = DateInterval(start: prevMonthInterval.start, end: thisMonthInterval.end)
        let monthlyBuckets = (try? engine.monthlySpend(range: twoMonthRange)) ?? []
        monthTotal = monthlyBuckets.first {
            cal.isDate($0.date, equalTo: thisMonthInterval.start, toGranularity: .month)
        }?.total ?? .zero
        prevMonthTotal = monthlyBuckets.first {
            cal.isDate($0.date, equalTo: prevMonthInterval.start, toGranularity: .month)
        }?.total ?? .zero

        topMerchants = Array(((try? engine.merchantBreakdown(range: thisMonthInterval)) ?? []).prefix(3))
    }
}

private struct SpendSummaryCard: View {
    let monthTotal: Decimal
    let prevMonthTotal: Decimal

    private var deltaPct: Double? {
        guard prevMonthTotal > .zero else { return nil }
        let d = monthTotal - prevMonthTotal
        return NSDecimalNumber(decimal: d / prevMonthTotal).doubleValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This month")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(monthTotal, format: .currency(code: "USD"))
                .font(.system(size: 40, weight: .bold, design: .rounded))
            if let pct = deltaPct {
                let isUp = pct >= 0
                Text("\(isUp ? "+" : "")\(pct * 100, specifier: "%.0f")% vs last month")
                    .font(.caption)
                    .foregroundStyle(isUp ? .red : .green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((isUp ? Color.red : Color.green).opacity(0.12))
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct WeeklySpendChart: View {
    let data: [DateBucketTotal]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last 8 Weeks")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Chart(data) { bucket in
                BarMark(
                    x: .value("Week", bucket.date, unit: .weekOfYear),
                    y: .value("$", NSDecimalNumber(decimal: bucket.total).doubleValue)
                )
                .foregroundStyle(Color.accentColor)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear)) { value in
                    if let date = value.as(Date.self) {
                        AxisValueLabel {
                            Text(date, format: .dateTime.month(.abbreviated).day())
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

private struct TopMerchantsSection: View {
    let merchants: [MerchantShare]

    var body: some View {
        if !merchants.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Top Merchants")
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

#Preview {
    DashboardView()
        .modelContainer(for: [Receipt.self, LineItem.self, Merchant.self], inMemory: true)
}
