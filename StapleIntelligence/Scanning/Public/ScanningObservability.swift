//
//  ScanningObservability.swift
//  StapleIntelligence
//
//  Created by Zack Sparks on 3/2/26.
//

import OSLog

// MARK: - Loggers

/// Shared `Logger` instances for the receipt processing pipeline.
/// Each category maps to a pipeline stage: `scan` → `ocr` → `parse` → `db_save`.
/// All log messages use `.public` privacy — no receipt text is ever emitted.
enum ScanningLog {
    static let subsystem = "com.zsparks.StapleIntelligence"
    static let scan      = Logger(subsystem: subsystem, category: "scan")
    static let ocr       = Logger(subsystem: subsystem, category: "ocr")
    static let parse     = Logger(subsystem: subsystem, category: "parse")
    static let dbSave    = Logger(subsystem: subsystem, category: "db_save")
    static let imgSave   = Logger(subsystem: subsystem, category: "image_persist")
    static let edit       = Logger(subsystem: subsystem, category: "edit")
    static let validation = Logger(subsystem: subsystem, category: "validation")
    static let template   = Logger(subsystem: subsystem, category: "template")
}

// MARK: - Transaction

/// Wraps an OSSignposter interval for one full receipt processing run.
/// All logged values use `.public` privacy — no receipt text is ever emitted.
struct ReceiptProcessTransaction {
    private let signposter = OSSignposter(subsystem: ScanningLog.subsystem, category: "receipt_process")
    private let state: OSSignpostIntervalState

    init() {
        state = signposter.beginInterval("receipt_process")
    }

    func endScan(pageCount: Int) {
        ScanningLog.scan.log("scan complete — pages: \(pageCount, privacy: .public)")
    }

    func endOCR(lineCount: Int, avgConfidence: Double, durationMs: Int) {
        ScanningLog.ocr.log(
            "ocr complete — lines: \(lineCount, privacy: .public), avgConf: \(avgConfidence, privacy: .public), ms: \(durationMs, privacy: .public)"
        )
    }

    func endParse(itemCount: Int, parseConfidence: Double, reconciliation: ReconciliationStatus,
                  lowConfItemCount: Int, durationMs: Int) {
        ScanningLog.parse.log(
            "parse complete — items: \(itemCount, privacy: .public), conf: \(parseConfidence, privacy: .public), lowConf: \(lowConfItemCount, privacy: .public), reconciliation: \(reconciliation.rawValue, privacy: .public), ms: \(durationMs, privacy: .public)"
        )
    }

    func endImagePersist(pageCount: Int, durationMs: Int) {
        ScanningLog.imgSave.log(
            "image persist complete — pages: \(pageCount, privacy: .public), ms: \(durationMs, privacy: .public)"
        )
    }

    func endDbSave(durationMs: Int) {
        ScanningLog.dbSave.log("db save complete — ms: \(durationMs, privacy: .public)")
    }

    func end(totalDurationMs: Int, errorCode: Int? = nil) {
        if let code = errorCode {
            ScanningLog.scan.error(
                "receipt_process failed — errorCode: \(code, privacy: .public), totalMs: \(totalDurationMs, privacy: .public)"
            )
        } else {
            ScanningLog.scan.log(
                "receipt_process succeeded — totalMs: \(totalDurationMs, privacy: .public)"
            )
        }
        signposter.endInterval("receipt_process", state)
    }

}
