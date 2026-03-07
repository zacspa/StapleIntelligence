# Plan: Analytics MVP

**Status**: Completed
**Created**: 2026-03-05
**Completed**: 2026-03-05

## Goal
Implement real InsightsEngine queries, a spending-overview Dashboard, and a drill-down Insights tab.

## Scope
- `Engine/Impl/InsightsEngine.swift` — implement all 6 protocol methods
- `Views/Public/Dashboard/DashboardView.swift` — full rewrite
- `Views/Public/Insights/InsightsView.swift` — full rewrite

## Acceptance Criteria
- [x] InsightsEngine.weeklySpend groups receipts by Monday-of-week, sums totals
- [x] InsightsEngine.monthlySpend groups receipts by month start, sums totals
- [x] InsightsEngine.topItemsBySpend groups by canonicalName, skips discounts, sorts descending
- [x] InsightsEngine.itemPriceHistory resolves canonicalName from itemId, returns sorted PricePoints
- [x] InsightsEngine.priceMovers uses fixed rolling 4-week windows, filters by >$0.10 and >5% delta
- [x] InsightsEngine.merchantBreakdown sums by merchant, computes fraction of grand total
- [x] DashboardView shows ContentUnavailableView when no receipts
- [x] DashboardView shows month summary card with delta badge, 8-week bar chart, top 3 merchants
- [x] InsightsView shows ContentUnavailableView when no receipts
- [x] InsightsView shows 4W/3M/6M range picker, trend chart, top items, price movers, merchant breakdown
- [x] Tapping a top item presents PriceHistorySheet with LineMark chart

## Approach
- All engine methods are synchronous (no async/await) to stay within 300ms dashboard budget
- Decimal arithmetic throughout; NSDecimalNumber bridge only for Swift Charts (Double required by API)
- @Query on receipts used as change trigger only; @State holds computed analytics data
- .task(id:) recomputes when receipt count or selected range changes
