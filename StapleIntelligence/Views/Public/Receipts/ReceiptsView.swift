//
//  ReceiptsView.swift
//  StapleIntelligence
//
//  Created by Zack Sparks on 3/2/26.
//

import SwiftUI
import SwiftData
import UIKit
import OSLog

struct ReceiptsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Receipt.createdAt, order: .reverse) private var receipts: [Receipt]

    @State private var isShowingScanner = false
    @State private var scannedImages: [UIImage] = []
    @State private var parsedReceipt: ParsedReceipt? = nil
    @State private var scanError: IdentifiableError? = nil
    @State private var isProcessing = false
    @State private var pipelineTask: Task<Void, Never>? = nil
    @State private var receiptToDelete: Receipt? = nil

    private let ocrService = ReceiptOCRService()
    private let parser = ReceiptParser()

    var body: some View {
        NavigationStack {
            Group {
                if receipts.isEmpty {
                    ContentUnavailableView(
                        "No Receipts",
                        systemImage: "receipt",
                        description: Text("Tap + to scan your first receipt.")
                    )
                } else {
                    let _ = ScanningLog.edit.debug("ReceiptsView body — \(receipts.count, privacy: .public) receipts @ \(ts(), privacy: .public)")
                    List(receipts) { receipt in
                        NavigationLink(value: receipt) {
                            ReceiptRow(receipt: receipt)
                        }
                        .simultaneousGesture(LongPressGesture().onEnded { _ in
                            receiptToDelete = receipt
                        })
                    }
                    .navigationDestination(for: Receipt.self) { receipt in
                        ReceiptEditView(receipt: receipt)
                    }
                }
            }
            .navigationTitle("Receipts")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isShowingScanner = true
                    } label: {
                        Label("Add Receipt", systemImage: "plus")
                    }
                    .disabled(isProcessing)
                }
            }
            .overlay {
                if isProcessing {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Processing receipt…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .alert("Delete Receipt?", isPresented: Binding(
            get: { receiptToDelete != nil },
            set: { if !$0 { receiptToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let receipt = receiptToDelete {
                    let receiptID = receipt.id
                    Task { await ReceiptPersistenceService.deleteImages(for: receiptID) }
                    modelContext.delete(receipt)
                    receiptToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) { receiptToDelete = nil }
        } message: {
            if let receipt = receiptToDelete {
                Text("\(receipt.merchant?.displayName ?? "Unknown Merchant") will be permanently deleted.")
            }
        }
        .fullScreenCover(isPresented: $isShowingScanner) {
            ScannerView(
                onScan: { images in
                    isShowingScanner = false
                    scannedImages = images
                    pipelineTask?.cancel()
                    pipelineTask = Task { await runPipeline(images: images) }
                },
                onCancel: {
                    pipelineTask?.cancel()
                    pipelineTask = nil
                    isShowingScanner = false
                }
            )
        }
        .sheet(item: $parsedReceipt) { receipt in
            ReceiptReviewView(
                parsed: receipt,
                images: scannedImages,
                onSave: { edited in
                    // Capture `edited` here — Task copies the struct into its heap closure,
                    // giving lineItems a strong reference before any suspension.
                    Task { await handleSave(parsed: edited) }
                },
                onCancel: { parsedReceipt = nil }
            )
        }
        .alert(item: $scanError) { err in
            Alert(
                title: Text("Scan Failed"),
                message: Text(err.underlying.localizedDescription),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    // MARK: - Pipeline

    private func runPipeline(images: [UIImage]) async {
        let tx = ReceiptProcessTransaction()
        let pipelineStart = Date()
        isProcessing = true

        tx.endScan(pageCount: images.count)

        do {
            let ocrStart = Date()
            let (ocrLines, avgConf) = try await ocrService.recognizeText(in: images)
            tx.endOCR(lineCount: ocrLines.count, avgConfidence: avgConf, durationMs: ms(since: ocrStart))

            let parseStart = Date()
            let localParser = parser
            let parsed = await Task.detached(priority: .userInitiated) { localParser.parse(ocrLines) }.value
            tx.endParse(
                itemCount: parsed.lineItems.count,
                parseConfidence: parsed.parseConfidence,
                reconciliation: parsed.reconciliationStatus,
                lowConfItemCount: parsed.lineItems.filter { $0.confidence < 0.9 }.count,
                durationMs: ms(since: parseStart)
            )

            isProcessing = false
            parsedReceipt = parsed
            tx.end(totalDurationMs: ms(since: pipelineStart))

        } catch {
            isProcessing = false
            scanError = IdentifiableError(underlying: error)
            let code = (error as? ScanError)?.code
                ?? (error as? OCRError)?.code
                ?? (error as? ParseError)?.code
                ?? -1
            tx.end(totalDurationMs: ms(since: pipelineStart), errorCode: code)
        }
    }

    private func handleSave(parsed: ParsedReceipt) async {
        let tx = ReceiptProcessTransaction()
        let start = Date()
        let service = ReceiptPersistenceService(modelContext: modelContext)

        #if DEBUG
        appendDebugLog("handleSave: \(parsed.lineItems.count) items\n")
        #endif

        do {
            _ = try await service.persist(parsed: parsed, images: scannedImages, tx: tx)
            tx.end(totalDurationMs: ms(since: start))
        } catch {
            tx.end(totalDurationMs: ms(since: start), errorCode: (error as? PersistenceError)?.code ?? -1)
            scanError = IdentifiableError(underlying: error)
        }
        scannedImages = []
        parsedReceipt = nil
    }

    #if DEBUG
    private func appendDebugLog(_ content: String) {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let url = docs.appendingPathComponent("parse_debug.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            if let data = content.data(using: .utf8) { handle.write(data) }
            try? handle.close()
        } else {
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }
    #endif

    private func ms(since start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1000)
    }

    private func ts() -> String {
        let d = Date()
        let ms = Int(d.timeIntervalSince1970 * 1000) % 1000
        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: d)
        return String(format: "%02d:%02d:%02d.%03d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0, ms)
    }
}

// MARK: - Receipt list row

private struct ReceiptRow: View {
    let receipt: Receipt

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(receipt.merchant?.displayName ?? "Unknown Merchant")
                    .font(.body)
                Text(receipt.purchaseDate?.formatted(date: .abbreviated, time: .omitted) ?? "Unknown date")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let total = receipt.total {
                    Text(total, format: .currency(code: "USD"))
                        .monospacedDigit()
                }
                Text("\(receipt.lineItems.count) items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Error helper

struct IdentifiableError: Identifiable {
    let id = UUID()
    let underlying: Error
}

#Preview {
    ReceiptsView()
        .modelContainer(for: [Receipt.self, LineItem.self, Merchant.self, MerchantProduct.self, MergeRule.self], inMemory: true)
}
