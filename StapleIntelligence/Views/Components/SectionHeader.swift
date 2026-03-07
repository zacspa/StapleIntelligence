//
//  SectionHeader.swift
//  StapleIntelligence
//

import SwiftUI

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(AppTheme.Typography.sectionLabel)
            .foregroundStyle(AppTheme.Colors.secondary)
    }
}
