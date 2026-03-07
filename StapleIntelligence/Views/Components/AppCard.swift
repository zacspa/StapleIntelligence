//
//  AppCard.swift
//  StapleIntelligence
//

import SwiftUI

/// Card container with elevated surface background, hairline border, and optional accent glow.
struct AppCard<Content: View>: View {
    var glow: Bool = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(AppTheme.Spacing.lg)
            .background(AppTheme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                    .strokeBorder(AppTheme.Colors.border, lineWidth: 1)
            )
            .shadow(
                color: glow ? AppTheme.Colors.accent.opacity(AppTheme.Glow.accentOpacity) : .clear,
                radius: AppTheme.Glow.accentRadius
            )
            .shadow(
                color: glow ? AppTheme.Colors.accent.opacity(AppTheme.Glow.accentOpacity2) : .clear,
                radius: AppTheme.Glow.accentRadius2
            )
    }
}
