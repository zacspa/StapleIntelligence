//
//  ReceiptPersistenceService.swift
//  StapleIntelligence
//
//  Created by Zack Sparks on 3/2/26.
//

import UIKit
import SwiftData
import OSLog

struct ReceiptPersistenceService {
    let modelContext: ModelContext

    /// Persists images and SwiftData models. Returns the new receipt UUID.
    /// Hops off @MainActor for image I/O, then back for SwiftData insert.
    func persist(parsed: ParsedReceipt, images: [UIImage], tx: ReceiptProcessTransaction) async throws -> UUID {
        let receiptID = UUID()
        
        let localLineItems = parsed.lineItems
        let localMerchantName = parsed.merchantName
        let localDate = parsed.purchaseDate

        // 1. Save images off-actor
        let imgStart = Date()
        let imageURLs = try await saveImages(images, receiptID: receiptID)
        let imgMs = Int(Date().timeIntervalSince(imgStart) * 1000)
        tx.endImagePersist(pageCount: images.count, durationMs: imgMs)

        // 2. SwiftData insert on @MainActor
        let dbStart = Date()
        let merchant = localMerchantName.flatMap { name -> Merchant? in
            try? findOrCreateMerchant(displayName: name)
        }
        let normalizedMerchantName = merchant?.normalizedName

        // Batch-fetch all existing MerchantProducts for this merchant in one query,
        // then resolve/insert from a dictionary — avoids N per-item SQLite queries.
        var productsBySku: [String: MerchantProduct] = [:]
        if let normalized = normalizedMerchantName {
            let skusInReceipt = Set(localLineItems.compactMap(\.sku))
            if !skusInReceipt.isEmpty {
                let desc = FetchDescriptor<MerchantProduct>(
                    predicate: #Predicate { $0.normalizedMerchantName == normalized }
                )
                if let existing = try? modelContext.fetch(desc) {
                    for p in existing where skusInReceipt.contains(p.sku) {
                        p.lastSeenAt = Date()
                        productsBySku[p.sku] = p
                    }
                }
            }
        }

        let lineItems: [LineItem] = localLineItems.enumerated().map { (index, item) in
            var resolvedCanonical = item.canonicalName
            if let sku = item.sku {
                if let existing = productsBySku[sku] {
                    resolvedCanonical = existing.canonicalName
                } else if let normalized = normalizedMerchantName {
                    let product = MerchantProduct(
                        normalizedMerchantName: normalized, sku: sku, canonicalName: item.canonicalName)
                    modelContext.insert(product)
                    productsBySku[sku] = product  // prevent duplicates within this receipt
                }
            }
            return LineItem(
                rawName: item.rawName,
                canonicalName: resolvedCanonical,
                itemType: item.itemType,
                unitPrice: item.unitPrice,
                lineTotal: item.lineTotal,
                isDiscount: item.isDiscount,
                confidence: item.confidence,
                sku: item.sku,
                sortOrder: index
            )
        }

        let receipt = Receipt(
            id: receiptID,
            merchant: merchant,
            purchaseDate: localDate,
            lineItems: lineItems,
            subtotal: parsed.subtotal,
            tax: parsed.tax,
            total: parsed.total,
            rawOcrText: parsed.rawOcrText,
            parseConfidence: parsed.parseConfidence,
            reconciliationStatus: parsed.reconciliationStatus,
            imageURLs: imageURLs
        )
        modelContext.insert(receipt)

        do {
            try modelContext.save()
        } catch {
            let nsError = error as NSError
            throw PersistenceError.modelContextSaveFailed(underlyingCode: nsError.code)
        }

        let dbMs = Int(Date().timeIntervalSince(dbStart) * 1000)
        tx.endDbSave(durationMs: dbMs)
        ScanningLog.dbSave.log("Persisted receipt \(receiptID.uuidString, privacy: .public)")

        #if DEBUG
        appendReceiptDebugLog(receipt)
        #endif

        return receiptID
    }

    // MARK: - Private helpers

    #if DEBUG
    private func appendReceiptDebugLog(_ receipt: Receipt) {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let url = docs.appendingPathComponent("parse_debug.log")
        var lines: [String] = [
            "",
            "=== persisted Receipt \(receipt.id.uuidString) ===",
            "merchant:      \(receipt.merchant?.displayName ?? "<nil>")",
            "purchaseDate:  \(receipt.purchaseDate?.description ?? "<nil>")",
            "subtotal:      \(receipt.subtotal?.description ?? "<nil>")",
            "tax:           \(receipt.tax?.description ?? "<nil>")",
            "total:         \(receipt.total?.description ?? "<nil>")",
            "confidence:    \(receipt.parseConfidence)",
            "reconciliation:\(receipt.reconciliationStatus.rawValue)",
            "lineItems:     \(receipt.lineItems.count)",
        ]
        for (i, item) in receipt.lineItems.enumerated() {
            var info = "  [\(i)] \(item.canonicalName) = \(item.lineTotal)"
            if item.rawName != item.canonicalName { info += "  raw=\"\(item.rawName)\"" }
            if let sku = item.sku { info += "  sku=\(sku)" }
            if case .byWeight(let qty, let unit) = item.itemType {
                info += "  \(String(format: "%.2f", qty)) \(unit.rawValue)"
                if let up = item.unitPrice { info += " × \(up)/\(unit.rawValue)" }
            }
            if item.isDiscount { info += "  DISC" }
            lines.append(info)
        }
        lines.append("")
        let block = lines.joined(separator: "\n")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            if let data = block.data(using: .utf8) { handle.write(data) }
            try? handle.close()
        } else {
            try? block.write(to: url, atomically: true, encoding: .utf8)
        }
    }
    #endif

    /// nonisolated: runs off @MainActor writing JPEGs to Documents/receipts/<id>/page_<i>.jpg
    private nonisolated func saveImages(_ images: [UIImage], receiptID: UUID) async throws -> [URL] {
        try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let docs = try fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let dir = docs.appendingPathComponent("receipts/\(receiptID.uuidString)", isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)

            var urls: [URL] = []
            for (i, image) in images.enumerated() {
                let url = dir.appendingPathComponent("page_\(i).jpg")
                guard let data = image.jpegData(compressionQuality: 0.85) else {
                    throw PersistenceError.imageWriteFailed(pageIndex: i, underlyingCode: -1)
                }
                do {
                    try data.write(to: url, options: .atomic)
                } catch {
                    let nsError = error as NSError
                    throw PersistenceError.imageWriteFailed(pageIndex: i, underlyingCode: nsError.code)
                }
                urls.append(url)
            }
            return urls
        }.value
    }

    /// @MainActor: dedup merchant by normalized name using FetchDescriptor
    private func findOrCreateMerchant(displayName: String) throws -> Merchant {
        let normalized = displayName.uppercased().trimmingCharacters(in: .whitespaces)
        var descriptor = FetchDescriptor<Merchant>(
            predicate: #Predicate { $0.normalizedName == normalized }
        )
        descriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }
        let merchant = Merchant(displayName: displayName, normalizedName: normalized)
        modelContext.insert(merchant)
        return merchant
    }

}
