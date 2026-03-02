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
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        func makeContainer() throws -> ModelContainer {
            try ModelContainer(for: schema, configurations: [modelConfiguration])
        }

        do {
            return try makeContainer()
        } catch {
#if DEBUG
            // Schema changed — destroy the old store and retry once.
            let storeURL = modelConfiguration.url
            let fm = FileManager.default
            let siblings = [storeURL,
                            storeURL.appendingPathExtension("shm"),
                            storeURL.appendingPathExtension("wal")]
            for url in siblings where fm.fileExists(atPath: url.path) {
                try? fm.removeItem(at: url)
            }
            do {
                return try makeContainer()
            } catch {
                fatalError("Could not create ModelContainer after store reset: \(error)")
            }
#else
            fatalError("Could not create ModelContainer: \(error)")
#endif
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
