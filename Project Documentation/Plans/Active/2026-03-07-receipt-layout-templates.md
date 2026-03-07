# Plan: Universal Receipt Layout Templating

**Status**: Active
**Created**: 2026-03-07

## Goal
Allow users to label OCR regions on a receipt once; future receipts from the same merchant auto-use that template for extraction, falling back to the generic parser when no template matches.

## Scope
**In scope**: Template data model, template matching service, template-based parser, labeling UI, Settings management list, pipeline integration with confidence-based winner selection.
**Out of scope**: Multi-page labeling, barcode-assisted matching, cloud sync of templates.

## Acceptance Criteria
- [ ] Labeler renders: open any receipt in ReceiptReviewView, tap "Teach Layout" → labeler shows image with OCR boxes overlaid
- [ ] Labeling works: tap a box, pick "Merchant Name" → box fills color with chip label
- [ ] Save persists: save template, open Settings → Receipt Templates → template appears with correct name/merchant
- [ ] Template applied: scan same-merchant receipt → parse uses template, confidence is higher
- [ ] Fallback works: scan different-merchant receipt → generic parser runs (no crash, normal flow)
- [ ] Edit mode: tap saved template in list → labeler opens with existing labels pre-populated
- [ ] Low-confidence banner: badly-parsed receipt shows banner in ReceiptReviewView

## Approach

### Files Created
- `Scanning/Public/ReceiptTemplate.swift` — `ReceiptFieldLabel`, `CodableCGRect`, `TemplateField`, `CodableOCRLine`
- `Models/Public/ReceiptLayoutTemplate.swift` — SwiftData model with JSON-encoded fields + ocrLines
- `Scanning/Impl/TemplateMatchingService.swift` — merchant-name lookup, highest useCount wins
- `Scanning/Impl/TemplateParser.swift` — bbox-intersection grouping, Y-midpoint name/price pairing
- `Views/Public/Receipts/ReceiptTemplateLabelerView.swift` — image canvas + bbox overlays + picker sheet
- `Views/Public/Settings/TemplateListView.swift` — CRUD list with edit mode

### Files Modified
- `StapleIntelligenceApp.swift` — added `ReceiptLayoutTemplate` to ModelContainer schema
- `ReceiptsView.swift` — added `ocrLinesForReview` state, template lookup in pipeline, pass ocrLines to review
- `ReceiptReviewView.swift` — added `ocrLines` param, low-confidence banner, "Teach Layout" bottom bar button
- `SettingsView.swift` — added "Receipt Templates" navigation row
- `ReceiptParser.swift` — exposed `datePattern`, `dollarAmountPattern`, `priceWithCodePattern`, `standalonePricePattern` as internal static

## Open Questions / Blockers
- None currently
