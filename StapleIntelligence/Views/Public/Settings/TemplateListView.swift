//
//  TemplateListView.swift
//  StapleIntelligence
//

import SwiftUI
import SwiftData
import UIKit

/// Lists all persisted `ReceiptLayoutTemplate` records.
///
/// Displayed as a navigation destination within `SettingsView`.
/// Swipe-to-delete removes the template and its reference image.
/// Tapping a row opens `ReceiptTemplateLabelerView` in edit mode (via `fullScreenCover`).
struct TemplateListView: View {
    @Query(sort: \ReceiptLayoutTemplate.createdAt, order: .reverse)
    private var templates: [ReceiptLayoutTemplate]

    @Environment(\.modelContext) private var modelContext

    @State private var templateToEdit: ReceiptLayoutTemplate? = nil
    @State private var templateToDelete: ReceiptLayoutTemplate? = nil

    var body: some View {
        Group {
            if templates.isEmpty {
                ContentUnavailableView(
                    "No Templates",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Tap \"Teach Layout\" while reviewing a receipt to create a template.")
                )
            } else {
                List {
                    ForEach(templates) { template in
                        TemplateRow(template: template)
                            .contentShape(Rectangle())
                            .onTapGesture { templateToEdit = template }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    templateToDelete = template
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(AppTheme.Colors.base)
                .animation(AppTheme.Animation.springList, value: templates.count)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.Colors.base)
        .navigationTitle("Receipt Templates")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .alert("Delete Template?", isPresented: Binding(
            get: { templateToDelete != nil },
            set: { if !$0 { templateToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let t = templateToDelete {
                    deleteTemplate(t)
                    templateToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) { templateToDelete = nil }
        } message: {
            if let t = templateToDelete {
                Text(""\(t.templateName)" will be permanently deleted.")
            }
        }
        .fullScreenCover(item: $templateToEdit) { template in
            TemplateEditWrapper(template: template) {
                templateToEdit = nil
            }
        }
    }

    private func deleteTemplate(_ template: ReceiptLayoutTemplate) {
        // Remove reference image directory
        if let path = template.referenceImageURL {
            let dir = URL(fileURLWithPath: path).deletingLastPathComponent()
            try? FileManager.default.removeItem(at: dir)
        }
        modelContext.delete(template)
    }
}

// MARK: - Template row

private struct TemplateRow: View {
    let template: ReceiptLayoutTemplate

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(template.templateName)
                    .font(.body)
                Text(template.merchantNormalizedName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("Used \(template.useCount)×")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if let last = template.lastUsedAt {
                    Text(Self.dateFormatter.string(from: last))
                        .font(.caption2)
                        .foregroundStyle(AppTheme.Colors.tertiary)
                }
            }
        }
        .listRowBackground(AppTheme.Colors.surface)
    }
}

// MARK: - Edit wrapper

/// Loads the reference image from disk and presents the labeler in edit mode.
private struct TemplateEditWrapper: View {
    let template: ReceiptLayoutTemplate
    let onDismiss: () -> Void

    @State private var referenceImage: UIImage? = nil
    @State private var didLoad = false

    var body: some View {
        Group {
            if didLoad {
                ReceiptTemplateLabelerView(
                    ocrLines: template.ocrLines,
                    receiptImages: referenceImage.map { [$0] } ?? [],
                    merchantNormalizedName: template.merchantNormalizedName,
                    existingTemplate: template,
                    onDismiss: onDismiss
                )
            } else {
                ZStack {
                    AppTheme.Colors.base.ignoresSafeArea()
                    ProgressView()
                }
            }
        }
        .task {
            if let path = template.referenceImageURL {
                referenceImage = UIImage(contentsOfFile: path)
            }
            didLoad = true
        }
    }
}
