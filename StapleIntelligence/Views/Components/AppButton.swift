//
//  AppButton.swift
//  StapleIntelligence
//

import SwiftUI

/// Full-width Neon Mint filled button. Use for primary actions (e.g. "Save Anyway").
/// Label text is rendered in `Colors.base` (dark) for contrast against the mint fill.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(AppTheme.Colors.base)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppTheme.Spacing.md)
            .padding(.horizontal, AppTheme.Spacing.lg)
            .background(
                configuration.isPressed
                    ? AppTheme.Colors.accent.opacity(0.80)
                    : AppTheme.Colors.accent
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg))
    }
}

/// Full-width secondary button with accent-tinted background and hairline border.
/// Use for lower-priority actions (e.g. "Rescan").
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(AppTheme.Colors.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppTheme.Spacing.md)
            .padding(.horizontal, AppTheme.Spacing.lg)
            .background(
                configuration.isPressed
                    ? AppTheme.Colors.accent.opacity(0.07)
                    : AppTheme.Colors.accent.opacity(0.15)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                    .strokeBorder(AppTheme.Colors.border, lineWidth: 1)
            )
    }
}
