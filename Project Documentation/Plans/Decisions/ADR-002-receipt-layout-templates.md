# ADR-002: Receipt Layout Template System

**Status**: Accepted
**Date**: 2026-03-07
**Deciders**: Zack Sparks

---

## Context

`ReceiptParser` uses regex heuristics tuned for common receipt formats. It handles ALDI-style
split-column layouts explicitly but produces low `parseConfidence` for unusual merchants:
European formats, specialty stores, warehouse clubs with unconventional footers. Each new
layout requires a code change and a new regex branch.

The goal is a user-teachable system: the user labels OCR regions on a real receipt once,
the template is stored, and future scans from the same merchant apply that template automatically —
with a clean fallback to the generic parser when no template exists or confidence is lower.

---

## Decision

### Templates are always merchant-bound

There are no "generic" or unbound templates. Every `ReceiptLayoutTemplate` requires a
`merchantNormalizedName`. This is a hard constraint enforced in the UI (Save is disabled
until a non-empty merchant name is present).

**Why**: An unbound template would require the user to manually select it on every scan.
Merchant-binding makes the system fully automatic after the initial labeling step, which
is the core value proposition. Partial matching (fuzzy merchant names) was considered and
rejected — a wrong match would silently apply the wrong parsing template and produce
results worse than the generic fallback.

### Confidence-wins selection

After OCR, both the generic `ReceiptParser` and the matching `TemplateParser` (if a
template exists) produce a `ParsedReceipt`. The one with the higher `parseConfidence`
is shown to the user.

**Why**: Templates created from a single receipt may degrade over time as OCR quality
varies or receipt layouts change slightly. Using the higher-confidence result ensures the
user always sees the best available parse, even if that means the template is temporarily
outperformed by the generic parser.

### Templates run synchronously on the main actor

`TemplateParser.parse(ocrLines:template:)` runs synchronously inside `runPipeline` rather
than in a `Task.detached` block. `ReceiptLayoutTemplate` is a SwiftData `@Model` class and
is not `Sendable`; accessing it from a detached task would be unsafe. Template parsing is
O(lines × fields) and trivially fast (< 1 ms for typical receipts), so there is no
performance justification for parallelising it.

### OCR lines are persisted alongside the template

`ReceiptLayoutTemplate` stores a JSON-encoded copy of the OCR lines from the labeling
session (`ocrLinesJSON`). This allows the labeler to re-open a template in edit mode
without re-running OCR on the reference image.

**Considered alternative**: store only the reference image and re-run OCR on demand. This
was rejected because it introduces an async dependency and an additional OCR inference in
the settings flow, which has no budget for a spinner. Storing ~20 KB of JSON per template
is negligible.

### Discount `lineTotal` is negated

`TemplateParser` negates the price extracted from `.discount` lines (`lineTotal = -|price|`)
so that `sum(lineItems) ≈ subtotal` arithmetic is correct and reconciliation works as
expected. This mirrors `ReceiptParser`'s treatment of discount items.

### BBox overlay uses ZStack + offset, not UIScrollView subviews

The labeling UI renders bounding-box overlays as SwiftUI `Rectangle` views inside a
`ZStack(alignment: .topLeading)`, sized and positioned via `.frame(width:height:)` and
`.offset(x:y:)`. Zoom is handled by `MagnificationGesture` scaling the whole `ZStack`
inside a `ScrollView`.

**Considered alternative**: a UIKit `UIScrollView` subclass with `UIView` overlays. This
was rejected for complexity — bridging tap events back to SwiftUI `@State` would require a
`UIViewRepresentable` coordinator and significant boilerplate. The SwiftUI approach is
simpler, correct, and performs well for the ~100 OCR line boxes typical of a grocery receipt.

---

## Consequences

### Positive
- Zero code changes needed to add support for new merchant layouts — users teach the app.
- Labeling is a one-time cost per merchant; subsequent scans are automatic.
- The confidence-wins selection provides a natural safety net against poor templates.
- Edit mode works offline without re-running OCR.

### Negative / Trade-offs
- Templates are merchant-name-exact: a merchant that OCR reads as "WHOLE FOODS" on some
  receipts and "WHOLE FOODS MARKET" on others will not match a single template. Mitigation:
  users can create multiple templates and the highest-`useCount` one wins.
- No multi-page labeling: template regions apply only to page 0 (the page with bounding
  boxes). Multi-page receipts are partially supported.
- The spatial pairing algorithm (Y-midpoint nearest-neighbour) can mis-pair items on
  receipts where names and prices are not horizontally aligned. The confidence score will
  be low in these cases, surfacing the low-confidence banner.

---

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| Hard-code new regex branches per merchant | Requires developer involvement; doesn't scale |
| ML-based layout classification | Requires training data; out of scope for MVP |
| User selects template manually per scan | Defeats the automation goal |
| Fuzzy merchant-name matching | Risk of wrong template application |
| Store only reference image, re-run OCR on edit | Adds async load + spinner to settings flow |
