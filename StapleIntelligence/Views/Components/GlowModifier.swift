//
//  GlowModifier.swift
//  StapleIntelligence
//

import SwiftUI

/// Applies a double-shadow bloom effect to any view.
///
/// Two `.shadow()` calls are layered — a tight inner glow (`radius1`) for the
/// bright core and a diffuse outer bloom (`radius2`) — to simulate a neon
/// light effect on dark backgrounds without Core Image filters.
///
/// Use `.glowAccent()` for Neon Mint glow and `.glowCaution()` for amber glow.
struct GlowModifier: ViewModifier {
    var color: Color
    var radius1: CGFloat
    var opacity1: Double
    var radius2: CGFloat
    var opacity2: Double

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(opacity1), radius: radius1)
            .shadow(color: color.opacity(opacity2), radius: radius2)
    }
}

extension View {
    func glowAccent() -> some View {
        modifier(GlowModifier(
            color: AppTheme.Colors.accent,
            radius1: AppTheme.Glow.accentRadius,
            opacity1: AppTheme.Glow.accentOpacity,
            radius2: AppTheme.Glow.accentRadius2,
            opacity2: AppTheme.Glow.accentOpacity2
        ))
    }

    func glowCaution() -> some View {
        modifier(GlowModifier(
            color: AppTheme.Colors.caution,
            radius1: AppTheme.Glow.cautionRadius,
            opacity1: AppTheme.Glow.cautionOpacity,
            radius2: AppTheme.Glow.cautionRadius * 2,
            opacity2: AppTheme.Glow.cautionOpacity * 0.5
        ))
    }
}
