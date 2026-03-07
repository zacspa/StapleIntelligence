//
//  ItemDetailView.swift
//  StapleIntelligence
//
//  Created by Zack Sparks on 3/2/26.
//

import SwiftUI
import SwiftData

struct ItemDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let item: LineItem
    let receipt: Receipt

    @State private var canonicalName: String

    init(item: LineItem, receipt: Receipt) {
        self.item = item
        self.receipt = receipt
        _canonicalName = State(initialValue: item.canonicalName)
    }

    private var isSaveDisabled: Bool {
        let trimmed = canonicalName.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed == item.canonicalName
    }

    var body: some View {
        Form {
            Section("Name") {
                TextField("Canonical name", text: $canonicalName)
                if item.rawName != item.canonicalName {
                    Text(item.rawName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Price") {
                LabeledContent("Total") {
                    Text(item.lineTotal, format: .currency(code: "USD"))
                        .monospacedDigit()
                }
                if case .byWeight(let qty, let unit) = item.itemType, let unitPrice = item.unitPrice {
                    LabeledContent("Unit Price") {
                        Text(unitPrice, format: .currency(code: "USD"))
                            .monospacedDigit()
                    }
                    LabeledContent("Quantity") {
                        Text("\(String(format: "%.2f", qty)) \(unit.rawValue)")
                            .monospacedDigit()
                    }
                }
            }

            Section("Details") {
                LabeledContent("SKU", value: item.sku ?? "—")
                LabeledContent("Confidence") {
                    Text("\(Int(item.confidence * 100))%")
                        .foregroundStyle(item.confidence < 0.6 ? AppTheme.Colors.caution : .primary)
                        .monospacedDigit()
                }
                if item.isDiscount {
                    LabeledContent("Type", value: "Discount")
                        .foregroundStyle(AppTheme.Colors.negative)
                }
            }

            Section("Receipt") {
                LabeledContent("Merchant", value: receipt.merchant?.displayName ?? "Unknown")
                LabeledContent("Date", value: receipt.purchaseDate?.formatted(date: .abbreviated, time: .omitted) ?? "Unknown")
            }

            Section("Price History") {
                ContentUnavailableView(
                    "No Price History",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Price history across receipts will appear here.")
                )
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.Colors.base)
        .foregroundStyle(item.isDiscount ? AppTheme.Colors.negative : .primary)
        .navigationTitle(item.canonicalName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(isSaveDisabled)
            }
        }
    }

    private func save() {
        let newName = canonicalName.trimmingCharacters(in: .whitespaces)
        if newName != item.canonicalName {
            upsertMergeRule(rawName: item.rawName, canonicalName: newName)
        }
        item.canonicalName = newName
        try? modelContext.save()
        dismiss()
    }

    private func upsertMergeRule(rawName: String, canonicalName: String) {
        var descriptor = FetchDescriptor<MergeRule>(
            predicate: #Predicate { $0.rawName == rawName }
        )
        descriptor.fetchLimit = 1
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.canonicalName = canonicalName
        } else {
            modelContext.insert(MergeRule(rawName: rawName, canonicalName: canonicalName))
        }
    }
}
