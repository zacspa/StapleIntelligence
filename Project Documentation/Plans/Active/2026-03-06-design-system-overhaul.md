# Plan: StapleIntelligence Dark Mode Design System Overhaul

**Status**: Active
**Created**: 2026-03-06

## Goal

Establish a token-based design system and reusable component library, then apply it across all 11 views to achieve a dark-mode-first premium feel with depth, glow, spring animations, and haptic feedback.

## Scope

**In scope:**
- `AppTheme.swift` token namespace (colors, spacing, radii, typography, animation, glow)
- Component library: AppCard, PrimaryButtonStyle, SecondaryButtonStyle, SectionHeader, DeltaBadge, GlowModifier, HapticFeedback, FrostedOverlay
- Apply tokens + components to all 11 view files
- UIAppearance for tab bar blur + segmented control tint
- `.toolbarBackground` for nav bar frosted glass
- Glowing charts (double-shadow), spring list animations, haptic feedback
- AccentColor.colorset updated to Neon Mint #80FFD4
- ADR-001 documenting all architectural decisions

**Out of scope:** ScannerView (UIKit UIViewController), third-party libraries, custom fonts, barcode scanning, data model changes.

## Acceptance Criteria

- [x] `AppTheme.swift` with all token namespaces created
- [x] `AccentColor.colorset` updated to Neon Mint (#80FFD4)
- [x] `StapleIntelligenceApp.init()` with UITabBar and UISegmentedControl UIAppearance
- [x] All 7 component files created in `Views/Components/`
- [x] `ContentView` — selectedTab state + onChange haptic
- [x] `DashboardView` — AppCard, SectionHeader, DeltaBadge, chart glow, spring animation
- [x] `InsightsView` — AppCard, SectionHeader, DeltaBadge, chart glow, caution-glow PriceMovers, picker haptic
- [x] `ReceiptsView` — dark list, spring animation, FrostedOverlay, delete haptic, toolbar
- [x] `ReceiptReviewView` — dark Form, monospaced LabeledContent, save haptic, toolbar
- [x] `ValidationReviewView` — token ProgressBar, AppCard IssueCards, PrimaryButtonStyle/SecondaryButtonStyle, step haptic, success haptic
- [x] `ReceiptEditView` — dark Form, monospaced LabeledContent, save haptic, toolbar
- [x] `ItemDetailView` — dark Form, semantic color tokens, toolbar
- [x] `SettingsView` — dark Form, toolbar (Toggle tint auto-fixed via AccentColor.colorset)
- [x] ADR-001 written at `Project Documentation/Plans/Decisions/ADR-001-design-system.md`

## Approach

Six phases:
1. Token Foundation: AppTheme, AccentColor, App init
2. Component Library: 7 component files
3. Dashboard + Insights: Highest visual impact, chart glow precedent
4. Receipts Flow: ReceiptsView through ItemDetailView
5. Settings + ContentView
6. Documentation: ADR-001, plan files, README

## Open Questions / Blockers

- None
