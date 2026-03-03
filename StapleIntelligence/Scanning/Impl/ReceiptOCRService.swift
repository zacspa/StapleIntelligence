//
//  ReceiptOCRService.swift
//  StapleIntelligence
//
//  Created by Zack Sparks on 3/2/26.
//

import UIKit
import Vision
import OSLog

struct ReceiptOCRService {

    private static let minimumConfidenceThreshold = 0.4

    /// Called from @MainActor; returns raw joined text and avg confidence.
    /// OCR runs off-actor inside a Task.detached per page.
    func recognizeText(in images: [UIImage]) async throws -> (rawText: String, avgConfidence: Double) {
        guard !images.isEmpty else {
            throw OCRError.noTextFound
        }

        var pageResults: [(lines: [String], avgConfidence: Double)] = []

        // Process pages concurrently, each escaping @MainActor via Task.detached
        try await withThrowingTaskGroup(of: (Int, [String], Double).self) { group in
            for (index, image) in images.enumerated() {
                group.addTask {
                    let result = try await self.performOCR(on: image)
                    return (index, result.lines, result.avgConfidence)
                }
            }
            var indexed: [(Int, [String], Double)] = []
            for try await result in group {
                indexed.append(result)
            }
            // Restore page order
            pageResults = indexed
                .sorted(by: { $0.0 < $1.0 })
                .map { (lines: $0.1, avgConfidence: $0.2) }
        }

        guard !pageResults.isEmpty else {
            throw OCRError.noTextFound
        }

        let allLines = pageResults.map { $0.lines.joined(separator: "\n") }.joined(separator: "\n\n")
        let avgConf = pageResults.map(\.avgConfidence).reduce(0, +) / Double(pageResults.count)

        guard !allLines.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OCRError.noTextFound
        }

        if avgConf < Self.minimumConfidenceThreshold {
            throw OCRError.belowConfidenceThreshold(avgConf)
        }

        ScanningLog.ocr.log("OCR completed — pages: \(images.count, privacy: .public), avgConf: \(avgConf, privacy: .public)")
        return (rawText: allLines, avgConfidence: avgConf)
    }

    /// nonisolated: escapes @MainActor via Task.detached to run Vision synchronously
    /// on a background thread.
    private nonisolated func performOCR(on image: UIImage) async throws -> (lines: [String], avgConfidence: Double) {
        try await Task.detached(priority: .userInitiated) {
            guard let cgImage = image.cgImage else {
                throw OCRError.noTextFound
            }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"]

            do {
                try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
            } catch {
                throw OCRError.requestFailed(error)
            }

            let observations = request.results ?? []
            if observations.isEmpty {
                throw OCRError.noTextFound
            }

            var lines: [String] = []
            var totalConf = 0.0

            for obs in observations {
                guard let candidate = obs.topCandidates(1).first else { continue }
                lines.append(candidate.string)
                totalConf += Double(candidate.confidence)
            }

            let avgConf = observations.isEmpty ? 0.0 : totalConf / Double(observations.count)
            return (lines: lines, avgConfidence: avgConf)
        }.value
    }
}
