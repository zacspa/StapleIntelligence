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
                        VStack(spacing: AppTheme.Spacing.xl) {
                            SpendSummaryCard(monthTotal: monthTotal, prevMonthTotal: prevMonthTotal)
                            WeeklySpendChart(data: weeklyData)
                            TopMerchantsSection(merchants: topMerchants)
                        }
                        .padding()
                        .animation(AppTheme.Animation.springList, value: receipts.count)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.Colors.base)
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task(id: receipts.count) {
                recompute()
            }
        }
        .background(AppTheme.Colors.base)
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

        topMerchants = Array(((try? engine.merchantBreakdown(range: DateInterval(start: eightWeeksAgo, end: now))) ?? []).prefix(3))
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
        AppCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                SectionHeader(title: "This month")
                Text(monthTotal, format: .currency(code: "USD"))
                    .font(AppTheme.Typography.hero)
                    .foregroundStyle(.primary)
                if let pct = deltaPct {
                    HStack(spacing: AppTheme.Spacing.xs) {
                        DeltaBadge(pct: pct)
                        Text("vs last month")
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct WeeklySpendChart: View {
    let data: [DateBucketTotal]

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                SectionHeader(title: "Last 8 Weeks")
                Chart(data) { bucket in
                    BarMark(
                        x: .value("Week", bucket.date, unit: .weekOfYear),
                        y: .value("$", NSDecimalNumber(decimal: bucket.total).doubleValue)
                    )
                    .foregroundStyle(AppTheme.Colors.accent)
                    .cornerRadius(AppTheme.Radius.xs)
                }
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .weekOfYear)) { value in
                        if let date = value.as(Date.self) {
                            AxisValueLabel {
                                Text(date, format: .dateTime.month(.abbreviated).day())
                                    .font(.caption2)
                            }
                            .foregroundStyle(AppTheme.Colors.secondary)
                        }
                    }
                }
                .frame(height: 160)
                .shadow(color: AppTheme.Colors.accent.opacity(0.45), radius: 6)
                .shadow(color: AppTheme.Colors.accent.opacity(0.20), radius: 16)
            }
        }
    }
}

private struct TopMerchantsSection: View {
    let merchants: [MerchantShare]

    var body: some View {
        if !merchants.isEmpty {
            AppCard {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    SectionHeader(title: "Top Merchants (8 weeks)")
                    ForEach(merchants) { merchant in
                        VStack(spacing: AppTheme.Spacing.xs) {
                            HStack {
                                Text(merchant.displayName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(merchant.total, format: .currency(code: "USD"))
                                    .font(AppTheme.Typography.bodyMono)
                            }
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(AppTheme.Colors.accent.opacity(0.25))
                                    .frame(width: geo.size.width, height: 4)
                                    .overlay(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(AppTheme.Colors.accent)
                                            .frame(width: geo.size.width * merchant.fraction)
                                    }
                            }
                            .frame(height: 4)
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    DashboardView()
        .modelContainer(for: [Receipt.self, LineItem.self, Merchant.self], inMemory: true)
}
