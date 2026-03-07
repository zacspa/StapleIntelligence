//
//  DeltaBadge.swift
//  StapleIntelligence
//

import SwiftUI

/// Capsule delta indicator. Positive pct = spend up / price increase (shown red).
/// Negative pct = spend down / price decrease (shown green).
struct DeltaBadge: View {
    let pct: Double  // 0.10 = +10%, -0.05 = -5%

    private var isUp: Bool { pct >= 0 }

    var body: some View {
        Text("\(isUp ? "+" : "")\(pct * 100, specifier: "%.0f")%")
            .font(AppTheme.Typography.badge)
            .foregroundStyle(isUp ? AppTheme.Colors.negative : AppTheme.Colors.positive)
            .padding(.horizontal, AppTheme.Spacing.sm)
            .padding(.vertical, AppTheme.Spacing.xxs + 1)
            .background((isUp ? AppTheme.Colors.negative : AppTheme.Colors.positive).opacity(0.15))
            .clipShape(Capsule())
    }
}
