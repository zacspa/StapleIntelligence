//
//  ReceiptTemplateLabelerView.swift
//  StapleIntelligence
//

import SwiftUI
import SwiftData
import UIKit

// MARK: - Root view

/// Full-screen labeling UI for creating or editing a `ReceiptLayoutTemplate`.
///
/// Renders the receipt image with every OCR bounding box overlaid as a stroked rectangle.
/// Tapping a box opens `FieldLabelPickerSheet`; labeled boxes fill with a semi-transparent
/// color and display a small label chip. Pinch-to-zoom via `MagnificationGesture`.
///
/// On Save: builds a `[TemplateField]` from labeled entries, upserts a
/// `ReceiptLayoutTemplate` in `ModelContext`, and writes the reference image to
/// `Documents/templates/<id>/page_0.jpg`.
struct ReceiptTemplateLabelerView: View {
    let ocrLines: [OCRLine]
    let receiptImages: [UIImage]
    let merchantNormalizedName: String
    var existingTemplate: ReceiptLayoutTemplate?
    var onDismiss: () -> Void

    @Environment(\.modelContext) private var modelContext

    private let lineEntries: [LineEntry]

    @State private var labeledFields: [UUID: ReceiptFieldLabel]
    @State private var templateName: String
    @State private var selectedLineID: UUID? = nil
    @State private var showingPicker = false
    @State private var zoomScale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    init(
        ocrLines: [OCRLine],
        receiptImages: [UIImage],
        merchantNormalizedName: String,
        existingTemplate: ReceiptLayoutTemplate? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.ocrLines = ocrLines
        self.receiptImages = receiptImages
        self.merchantNormalizedName = merchantNormalizedName
        self.existingTemplate = existingTemplate
        self.onDismiss = onDismiss

        let entries = ocrLines.map(LineEntry.init)
        self.lineEntries = entries

        _templateName = State(initialValue: existingTemplate?.templateName ?? "")

        // Pre-populate labels from existing template by region intersection
        var initialLabels: [UUID: ReceiptFieldLabel] = [:]
        if let template = existingTemplate {
            for entry in entries {
                guard let bbox = entry.line.boundingBox else { continue }
                for field in template.fields where field.label != .ignore {
                    if field.region.cgRect.intersects(bbox) {
                        initialLabels[entry.id] = field.label
                        break
                    }
                }
            }
        }
        _labeledFields = State(initialValue: initialLabels)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let image = receiptImages.first {
                    imageCanvas(image: image)
                } else {
                    ContentUnavailableView(
                        "No Image",
                        systemImage: "photo",
                        description: Text("No receipt image is available for labeling.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.Colors.base)
                }
                templateInfoPanel
            }
            .background(AppTheme.Colors.base)
            .navigationTitle("Teach Receipt Layout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: saveTemplate)
                        .disabled(templateName.trimmingCharacters(in: .whitespaces).isEmpty
                                  || merchantNormalizedName.isEmpty)
                }
            }
            .sheet(isPresented: $showingPicker) {
                FieldLabelPickerSheet(
                    currentLabel: selectedLineID.flatMap { labeledFields[$0] }
                ) { chosen in
                    if let id = selectedLineID {
                        if let chosen {
                            labeledFields[id] = chosen
                        } else {
                            labeledFields.removeValue(forKey: id)
                        }
                    }
                    showingPicker = false
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Image canvas

    @ViewBuilder
    private func imageCanvas(image: UIImage) -> some View {
        GeometryReader { geo in
            let imgSize = image.size
            let containerW = geo.size.width
            let containerH = geo.size.height
            let imgAspect = imgSize.width / imgSize.height
            let containerAspect = containerW / containerH
            let displayW = (imgAspect > containerAspect
                ? containerW
                : containerH * imgAspect) * zoomScale
            let displayH = (imgAspect > containerAspect
                ? containerW / imgAspect
                : containerH) * zoomScale

            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: displayW, height: displayH)

                    ForEach(lineEntries) { entry in
                        if let bbox = entry.line.boundingBox {
                            BoundingBoxOverlay(
                                displayRect: visionToDisplay(bbox, w: displayW, h: displayH),
                                label: labeledFields[entry.id],
                                isSelected: selectedLineID == entry.id
                            )
                            .onTapGesture {
                                selectedLineID = entry.id
                                HapticFeedback.impact(.light)
                                showingPicker = true
                            }
                        }
                    }
                }
                .frame(width: displayW, height: displayH)
            }
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        zoomScale = max(1.0, min(5.0, lastScale * value))
                    }
                    .onEnded { _ in
                        lastScale = zoomScale
                    }
            )
        }
    }

    // MARK: - Info panel

    private var templateInfoPanel: some View {
        Form {
            Section("Template") {
                TextField("Template name", text: $templateName)
            }

            Section("Merchant") {
                Text(merchantNormalizedName.isEmpty ? "Unknown" : merchantNormalizedName)
                    .foregroundStyle(.secondary)
            }

            if !labeledFields.isEmpty {
                let counts = Dictionary(grouping: labeledFields.values, by: { $0 })
                    .mapValues(\.count)
                    .sorted(by: { $0.key.displayName < $1.key.displayName })

                Section("Labels (\(labeledFields.count))") {
                    ForEach(counts, id: \.key) { label, count in
                        HStack {
                            Image(systemName: label.systemImage)
                                .foregroundStyle(fieldColor(label))
                                .frame(width: 20)
                            Text(label.displayName)
                            Spacer()
                            Text("×\(count)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.Colors.base)
        .frame(maxHeight: 260)
    }

    // MARK: - Save

    private func saveTemplate() {
        let name = templateName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !merchantNormalizedName.isEmpty else { return }

        var fields: [TemplateField] = []
        for (id, label) in labeledFields {
            guard let entry = lineEntries.first(where: { $0.id == id }),
                  let bbox = entry.line.boundingBox else { continue }
            fields.append(TemplateField(label: label, region: bbox, anchorText: entry.line.text))
        }

        let template: ReceiptLayoutTemplate
        if let existing = existingTemplate {
            existing.templateName = name
            existing.fields = fields
            existing.ocrLines = ocrLines
            template = existing
        } else {
            template = ReceiptLayoutTemplate(
                templateName: name,
                merchantNormalizedName: merchantNormalizedName,
                fields: fields,
                ocrLines: ocrLines
            )
            modelContext.insert(template)
        }

        // Persist reference image
        if let image = receiptImages.first,
           let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        {
            let dir = docs.appendingPathComponent("templates/\(template.id)")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let imgURL = dir.appendingPathComponent("page_0.jpg")
            if let jpeg = image.jpegData(compressionQuality: 0.85) {
                try? jpeg.write(to: imgURL)
                template.referenceImageURL = imgURL.path
            }
        }

        try? modelContext.save()
        HapticFeedback.notification(.success)
        onDismiss()
    }

    // MARK: - Coordinate helpers

    /// Converts a Vision bounding box to SwiftUI display coordinates.
    ///
    /// **Vision** uses a **bottom-left origin**: `minY = 0` at the bottom, `maxY = 1` at
    /// the top of the image. **SwiftUI** (and `CGImage`) uses a **top-left origin**: `y = 0`
    /// at the top, increasing downward.
    ///
    /// The Y-flip formula is: `displayMinY = (1 − vision.maxY) × displayHeight`.
    /// This maps the Vision box's top edge (`maxY`) to the SwiftUI box's top edge (`minY`),
    /// preserving both position and height correctly.
    ///
    /// - Parameters:
    ///   - bbox: A Vision-normalized bounding box (origin = bottom-left, range 0–1).
    ///   - w: Width of the displayed image frame in points.
    ///   - h: Height of the displayed image frame in points.
    /// - Returns: The equivalent `CGRect` in SwiftUI display coordinates.
    private func visionToDisplay(_ bbox: CGRect, w: CGFloat, h: CGFloat) -> CGRect {
        CGRect(
            x:      bbox.minX * w,
            y:      (1 - bbox.maxY) * h,   // Y-flip: Vision BL-origin → SwiftUI TL-origin
            width:  bbox.width  * w,
            height: bbox.height * h
        )
    }

    /// Returns the color associated with a field label, used for both the overlay tint
    /// and the label chip background.
    func fieldColor(_ label: ReceiptFieldLabel) -> Color {
        switch label {
        case .merchantName:  return AppTheme.Colors.accent
        case .purchaseDate:  return AppTheme.Colors.positive
        case .lineItemName:  return Color(hex: "4A9EFF")
        case .lineItemPrice: return Color(hex: "5AC8FA")
        case .subtotal:      return AppTheme.Colors.caution
        case .tax:           return Color(hex: "FF9F0A")
        case .total:         return AppTheme.Colors.positive
        case .discount:      return AppTheme.Colors.negative
        case .ignore:        return AppTheme.Colors.tertiary
        }
    }
}

// MARK: - Line entry (stable identity for ForEach)

/// Wrapper giving each `OCRLine` a stable `UUID` for ForEach and labeledFields keying.
private struct LineEntry: Identifiable {
    let id: UUID
    let line: OCRLine

    init(line: OCRLine) {
        self.id = UUID()
        self.line = line
    }
}

// MARK: - Bounding box overlay

/// A colored, tappable overlay rectangle for one OCR bounding box.
private struct BoundingBoxOverlay: View {
    let displayRect: CGRect
    let label: ReceiptFieldLabel?
    let isSelected: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(label != nil ? overlayColor.opacity(0.22) : Color.clear)
            Rectangle()
                .strokeBorder(
                    isSelected ? Color.white : (label != nil ? overlayColor : Color.white.opacity(0.4)),
                    lineWidth: isSelected ? 2.5 : 1.2
                )
            if let label {
                Text(label.displayName)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(overlayColor)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.xs))
                    .offset(y: -13)
            }
        }
        .frame(width: displayRect.width, height: displayRect.height)
        .offset(x: displayRect.minX, y: displayRect.minY)
        .contentShape(Rectangle())
    }

    private var overlayColor: Color {
        guard let label else { return .white }
        switch label {
        case .merchantName:  return AppTheme.Colors.accent
        case .purchaseDate:  return AppTheme.Colors.positive
        case .lineItemName:  return Color(hex: "4A9EFF")
        case .lineItemPrice: return Color(hex: "5AC8FA")
        case .subtotal:      return AppTheme.Colors.caution
        case .tax:           return Color(hex: "FF9F0A")
        case .total:         return AppTheme.Colors.positive
        case .discount:      return AppTheme.Colors.negative
        case .ignore:        return AppTheme.Colors.tertiary
        }
    }
}

// MARK: - Field label picker sheet

/// Bottom sheet listing all `ReceiptFieldLabel` cases for the user to choose from.
private struct FieldLabelPickerSheet: View {
    let currentLabel: ReceiptFieldLabel?
    let onPick: (ReceiptFieldLabel?) -> Void

    var body: some View {
        NavigationStack {
            List {
                if currentLabel != nil {
                    Button(role: .destructive) {
                        onPick(nil)
                    } label: {
                        Label("Clear Label", systemImage: "xmark.circle")
                    }
                }

                ForEach(ReceiptFieldLabel.allCases, id: \.self) { label in
                    Button {
                        onPick(label)
                    } label: {
                        HStack {
                            Image(systemName: label.systemImage)
                                .frame(width: 24)
                                .foregroundStyle(pickerColor(label))
                            Text(label.displayName)
                            Spacer()
                            if currentLabel == label {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(AppTheme.Colors.accent)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AppTheme.Colors.surface)
            .navigationTitle("Label this region")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    private func pickerColor(_ label: ReceiptFieldLabel) -> Color {
        switch label {
        case .merchantName:  return AppTheme.Colors.accent
        case .purchaseDate:  return AppTheme.Colors.positive
        case .lineItemName:  return Color(hex: "4A9EFF")
        case .lineItemPrice: return Color(hex: "5AC8FA")
        case .subtotal:      return AppTheme.Colors.caution
        case .tax:           return Color(hex: "FF9F0A")
        case .total:         return AppTheme.Colors.positive
        case .discount:      return AppTheme.Colors.negative
        case .ignore:        return AppTheme.Colors.tertiary
        }
    }
}
