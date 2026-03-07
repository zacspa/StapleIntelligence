//
//  AppTheme.swift
//  StapleIntelligence
//

import SwiftUI

enum AppTheme {
    enum Colors {
        static let base       = Color(hex: "121212")
        static let surface    = Color(hex: "1C1C1E")
        static let surfaceAlt = Color(hex: "242426")
        static let border     = Color(hex: "3A3A3C")
        static let accent     = Color(hex: "80FFD4")
        static let accentDim  = Color(hex: "80FFD4").opacity(0.15)
        static let positive   = Color(hex: "30D158")
        static let negative   = Color(hex: "FF453A")
        static let caution    = Color(hex: "FF9F0A")
        static let secondary  = Color(hex: "EBEBF5").opacity(0.60)
        static let tertiary   = Color(hex: "EBEBF5").opacity(0.30)
    }

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs:  CGFloat = 4
        static let sm:  CGFloat = 8
        static let md:  CGFloat = 12
        static let lg:  CGFloat = 16
        static let xl:  CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let xs:   CGFloat = 4
        static let sm:   CGFloat = 6
        static let md:   CGFloat = 8
        static let lg:   CGFloat = 12
        static let xl:   CGFloat = 16
        static let xxl:  CGFloat = 20
        static let pill: CGFloat = 999
    }

    enum Typography {
        static let hero:         Font = .system(size: 40, weight: .bold, design: .rounded)
        static let sectionLabel: Font = .subheadline
        static let body:         Font = .body
        static let bodyMono:     Font = .body.monospacedDigit()
        static let caption:      Font = .caption
        static let badge:        Font = .caption.weight(.semibold)
    }

    enum Animation {
        static let springList = SwiftUI.Animation.spring(response: 0.38, dampingFraction: 0.72)
        static let springCard = SwiftUI.Animation.spring(response: 0.30, dampingFraction: 0.65)
        static let slideStep  = SwiftUI.Animation.spring(response: 0.40, dampingFraction: 0.78)
        static let easeOut    = SwiftUI.Animation.easeOut(duration: 0.25)
    }

    enum Glow {
        static let accentRadius:   CGFloat = 6
        static let accentOpacity:  Double  = 0.45
        static let accentRadius2:  CGFloat = 16
        static let accentOpacity2: Double  = 0.20
        static let cautionRadius:  CGFloat = 8
        static let cautionOpacity: Double  = 0.40
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red:     Double(r) / 255,
            green:   Double(g) / 255,
            blue:    Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
