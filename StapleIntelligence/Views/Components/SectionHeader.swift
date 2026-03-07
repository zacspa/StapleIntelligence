//
//  SectionHeader.swift
//  StapleIntelligence
//

import SwiftUI

/// Standardized section label inside `AppCard` bodies.
/// Uses `AppTheme.Typography.sectionLabel` (.subheadline) in `Colors.secondary`.
struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(AppTheme.Typography.sectionLabel)
            .foregroundStyle(AppTheme.Colors.secondary)
    }
}
