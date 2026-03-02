//
//  InsightsView.swift
//  StapleIntelligence
//
//  Created by Zack Sparks on 3/2/26.
//

import SwiftUI

struct InsightsView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No Insights Yet",
                systemImage: "lightbulb",
                description: Text("Scan more receipts to unlock spending insights.")
            )
            .navigationTitle("Insights")
        }
    }
}

#Preview {
    InsightsView()
}
