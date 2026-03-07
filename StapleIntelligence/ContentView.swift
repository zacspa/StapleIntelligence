//
//  ContentView.swift
//  StapleIntelligence
//
//  Created by Zack Sparks on 3/2/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Dashboard", systemImage: "chart.bar", value: 0) {
                DashboardView()
            }
            Tab("Receipts", systemImage: "receipt", value: 1) {
                ReceiptsView()
            }
            Tab("Insights", systemImage: "lightbulb", value: 2) {
                InsightsView()
            }
            Tab("Settings", systemImage: "gearshape", value: 3) {
                SettingsView()
            }
        }
        .tint(AppTheme.Colors.accent)
        .onChange(of: selectedTab) {
            HapticFeedback.selection()
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Receipt.self, LineItem.self, Merchant.self], inMemory: true)
}
