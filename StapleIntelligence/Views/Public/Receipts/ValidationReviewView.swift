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
    case skuPricesFixed(corrections: [(sku: String, correctedPrice: Decimal)])
}

// MARK: - Root view

struct ValidationReviewView: View {
    let result: ReceiptValidationResult
    let images: [UIImage]
    var onSaveAnyway: (ParsedReceipt) -> Void
    var onRescan: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var resolvedParsed: ParsedReceipt
    @State private var currentIndex = 0
    @State private var cropCache: [Int: [UIImage?]] = [:]

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
                    cropImages: cropCache[currentIndex] ?? Array(repeating: nil, count: sorted[currentIndex].instances.count),
                    receipt: resolvedParsed,
                    onNext: { resolution in
                        if case .rescan = resolution {
                            onRescan()
                        } else {
                            apply(resolution)
                            // After mutating resolvedParsed, skip any cards whose conditions
                            // are no longer true (e.g. implausibleTaxRate after a totals fix).
                            var next = currentIndex + 1
                            while next < total && !isRelevant(sorted[next]) { next += 1 }
                            withAnimation { currentIndex = next }
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
                Button("Cancel") { dismiss() }
            }
        }
        .task {
            for (i, issue) in result.sortedIssues.enumerated() {
                guard cropCache[i] == nil, let image = images.first,
                      !issue.instances.isEmpty else { continue }
                let imgs: [UIImage?] = issue.instances.map { instance in
                    let strips = instance.bboxes.compactMap {
                        crop(CGRect(x: 0, y: $0.minY, width: 1.0, height: $0.height),
                             from: image, xPad: 0, yPad: 0.012)
                    }
                    guard !strips.isEmpty else { return nil }
                    return strips.count == 1 ? strips[0] : stackVertically(strips)
                }
                cropCache[i] = imgs
            }
        }
    }

    // MARK: - Apply resolution

    private func apply(_ resolution: CardResolution) {
        switch resolution {
        case .accepted, .rescan:
            break
        case .skuPricesFixed(let corrections):
            let correctionMap = Dictionary(uniqueKeysWithValues: corrections.map { ($0.sku, $0.correctedPrice) })
            let updatedItems = resolvedParsed.lineItems.map { item -> ParsedLineItem in
                guard let sku = item.sku, let correctedPrice = correctionMap[sku] else { return item }
                let lineTotal: Decimal
                if case .byWeight(let qty, _) = item.itemType {
                    lineTotal = Decimal(qty) * correctedPrice
                } else {
                    lineTotal = correctedPrice
                }
                return ParsedLineItem(
                    rawName: item.rawName, canonicalName: item.canonicalName,
                    itemType: item.itemType,
                    unitPrice: item.unitPrice != nil ? correctedPrice : nil,
                    lineTotal: lineTotal,
                    isDiscount: item.isDiscount,
                    confidence: item.confidence,
                    taxCode: item.taxCode, sku: item.sku, boundingBox: item.boundingBox
                )
            }
            resolvedParsed = ParsedReceipt(
                rawOcrText: resolvedParsed.rawOcrText, merchantName: resolvedParsed.merchantName,
                purchaseDate: resolvedParsed.purchaseDate, lineItems: updatedItems,
                subtotal: resolvedParsed.subtotal, tax: resolvedParsed.tax, total: resolvedParsed.total,
                parseConfidence: resolvedParsed.parseConfidence, reconciliationStatus: .unverified
            )
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

    // MARK: - Issue relevance

    // Returns false when an issue's condition is no longer satisfied given the current
    // resolvedParsed — meaning the card would be misleading and should be skipped.
    // Called after each apply() so the check runs against the already-mutated state.
    private func isRelevant(_ issue: ReceiptValidationIssue) -> Bool {
        switch issue.kind {
        case .implausibleTaxRate:
            guard let subtotal = resolvedParsed.subtotal,
                  NSDecimalNumber(decimal: subtotal).doubleValue != 0,
                  let tax = resolvedParsed.tax else { return false }
            let rate = tax / subtotal
            return rate < 0 || rate > Decimal(string: "0.20")!
        case .totalsMismatch:
            guard let subtotal = resolvedParsed.subtotal,
                  let tax = resolvedParsed.tax,
                  let total = resolvedParsed.total else { return false }
            return abs(subtotal + tax - total) > Decimal(string: "0.02")!
        case .reconciliationFailed:
            guard let subtotal = resolvedParsed.subtotal else { return false }
            let itemSum = resolvedParsed.lineItems.reduce(Decimal.zero) { $0 + $1.lineTotal }
            return abs(itemSum - subtotal) > Decimal(string: "0.02")!
        default:
            return true
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

    private func stackVertically(_ strips: [UIImage]) -> UIImage {
        let width  = strips.map(\.size.width).max() ?? 0
        let height = strips.reduce(0) { $0 + $1.size.height }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        return renderer.image { _ in
            var y: CGFloat = 0
            for strip in strips {
                strip.draw(in: CGRect(x: 0, y: y, width: strip.size.width, height: strip.size.height))
                y += strip.size.height
            }
        }
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
    /// One entry per instance (nil = no crop available for that instance). Count always equals issue.instances.count.
    let cropImages: [UIImage?]
    let receipt: ParsedReceipt
    var onNext: (CardResolution) -> Void

    @State private var merchantInput: String
    @State private var dateInput: Date
    @State private var subtotalText: String
    @State private var taxLines: [String]
    @State private var skuPriceInputs: [String]
    @State private var showingZoom = false
    @State private var instanceIndex = 0

    init(issue: ReceiptValidationIssue, cropImages: [UIImage?], receipt: ParsedReceipt,
         onNext: @escaping (CardResolution) -> Void) {
        self.issue = issue
        self.cropImages = cropImages
        self.receipt = receipt
        self.onNext = onNext
        _merchantInput = State(initialValue: receipt.merchantName ?? "")
        _dateInput = State(initialValue: receipt.purchaseDate ?? Date())
        _subtotalText = State(initialValue: receipt.subtotal.map { $0.description } ?? "")
        _taxLines = State(initialValue: [receipt.tax.map { $0.description } ?? ""])
        if case .skuPriceConflict = issue.kind {
            _skuPriceInputs = State(initialValue: Array(repeating: "", count: issue.instances.count))
        } else {
            _skuPriceInputs = State(initialValue: [])
        }
    }

    private var isLastInstance: Bool { instanceIndex >= max(cropImages.count - 1, 0) }

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

            instanceImageSection()

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
    private func instanceImageSection() -> some View {
        let count = cropImages.count
        if count > 1 {
            VStack(spacing: 4) {
                Text("\(instanceIndex + 1) of \(count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TabView(selection: $instanceIndex) {
                    ForEach(0..<count, id: \.self) { i in
                        if let img = cropImages[i] {
                            singleImageView(img).tag(i)
                        } else {
                            Color.clear.frame(maxHeight: 60).tag(i)
                        }
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .frame(maxHeight: 80)
            }
            .fullScreenCover(isPresented: $showingZoom) {
                if let img = cropImages[min(instanceIndex, count - 1)] {
                    ZoomableImageSheet(image: img)
                }
            }
        } else if let img = cropImages.first.flatMap({ $0 }) {
            singleImageView(img)
                .fullScreenCover(isPresented: $showingZoom) {
                    ZoomableImageSheet(image: img)
                }
        }
    }

    private func singleImageView(_ img: UIImage) -> some View {
        Image(uiImage: img)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: 60)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption2)
                    .padding(4)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
                    .padding(4)
            }
            .contentShape(Rectangle())
            .onTapGesture { showingZoom = true }
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
                Button(isLastInstance ? "Accept Anyway" : "Next →") {
                    if isLastInstance { onNext(.accepted) } else { instanceIndex += 1 }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
            }

        case .reconciliationFailed, .totalsMismatch:
            totalsCalculator()

        case .skuPriceConflict:
            skuPriceConflictControls()

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
                Button(isLastInstance ? "These Look Correct" : "Next →") {
                    if isLastInstance { onNext(.accepted) } else { instanceIndex += 1 }
                }
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
                Button(isLastInstance ? "Accept" : "Next →") {
                    if isLastInstance { onNext(.accepted) } else { instanceIndex += 1 }
                }
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
    private func skuPriceConflictControls() -> some View {
        let conflict = issue.instances.indices.contains(instanceIndex)
            ? issue.instances[instanceIndex].skuConflict : nil
        let inputBinding = Binding<String>(
            get: { skuPriceInputs.indices.contains(instanceIndex) ? skuPriceInputs[instanceIndex] : "" },
            set: { if skuPriceInputs.indices.contains(instanceIndex) { skuPriceInputs[instanceIndex] = $0 } }
        )
        let currentInput = skuPriceInputs.indices.contains(instanceIndex) ? skuPriceInputs[instanceIndex] : ""
        let parsedInput = Decimal(string: currentInput.replacingOccurrences(of: ",", with: "."))

        VStack(alignment: .leading, spacing: 12) {
            if let conflict {
                VStack(alignment: .leading, spacing: 8) {
                    Text("SKU \(conflict.sku)")
                        .font(.subheadline.weight(.semibold))

                    HStack(spacing: 8) {
                        Text("Conflicting prices:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(0..<conflict.prices.count, id: \.self) { i in
                            Button {
                                if skuPriceInputs.indices.contains(instanceIndex) {
                                    skuPriceInputs[instanceIndex] = conflict.prices[i].description
                                }
                            } label: {
                                Text(conflict.prices[i], format: .currency(code: "USD"))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    HStack {
                        Text("Correct price")
                            .font(.subheadline)
                        Spacer()
                        TextField("0.00", text: inputBinding)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.decimalPad)
                            .frame(width: 100)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }

            Button(isLastInstance ? "Apply & Continue" : "Next →") {
                if isLastInstance {
                    let corrections: [(sku: String, correctedPrice: Decimal)] = issue.instances
                        .enumerated()
                        .compactMap { (i, inst) in
                            guard let c = inst.skuConflict,
                                  skuPriceInputs.indices.contains(i),
                                  let price = Decimal(string: skuPriceInputs[i].replacingOccurrences(of: ",", with: "."))
                            else { return nil }
                            return (sku: c.sku, correctedPrice: price)
                        }
                    onNext(.skuPricesFixed(corrections: corrections))
                } else {
                    instanceIndex += 1
                }
            }
            .disabled(parsedInput == nil)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)

            Button("Rescan") { onNext(.rescan) }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
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

// MARK: - Full-screen zoom sheet

private struct ZoomableImageSheet: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            ZoomableImageView(image: image)
                .ignoresSafeArea()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color(.systemGray2).opacity(0.7))
            }
            .padding()
        }
    }
}

// UIScrollView-backed image view with native pinch-to-zoom and double-tap to zoom/reset.
private struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage

    // UIScrollView subclass that sizes the image view to fill its frame during layout.
    // Using layoutSubviews instead of updateUIView avoids resizing the frame while the
    // user is actively zoomed in.
    final class ZoomScrollView: UIScrollView {
        weak var imageView: UIImageView?
        override func layoutSubviews() {
            super.layoutSubviews()
            guard let iv = imageView, zoomScale == minimumZoomScale else { return }
            iv.frame = bounds
            contentSize = bounds.size
        }
    }

    func makeUIView(context: Context) -> ZoomScrollView {
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit

        let scrollView = ZoomScrollView()
        scrollView.imageView = imageView
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 5.0
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .clear
        scrollView.addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        context.coordinator.imageView = imageView
        return scrollView
    }

    func updateUIView(_ uiView: ZoomScrollView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard let iv = imageView else { return }
            let xOff = max((scrollView.bounds.width  - scrollView.contentSize.width)  / 2, 0)
            let yOff = max((scrollView.bounds.height - scrollView.contentSize.height) / 2, 0)
            iv.center = CGPoint(
                x: scrollView.contentSize.width  / 2 + xOff,
                y: scrollView.contentSize.height / 2 + yOff)
        }

        @objc func handleDoubleTap(_ sender: UITapGestureRecognizer) {
            guard let scrollView = sender.view as? UIScrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                let pt = sender.location(in: imageView)
                let w = scrollView.bounds.width  / 2.5
                let h = scrollView.bounds.height / 2.5
                scrollView.zoom(to: CGRect(x: pt.x - w / 2, y: pt.y - h / 2, width: w, height: h),
                                animated: true)
            }
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
