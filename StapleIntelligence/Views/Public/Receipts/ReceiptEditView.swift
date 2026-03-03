//
//  ReceiptEditView.swift
//  StapleIntelligence
//
//  Created by Zack Sparks on 3/2/26.
//

import SwiftUI
import SwiftData

/// Pushed onto the NavigationStack from ReceiptsView — edits a persisted Receipt in-place.
struct ReceiptEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let receipt: Receipt

    @State private var merchantName: String
    @State private var purchaseDate: Date

    init(receipt: Receipt) {
        self.receipt = receipt
        _merchantName = State(initialValue: receipt.merchant?.displayName ?? "")
        _purchaseDate = State(initialValue: receipt.purchaseDate ?? Date())
    }

    var body: some View {
        Form {
            Section("Merchant") {
                TextField("Store name", text: $merchantName)
            }

            Section("Date") {
                DatePicker("Purchase date", selection: $purchaseDate, displayedComponents: .date)
                    .labelsHidden()
            }

            Section("Items (\(receipt.lineItems.count))") {
                ForEach(receipt.lineItems, id: \.id) { item in
                    LineItemEditRow(item: item)
                }
            }

            if receipt.subtotal != nil || receipt.tax != nil || receipt.total != nil {
                Section("Totals") {
                    if let subtotal = receipt.subtotal {
                        LabeledContent("Subtotal", value: subtotal, format: .currency(code: "USD"))
                    }
                    if let tax = receipt.tax {
                        LabeledContent("Tax", value: tax, format: .currency(code: "USD"))
                    }
                    if let total = receipt.total {
                        LabeledContent("Total", value: total, format: .currency(code: "USD"))
                            .bold()
                    }
                }
            }
        }
        .navigationTitle("Edit Receipt")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { save() }
            }
        }
    }

    private func save() {
        let trimmed = merchantName.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            receipt.merchant = nil
        } else if let merchant = receipt.merchant {
            merchant.displayName = trimmed
            merchant.normalizedName = trimmed.uppercased().trimmingCharacters(in: .whitespaces)
        } else {
            let normalized = trimmed.uppercased().trimmingCharacters(in: .whitespaces)
            var descriptor = FetchDescriptor<Merchant>(
                predicate: #Predicate { $0.normalizedName == normalized }
            )
            descriptor.fetchLimit = 1
            if let existing = try? modelContext.fetch(descriptor).first {
                receipt.merchant = existing
            } else {
                let merchant = Merchant(displayName: trimmed, normalizedName: normalized)
                modelContext.insert(merchant)
                receipt.merchant = merchant
            }
        }
        receipt.purchaseDate = purchaseDate
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Item edit row

private struct LineItemEditRow: View {
    let item: LineItem

    @State private var name: String

    init(item: LineItem) {
        self.item = item
        _name = State(initialValue: item.canonicalName)
    }

    var body: some View {
        HStack {
            TextField("Item name", text: $name)
                .foregroundStyle(item.isDiscount ? .red : .primary)
                .onChange(of: name) { _, new in
                    item.canonicalName = new
                }
            Spacer()
            Text(item.lineTotal, format: .currency(code: "USD"))
                .foregroundStyle(item.isDiscount ? .red : .primary)
                .monospacedDigit()
        }
    }
}
