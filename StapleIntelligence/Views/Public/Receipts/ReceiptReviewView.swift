//
//  ReceiptReviewView.swift
//  StapleIntelligence
//
//  Created by Zack Sparks on 3/2/26.
//

import SwiftUI
import UIKit
internal import os

/// Sheet shown after OCR+parse, letting the user review and confirm the parsed receipt
/// before it is persisted.
///
/// On "Save": runs `ReceiptValidator`. If `requiresReview`, pushes `ValidationReviewView`
/// via a `navigationDestination`; otherwise calls `onSave` directly with a haptic.
/// The view is embedded inside its own `NavigationStack` so the validation destination
/// can be pushed without affecting the parent stack.
struct ReceiptReviewView: View {
    let parsed: ParsedReceipt
    let ocrLines: [OCRLine]
    let images: [UIImage]
    var onSave: (ParsedReceipt) -> Void   // synchronous — caller wraps in Task to avoid
    var onCancel: () -> Void              // @in_guaranteed borrow through async thunk chain

    @State private var merchantName: String
    @State private var purchaseDate: Date
    @State private var isSaving = false
    @State private var showingValidation = false
    @State private var showingLabeler = false
    @State private var validationResult: ReceiptValidationResult? = nil
    @State private var editedForSave: ParsedReceipt? = nil
    private let validator = ReceiptValidator()

    private var normalizedMerchantName: String {
        ReceiptParser.canonicalize(merchantName)
    }

    init(parsed: ParsedReceipt, ocrLines: [OCRLine] = [], images: [UIImage], onSave: @escaping (ParsedReceipt) -> Void, onCancel: @escaping () -> Void) {
        self.parsed = parsed
        self.ocrLines = ocrLines
        self.images = images
        self.onSave = onSave
        self.onCancel = onCancel
        _merchantName = State(initialValue: parsed.merchantName ?? "")
        _purchaseDate = State(initialValue: parsed.purchaseDate ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                if parsed.parseConfidence < 0.55 {
                    Section {
                        HStack(spacing: AppTheme.Spacing.sm) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(AppTheme.Colors.caution)
                            Text("Low confidence parse")
                                .font(.subheadline)
                            Spacer()
                            Button("Teach") { showingLabeler = true }
                                .font(.subheadline.bold())
                                .foregroundStyle(AppTheme.Colors.accent)
                        }
                    }
                }

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
                            LabeledContent("Subtotal") {
                                Text(subtotal, format: .currency(code: "USD")).monospacedDigit()
                            }
                        }
                        if let tax = parsed.tax {
                            LabeledContent("Tax") {
                                Text(tax, format: .currency(code: "USD")).monospacedDigit()
                            }
                        }
                        if let total = parsed.total {
                            LabeledContent("Total") {
                                Text(total, format: .currency(code: "USD")).monospacedDigit()
                            }
                            .bold()
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.Colors.base)
            .navigationTitle("Review Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationDestination(isPresented: $showingValidation) {
                if let result = validationResult, let edited = editedForSave {
                    ValidationReviewView(
                        result: result,
                        parsed: edited,
                        images: images,
                        onSaveAnyway: { resolvedReceipt in
                            showingValidation = false
                            isSaving = true
                            onSave(resolvedReceipt)
                        },
                        onRescan: {
                            showingValidation = false
                            onCancel()
                        }
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        ScanningLog.template.log("Teach Layout tapped — merchant: \(normalizedMerchantName, privacy: .public), ocrLines: \(ocrLines.count, privacy: .public), images: \(images.count, privacy: .public)")
                        showingLabeler = true
                    } label: {
                        Label("Teach Layout", systemImage: "pencil.and.list.clipboard")
                    }
                    .foregroundStyle(AppTheme.Colors.accent)
                }
            }
            .fullScreenCover(isPresented: $showingLabeler) {
                let _ = ScanningLog.template.log("Labeler cover presented — ocrLines: \(ocrLines.count, privacy: .public), images: \(images.count, privacy: .public)")
                ReceiptTemplateLabelerView(
                    ocrLines: ocrLines,
                    receiptImages: images,
                    merchantNormalizedName: normalizedMerchantName,
                    onDismiss: { showingLabeler = false }
                )
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
        let result = validator.validate(edited)
        ScanningLog.validation.log("save tapped — requiresReview: \(result.requiresReview, privacy: .public), preferRescan: \(result.preferRescan, privacy: .public), totalWeight: \(result.totalWeight, privacy: .public)")
        if result.requiresReview {
            ScanningLog.validation.log("pushing ValidationReviewView")
            validationResult = result
            editedForSave = edited
            showingValidation = true
        } else {
            ScanningLog.validation.log("no review needed — saving directly")
            isSaving = true
            HapticFeedback.notification(.success)
            onSave(edited)
        }
    }
}

// MARK: - Line item row

private struct LineItemRow: View {
    let item: ParsedLineItem

    private func weightLabel(qty: Double, unit: WeightUnit, unitPrice: Decimal?) -> String {
        let qtyStr = String(format: "%.2f", qty)
        guard let up = unitPrice else { return "\(qtyStr) \(unit.rawValue)" }
        return "\(qtyStr) \(unit.rawValue) × \(up.formatted(.currency(code: "USD")))/\(unit.rawValue)"
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.canonicalName)
                    .foregroundStyle(item.isDiscount ? AppTheme.Colors.negative : .primary)
                if case .byWeight(let qty, let unit) = item.itemType {
                    Text(weightLabel(qty: qty, unit: unit, unitPrice: item.unitPrice))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if item.confidence < 0.6 {
                    Text("(low confidence)")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.Colors.caution)
                }
            }
            Spacer()
            Text(item.lineTotal, format: .currency(code: "USD"))
                .foregroundStyle(item.isDiscount ? AppTheme.Colors.negative : .primary)
                .monospacedDigit()
        }
    }
}
