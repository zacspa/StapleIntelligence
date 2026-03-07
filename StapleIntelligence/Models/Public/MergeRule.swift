//
//  MergeRule.swift
//  StapleIntelligence
//
//  Created by Zack Sparks on 3/6/26.
//

import SwiftData
import Foundation

/// Persists user-made canonical name corrections so future scans of the same raw item
/// name automatically use the corrected name.
@Model final class MergeRule {
    var rawName: String
    var canonicalName: String
    var createdAt: Date

    init(rawName: String, canonicalName: String) {
        self.rawName = rawName
        self.canonicalName = canonicalName
        self.createdAt = Date()
    }
}
