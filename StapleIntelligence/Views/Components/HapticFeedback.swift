//
//  HapticFeedback.swift
//  StapleIntelligence
//

import UIKit

/// Thin wrapper around UIKit haptic generators for consistent feedback across the app.
///
/// - `.impact(_:)` — physical interaction feedback (`.light`, `.medium`, `.heavy`)
/// - `.notification(_:)` — outcome feedback (`.success`, `.warning`, `.error`)
/// - `.selection()` — picker / tab-selection feedback
enum HapticFeedback {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
