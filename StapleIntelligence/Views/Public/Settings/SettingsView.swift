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
            SettingsForm()
                .navigationTitle("Settings")
        }
    }
}

private struct SettingsForm: View {
    @AppStorage("validator.reconciliation") private var detectReconciliation = true
    @AppStorage("validator.priceConflicts") private var detectPriceConflicts = true
    @AppStorage("validator.missingData")    private var detectMissingData    = true
    @AppStorage("validator.taxRate")        private var detectTaxRate        = true
    @AppStorage("validator.duplicates")     private var detectDuplicates     = true
    @AppStorage("validator.itemQuality")    private var detectItemQuality    = true

    var body: some View {
        Form {
            Section {
                Toggle("Totals & reconciliation", isOn: $detectReconciliation)
                Toggle("Price conflicts", isOn: $detectPriceConflicts)
                Toggle("Missing merchant & date", isOn: $detectMissingData)
                Toggle("Unusual tax rate", isOn: $detectTaxRate)
                Toggle("Duplicate items", isOn: $detectDuplicates)
                Toggle("Item name & price quality", isOn: $detectItemQuality)
            } header: {
                Text("Issue Detection")
            } footer: {
                Text("OCR confidence and parse failures are always checked.")
            }

            #if DEBUG
            Section("Developer") {
                SkuGateToggle()
            }
            #endif
        }
    }
}

#if DEBUG
private struct SkuGateToggle: View {
    @State private var skuGated = ReceiptParser.useSkuGatedNameCollection

    var body: some View {
        Toggle("SKU-gated name collection", isOn: $skuGated)
            .onChange(of: skuGated) { _, newValue in
                ReceiptParser.useSkuGatedNameCollection = newValue
            }
        Text("When on, only lines with a 3–9 digit SKU prefix are accepted as item names in split-column (ALDI-style) receipts.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
#endif

#Preview {
    SettingsView()
}
