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
                        .foregroundStyle(item.confidence < 0.6 ? .orange : .primary)
                        .monospacedDigit()
                }
                if item.isDiscount {
                    LabeledContent("Type", value: "Discount")
                        .foregroundStyle(.red)
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
        .foregroundStyle(item.isDiscount ? .red : .primary)
        .navigationTitle(item.canonicalName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(isSaveDisabled)
            }
        }
    }

    private func save() {
        item.canonicalName = canonicalName.trimmingCharacters(in: .whitespaces)
        try? modelContext.save()
        dismiss()
    }
}
