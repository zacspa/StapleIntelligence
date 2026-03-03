//
//  ReceiptReviewView.swift
//  StapleIntelligence
//
//  Created by Zack Sparks on 3/2/26.
//

import SwiftUI

struct ReceiptReviewView: View {
    let parsed: ParsedReceipt
    var onSave: (ParsedReceipt) -> Void   // synchronous — caller wraps in Task to avoid
    var onCancel: () -> Void              // @in_guaranteed borrow through async thunk chain

    @State private var merchantName: String
    @State private var purchaseDate: Date
    @State private var isSaving = false

    init(parsed: ParsedReceipt, onSave: @escaping (ParsedReceipt) -> Void, onCancel: @escaping () -> Void) {
        self.parsed = parsed
        self.onSave = onSave
        self.onCancel = onCancel
        _merchantName = State(initialValue: parsed.merchantName ?? "")
        _purchaseDate = State(initialValue: parsed.purchaseDate ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Merchant") {
                    TextField("Store name", text: $merchantName)
                }

                Section("Date") {
                    DatePicker("Purchase date", selection: $purchaseDate, displayedComponents: .date)
                        .labelsHidden()
                }

                Section("Items (\(parsed.lineItems.count))") {
                    ForEach(Array(parsed.lineItems.enumerated()), id: \.offset) { _, item in
                        LineItemRow(item: item)
                    }
                }

                if parsed.subtotal != nil || parsed.tax != nil || parsed.total != nil {
                    Section("Totals") {
                        if let subtotal = parsed.subtotal {
                            LabeledContent("Subtotal", value: subtotal, format: .currency(code: "USD"))
                        }
                        if let tax = parsed.tax {
                            LabeledContent("Tax", value: tax, format: .currency(code: "USD"))
                        }
                        if let total = parsed.total {
                            LabeledContent("Total", value: total, format: .currency(code: "USD"))
                                .bold()
                        }
                    }
                }
            }
            .navigationTitle("Review Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(isSaving)
                }
            }
            .overlay {
                if isSaving {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.ultraThinMaterial)
                }
            }
        }
    }

    private func save() {
        isSaving = true
        let trimmedMerchant = merchantName.trimmingCharacters(in: .whitespaces)
        let edited = ParsedReceipt(
            rawOcrText: parsed.rawOcrText,
            merchantName: trimmedMerchant.isEmpty ? nil : trimmedMerchant,
            purchaseDate: purchaseDate,
            lineItems: parsed.lineItems,
            subtotal: parsed.subtotal,
            tax: parsed.tax,
            total: parsed.total,
            parseConfidence: parsed.parseConfidence,
            reconciliationStatus: parsed.reconciliationStatus
        )
        // onSave is synchronous. ReceiptsView wraps handleSave in a Task, which captures
        // `edited` by copying it into the Task's heap closure before any suspension.
        // This gives the array buffer a proper strong reference — no @in_guaranteed borrow.
        onSave(edited)
        // isSaving stays true; spinner is visible until ReceiptsView sets parsedReceipt = nil.
    }
}

// MARK: - Line item row

private struct LineItemRow: View {
    let item: ParsedLineItem

    private func weightLabel(qty: Double, unit: String, unitPrice: Decimal?) -> String {
        let qtyStr = String(format: "%.2f", qty)
        guard let up = unitPrice else { return "\(qtyStr) \(unit)" }
        return "\(qtyStr) \(unit) × \(up.formatted(.currency(code: "USD")))/\(unit)"
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.canonicalName)
                    .foregroundStyle(item.isDiscount ? .red : .primary)
                if let qty = item.quantity, let unit = item.unit {
                    Text(weightLabel(qty: qty, unit: unit, unitPrice: item.unitPrice))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if item.confidence < 0.6 {
                    Text("(low confidence)")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            Text(item.lineTotal, format: .currency(code: "USD"))
                .foregroundStyle(item.isDiscount ? .red : .primary)
                .monospacedDigit()
        }
    }
}
