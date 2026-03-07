//
//  StapleIntelligenceApp.swift
//  StapleIntelligence
//
//  Created by Zack Sparks on 3/2/26.
//

import SwiftUI
import SwiftData

@main
struct StapleIntelligenceApp: App {
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
