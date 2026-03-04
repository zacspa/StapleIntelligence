//
//  ValidationReviewView.swift
//  StapleIntelligence
//
//  Created by Zack Sparks on 3/3/26.
//

import SwiftUI
import UIKit

// MARK: - Card resolution

private enum CardResolution {
    case accepted
    case rescan
    case merchantUpdated(String)
    case dateUpdated(Date)
    case totalsUpdated(subtotal: Decimal?, tax: Decimal?, total: Decimal?)
}

// MARK: - Root view

struct ValidationReviewView: View {
    let result: ReceiptValidationResult
    let images: [UIImage]
    var onSaveAnyway: (ParsedReceipt) -> Void
    var onRescan: () -> Void

    @State private var resolvedParsed: ParsedReceipt
    @State private var currentIndex = 0
    @State private var cropCache: [Int: UIImage] = [:]

    private var sorted: [ReceiptValidationIssue] { result.sortedIssues }
    private var total: Int { sorted.count }

    init(result: ReceiptValidationResult, parsed: ParsedReceipt, images: [UIImage],
         onSaveAnyway: @escaping (ParsedReceipt) -> Void, onRescan: @escaping () -> Void) {
        self.result = result
        self.images = images
        self.onSaveAnyway = onSaveAnyway
        self.onRescan = onRescan
        _resolvedParsed = State(initialValue: parsed)
    }

    var body: some View {
        VStack(spacing: 0) {
            ProgressBar(current: currentIndex, total: total)
                .padding(.horizontal)
                .padding(.top, 8)

            if currentIndex < total {
                Text("Issue \(currentIndex + 1) of \(total)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                IssueCardView(
                    issue: sorted[currentIndex],
                    cropImage: cropCache[currentIndex],
                    receipt: resolvedParsed,
                    onNext: { resolution in
                        if case .rescan = resolution {
                            onRescan()
                        } else {
                            apply(resolution)
                            withAnimation { currentIndex += 1 }
                        }
                    }
                )
                .padding()
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                ))
                .id(currentIndex)
            } else {
                FinalCardView(
                    result: result,
                    onSaveAnyway: { onSaveAnyway(resolvedParsed) },
                    onRescan: onRescan
                )
                .padding()
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                ))
            }

            Spacer()
        }
        .navigationTitle("Review Issues")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back") {}
                    .hidden()
            }
        }
        .task {
            for (i, issue) in result.sortedIssues.enumerated() {
                guard cropCache[i] == nil else { continue }
                if let box = issue.associatedBoundingBox, let image = images.first {
                    cropCache[i] = crop(box, from: image, xPad: 0.02, yPad: 0.012)
                }
            }
        }
    }

    // MARK: - Apply resolution

    private func apply(_ resolution: CardResolution) {
        switch resolution {
        case .accepted, .rescan:
            break
        case .merchantUpdated(let name):
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            resolvedParsed = ParsedReceipt(
                rawOcrText: resolvedParsed.rawOcrText,
                merchantName: trimmed.isEmpty ? nil : trimmed,
                purchaseDate: resolvedParsed.purchaseDate,
                lineItems: resolvedParsed.lineItems,
                subtotal: resolvedParsed.subtotal,
                tax: resolvedParsed.tax,
                total: resolvedParsed.total,
                parseConfidence: resolvedParsed.parseConfidence,
                reconciliationStatus: resolvedParsed.reconciliationStatus
            )
        case .dateUpdated(let date):
            resolvedParsed = ParsedReceipt(
                rawOcrText: resolvedParsed.rawOcrText,
                merchantName: resolvedParsed.merchantName,
                purchaseDate: date,
                lineItems: resolvedParsed.lineItems,
                subtotal: resolvedParsed.subtotal,
                tax: resolvedParsed.tax,
                total: resolvedParsed.total,
                parseConfidence: resolvedParsed.parseConfidence,
                reconciliationStatus: resolvedParsed.reconciliationStatus
            )
        case .totalsUpdated(let subtotal, let tax, let total):
            resolvedParsed = ParsedReceipt(
                rawOcrText: resolvedParsed.rawOcrText,
                merchantName: resolvedParsed.merchantName,
                purchaseDate: resolvedParsed.purchaseDate,
                lineItems: resolvedParsed.lineItems,
                subtotal: subtotal,
                tax: tax,
                total: total,
                parseConfidence: resolvedParsed.parseConfidence,
                reconciliationStatus: .unverified
            )
        }
    }

    // MARK: - Crop helper

    private func crop(_ box: CGRect, from image: UIImage, xPad: CGFloat, yPad: CGFloat) -> UIImage? {
        // Vision uses bottom-left origin; CGImage uses top-left origin.
        guard let cgImage = image.cgImage else { return nil }
        let w = CGFloat(cgImage.width), h = CGFloat(cgImage.height)
        let padded = box
            .insetBy(dx: -xPad, dy: -yPad)            // negative inset = expand
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        let rect = CGRect(
            x:      padded.minX * w,
            y:      (1 - padded.maxY) * h,            // flip Y: Vision bottom-left → CGImage top-left
            width:  padded.width * w,
            height: padded.height * h
        )
        guard let cropped = cgImage.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }
}

// MARK: - Progress bar

private struct ProgressBar: View {
    let current: Int
    let total: Int

    var progress: Double {
        total == 0 ? 1.0 : Double(current) / Double(total)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(.systemFill))
                    .frame(height: 4)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(width: geo.size.width * progress, height: 4)
                    .animation(.easeInOut(duration: 0.25), value: progress)
            }
        }
        .frame(height: 4)
    }
}

// MARK: - Issue card

private struct IssueCardView: View {
    let issue: ReceiptValidationIssue
    let cropImage: UIImage?
    let receipt: ParsedReceipt
    var onNext: (CardResolution) -> Void

    @State private var merchantInput: String
    @State private var dateInput: Date
    @State private var subtotalText: String
    @State private var taxLines: [String]

    init(issue: ReceiptValidationIssue, cropImage: UIImage?, receipt: ParsedReceipt,
         onNext: @escaping (CardResolution) -> Void) {
        self.issue = issue
        self.cropImage = cropImage
        self.receipt = receipt
        self.onNext = onNext
        _merchantInput = State(initialValue: receipt.merchantName ?? "")
        _dateInput = State(initialValue: receipt.purchaseDate ?? Date())
        _subtotalText = State(initialValue: receipt.subtotal.map { $0.description } ?? "")
        _taxLines = State(initialValue: [receipt.tax.map { $0.description } ?? ""])
    }

    private var iconColor: Color {
        switch issue.severity {
        case .info:     return .blue
        case .warning:  return .orange
        case .error:    return .red
        case .critical: return .red
        }
    }

    // Computed for totals calculator
    private var parsedSubtotal: Decimal? {
        Decimal(string: subtotalText.replacingOccurrences(of: ",", with: "."))
    }
    private var parsedTaxLines: [Decimal] {
        taxLines.compactMap { Decimal(string: $0.replacingOccurrences(of: ",", with: ".")) }
    }
    private var totalTax: Decimal { parsedTaxLines.reduce(.zero, +) }
    private var computedTotal: Decimal? { parsedSubtotal.map { $0 + totalTax } }
    private var itemsSum: Decimal { receipt.lineItems.reduce(.zero) { $0 + $1.lineTotal } }

    private var taxRateText: String {
        guard let subtotal = receipt.subtotal, let tax = receipt.tax,
              NSDecimalNumber(decimal: subtotal).doubleValue != 0 else { return "—" }
        let rate = NSDecimalNumber(decimal: tax).doubleValue /
                   NSDecimalNumber(decimal: subtotal).doubleValue * 100
        return String(format: "%.1f%%", rate)
    }

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: issue.iconName)
                .font(.system(size: 48))
                .foregroundStyle(iconColor)
                .padding(.top, 8)

            if let crop = cropImage {
                Image(uiImage: crop)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 60)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            VStack(spacing: 8) {
                Text(issue.title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(issue.detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            resolutionControls()
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func resolutionControls() -> some View {
        switch issue.kind {
        case .noItemsParsed, .globalConfidenceCritical:
            VStack(spacing: 12) {
                Button("Rescan Receipt") { onNext(.rescan) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                Button("Accept Anyway") { onNext(.accepted) }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
            }

        case .reconciliationFailed, .totalsMismatch:
            totalsCalculator()

        case .missingMerchant:
            VStack(spacing: 12) {
                TextField("Store name", text: $merchantInput)
                    .textFieldStyle(.roundedBorder)
                Button("Apply & Continue") { onNext(.merchantUpdated(merchantInput)) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                Button("Skip") { onNext(.accepted) }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
            }

        case .missingDate:
            VStack(spacing: 12) {
                DatePicker("Purchase date", selection: $dateInput, displayedComponents: .date)
                    .labelsHidden()
                Button("Apply & Continue") { onNext(.dateUpdated(dateInput)) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                Button("Skip") { onNext(.accepted) }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
            }

        case .implausibleTaxRate:
            VStack(spacing: 12) {
                Text("Detected rate: \(taxRateText)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Accept Rate") { onNext(.accepted) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                Button("Rescan") { onNext(.rescan) }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
            }

        case .duplicateItems:
            VStack(spacing: 12) {
                Button("These Look Correct") { onNext(.accepted) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                Button("Rescan") { onNext(.rescan) }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
            }

        case .lowConfidenceItems, .itemsWithZeroPrice, .itemNamesAllDigits,
             .itemNamesTooShort, .itemNamesNonAlpha:
            VStack(spacing: 12) {
                Button("Accept") { onNext(.accepted) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                Button("Rescan") { onNext(.rescan) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func totalsCalculator() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Items sum")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(itemsSum, format: .currency(code: "USD"))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.subheadline)

            Divider()

            HStack {
                Text("Subtotal")
                    .font(.subheadline)
                Spacer()
                TextField("0.00", text: $subtotalText)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)
                    .frame(width: 100)
                    .multilineTextAlignment(.trailing)
            }

            ForEach(taxLines.indices, id: \.self) { i in
                HStack {
                    Text(taxLines.count > 1 ? "Tax \(i + 1)" : "Tax")
                        .font(.subheadline)
                    Spacer()
                    TextField("0.00", text: $taxLines[i])
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                        .frame(width: 100)
                        .multilineTextAlignment(.trailing)
                    if taxLines.count > 1 {
                        Button {
                            taxLines.remove(at: i)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Button {
                taxLines.append("")
            } label: {
                Label("Add Tax", systemImage: "plus.circle")
                    .font(.subheadline)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)

            Divider()

            HStack {
                Text("Total")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let total = computedTotal {
                    Text(total, format: .currency(code: "USD"))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                } else {
                    Text("—")
                        .foregroundStyle(.secondary)
                }
            }

            Button("Apply & Continue") {
                if let total = computedTotal {
                    onNext(.totalsUpdated(subtotal: parsedSubtotal, tax: totalTax, total: total))
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .disabled(computedTotal == nil)

            Button("Rescan Receipt") { onNext(.rescan) }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Final card

private struct FinalCardView: View {
    let result: ReceiptValidationResult
    var onSaveAnyway: () -> Void
    var onRescan: () -> Void

    private var summaryIcon: String {
        result.preferRescan ? "arrow.counterclockwise.camera" : "checkmark.circle"
    }

    private var summaryColor: Color {
        result.preferRescan ? .orange : .green
    }

    private var summaryMessage: String {
        if result.preferRescan {
            return "There are significant quality issues with this receipt. We recommend rescanning for better results."
        } else {
            return "You've reviewed all issues. You can save the receipt as-is or rescan for a cleaner result."
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: summaryIcon)
                .font(.system(size: 48))
                .foregroundStyle(summaryColor)
                .padding(.top, 8)

            VStack(spacing: 8) {
                Text("Review Complete")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(summaryMessage)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                if result.preferRescan {
                    Button("Rescan Receipt", action: onRescan)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)

                    Button("Save Anyway", action: onSaveAnyway)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                } else {
                    Button("Save Anyway", action: onSaveAnyway)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)

                    Button("Rescan Receipt", action: onRescan)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
