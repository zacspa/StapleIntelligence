//
//  StapleIntelligenceApp.swift
//  StapleIntelligence
//
//  Created by Zack Sparks on 3/2/26.
//

import SwiftUI
import SwiftData
import UIKit

@main
struct StapleIntelligenceApp: App {
    /// UIAppearance configuration must run before any window is created, making `App.init()`
    /// the correct place. Three UIKit control classes are configured here:
    ///
    /// - **UITabBar**: frosted blur background + explicit Neon Mint selected-item tint.
    ///   `configureWithTransparentBackground()` resets item colors to defaults, so all
    ///   three layout appearances (stacked, inline, compact) must be set explicitly.
    ///
    /// - **UINavigationBar**: frosted dark background with white title text across all
    ///   four appearance states (standard, scrollEdge, compact, compactScrollEdge).
    ///   Setting only `standardAppearance` leaves `scrollEdgeAppearance` using the default
    ///   opaque background, which makes titles invisible at position 0 on dark screens.
    ///
    /// - **UISegmentedControl**: accent-tinted selected segment.
    init() {
        // Tab bar — ultraThinMaterialDark frosted blur
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithTransparentBackground()
        tabAppearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        tabAppearance.shadowColor = UIColor(AppTheme.Colors.border)
        let accentUIColor = UIColor(AppTheme.Colors.accent)
        let tertiaryUIColor = UIColor(AppTheme.Colors.tertiary)
        for layout in [tabAppearance.stackedLayoutAppearance,
                       tabAppearance.inlineLayoutAppearance,
                       tabAppearance.compactInlineLayoutAppearance] {
            layout.selected.iconColor = accentUIColor
            layout.selected.titleTextAttributes = [.foregroundColor: accentUIColor]
            layout.normal.iconColor = tertiaryUIColor
            layout.normal.titleTextAttributes = [.foregroundColor: tertiaryUIColor]
        }
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance

        // Navigation bar — frosted dark + white titles across all states (standard, scrollEdge, compact)
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithTransparentBackground()
        navAppearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        navAppearance.shadowColor = UIColor(AppTheme.Colors.border)
        navAppearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        navAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
        UINavigationBar.appearance().compactScrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().tintColor = UIColor(AppTheme.Colors.accent)

        // Segmented control — accent tint
        UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(AppTheme.Colors.accentDim)
        UISegmentedControl.appearance().setTitleTextAttributes(
            [.foregroundColor: UIColor(AppTheme.Colors.accent)], for: .selected)
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Receipt.self,
            LineItem.self,
            Merchant.self,
            MerchantProduct.self,
            MergeRule.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        func makeContainer() throws -> ModelContainer {
            try ModelContainer(for: schema, configurations: [modelConfiguration])
        }

        do {
            return try makeContainer()
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
