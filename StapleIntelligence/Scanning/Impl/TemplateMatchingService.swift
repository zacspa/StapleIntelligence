//
//  TemplateMatchingService.swift
//  StapleIntelligence
//

import Foundation
import SwiftData

/// Looks up persisted `ReceiptLayoutTemplate` records for a given merchant.
///
/// ## Thread safety
///
/// `findTemplate` accesses a `ModelContext`, which is not `Sendable`. Always call this
/// method on the same actor that owns the context — typically the main actor inside
/// `ReceiptsView.runPipeline`. Never call it from a `Task.detached` block.
///
/// ## Matching strategy
///
/// Templates are **merchant-bound** by design. Matching uses case-insensitive exact
/// equality on `merchantNormalizedName`. Partial or fuzzy matching is intentionally
/// excluded: an imprecise match would silently apply the wrong parsing template and
/// produce lower-quality results than the generic `ReceiptParser` fallback.
///
/// When multiple templates share the same merchant (e.g. a user iteratively improved
/// a template over several receipts), the one with the highest `useCount` is selected
/// as the most battle-tested version.
struct TemplateMatchingService {

    /// Returns the best-matching template for `merchantNormalizedName`, or `nil` if none
    /// exists or the merchant is unknown.
    ///
    /// - Parameters:
    ///   - merchantNormalizedName: The uppercase, trimmed merchant name (as produced by
    ///     `ReceiptParser.canonicalize(_:)`).
    ///   - context: The `ModelContext` to query. Must be called on its owning actor.
    /// - Returns: The highest-`useCount` template whose `merchantNormalizedName` exactly
    ///   matches (case-insensitively), or `nil`.
    func findTemplate(
        for merchantNormalizedName: String,
        in context: ModelContext
    ) -> ReceiptLayoutTemplate? {
        let lower = merchantNormalizedName.lowercased()
        let descriptor = FetchDescriptor<ReceiptLayoutTemplate>()
        let all = (try? context.fetch(descriptor)) ?? []
        let matches = all.filter { $0.merchantNormalizedName.lowercased() == lower }
        return matches.max(by: { $0.useCount < $1.useCount })
    }
}
