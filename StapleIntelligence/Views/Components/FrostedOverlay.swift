//
//  FrostedOverlay.swift
//  StapleIntelligence
//

import SwiftUI

/// Frosted .regularMaterial card overlay for loading/processing states.
struct FrostedOverlay<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(AppTheme.Spacing.xl)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppTheme.Radius.xl))
    }
}
