//
//  ReceiptEditView.swift
//  StapleIntelligence
//
//  Created by Zack Sparks on 3/2/26.
//

import SwiftUI
import SwiftData
import OSLog

/// Pushed onto the NavigationStack from ReceiptsView — edits a persisted Receipt in-place.
struct ReceiptEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let receipt: Receipt

    @State private var merchantName: String
    @State private var purchaseDate: Date
    @FocusState private var merchantFieldFocused: Bool

    init(receipt: Receipt) {
        self.receipt = receipt
        _merchantName = State(initialValue: receipt.merchant?.displayName ?? "")
        _purchaseDate = State(initialValue: receipt.purchaseDate ?? Date())
    }

    var body: some View {
        let _ = ScanningLog.edit.debug("ReceiptEditView body — \(receipt.lineItems.count, privacy: .public) items @ \(ts(), privacy: .public)")
        Form {
            Section("Merchant") {
                TextField("Store name", text: $merchantName)
                    .focused($merchantFieldFocused)
                    .onChange(of: merchantFieldFocused) { _, focused in
                        guard focused else { return }
                        ScanningLog.edit.log("merchant field tap — \(ts(), privacy: .public)")
                    }
                    .onChange(of: merchantName) { _, new in
                        ScanningLog.edit.log("merchant field edit — \(ts(), privacy: .public), len: \(new.count, privacy: .public)")
                    }
            }

            Section("Date") {
                DatePicker("Purchase date", selection: $purchaseDate, displayedComponents: .date)
                    .labelsHidden()
            }

            Section("Items (\(receipt.lineItems.count))") {
                ForEach(receipt.lineItems.sorted(by: { $0.sortOrder < $1.sortOrder }), id: \.id) { item in
                    NavigationLink(value: item.id) {
                        LineItemSummaryRow(item: item)
                    }
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
        .navigationDestination(for: UUID.self) { id in
            if let item = receipt.lineItems.first(where: { $0.id == id }) {
                ItemDetailView(item: item, receipt: receipt)
            }
        }
    }

    private func ts() -> String {
        let d = Date()
        let ms = Int(d.timeIntervalSince1970 * 1000) % 1000
        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: d)
        return String(format: "%02d:%02d:%02d.%03d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0, ms)
    }

    private func save() {
        let signposter = OSSignposter(subsystem: ScanningLog.subsystem, category: "edit")
        let spState = signposter.beginInterval("merchant_name_save")
        let wallStart = Date()

        let trimmed = merchantName.trimmingCharacters(in: .whitespaces)
        ScanningLog.edit.debug(
            "merchant_name_save — nameSet: \(trimmed.isEmpty ? "false" : "true", privacy: .public), items: \(receipt.lineItems.count, privacy: .public)"
        )

        if trimmed.isEmpty {
            receipt.merchant = nil
        } else if let merchant = receipt.merchant {
            merchant.displayName = trimmed
            merchant.normalizedName = trimmed.uppercased().trimmingCharacters(in: .whitespaces)
        } else {
            let normalized = trimmed.uppercased().trimmingCharacters(in: .whitespaces)
            let fetchStart = Date()
            var descriptor = FetchDescriptor<Merchant>(
                predicate: #Predicate { $0.normalizedName == normalized }
            )
            descriptor.fetchLimit = 1
            if let existing = try? modelContext.fetch(descriptor).first {
                ScanningLog.edit.debug("merchant fetch — hit, ms: \(Int(Date().timeIntervalSince(fetchStart) * 1000), privacy: .public)")
                receipt.merchant = existing
            } else {
                ScanningLog.edit.debug("merchant fetch — miss, ms: \(Int(Date().timeIntervalSince(fetchStart) * 1000), privacy: .public)")
                let merchant = Merchant(displayName: trimmed, normalizedName: normalized)
                modelContext.insert(merchant)
                receipt.merchant = merchant
            }
        }

        receipt.purchaseDate = purchaseDate

        let dbStart = Date()
        try? modelContext.save()
        ScanningLog.edit.log(
            "merchant_name_save — db ms: \(Int(Date().timeIntervalSince(dbStart) * 1000), privacy: .public), total ms: \(Int(Date().timeIntervalSince(wallStart) * 1000), privacy: .public)"
        )

        signposter.endInterval("merchant_name_save", spState)
        dismiss()
    }
}

// MARK: - Item summary row

private struct LineItemSummaryRow: View {
    let item: LineItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.canonicalName)
                    .foregroundStyle(item.isDiscount ? .red : .primary)
                if let qty = item.quantity, let unit = item.unit {
                    Text(weightLabel(qty: qty, unit: unit, unitPrice: item.unitPrice))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(item.lineTotal, format: .currency(code: "USD"))
                .foregroundStyle(item.isDiscount ? .red : .primary)
                .monospacedDigit()
        }
    }

    private func weightLabel(qty: Double, unit: String, unitPrice: Decimal?) -> String {
        let qtyStr = String(format: "%.2f", qty)
        guard let up = unitPrice else { return "\(qtyStr) \(unit)" }
        return "\(qtyStr) \(unit) × \(up.formatted(.currency(code: "USD")))/\(unit)"
    }
}
