//
//  ReconciliationStatus.swift
//  StapleIntelligence
//
//  Created by Zack Sparks on 3/2/26.
//

/// Whether the sum of a receipt's line items matches the printed subtotal.
enum ReconciliationStatus: String, Codable {
    /// The parser did not have enough data to attempt reconciliation
    /// (e.g. no subtotal was found on the receipt).
    case unverified
    /// `sum(lineItems) ≈ subtotal` within a small tolerance.
    case reconciled
    /// The line-item sum differs from the subtotal by more than the tolerance.
    case discrepancy
}
