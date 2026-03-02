//
//  SettingsView.swift
//  StapleIntelligence
//
//  Created by Zack Sparks on 3/2/26.
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Settings",
                systemImage: "gearshape",
                description: Text("Settings coming soon.")
            )
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
}
