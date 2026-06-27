import SwiftUI

// MARK: - Color(hex:)

extension Color {
    /// Hex initializer used by the BlueprintCapture redesign palette.
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

// MARK: - BP — ink / paper / brass palette
//
// Non-negotiable: ink text on warm paper, brass is the only brand accent.
// Saturated color is reserved for the signal set (proof / caution / blocker / info).
// The live viewfinder is the only dark surface; everywhere else is paper.

enum BP {
    // brand
    static let ink        = Color(hex: 0x0D0D0B)
    static let graphite   = Color(hex: 0x1A1A17)
    static let brass      = Color(hex: 0xC7A775)
    static let brassDeep  = Color(hex: 0xA8854F)
    static let brassLit   = Color(hex: 0xD8BD8D)

    // surfaces
    static let canvas     = Color(hex: 0xFAF7F0)
    static let card       = Color(hex: 0xFFFFFF)
    static let inset      = Color(hex: 0xF5F1E8)
    static let sunken     = Color(hex: 0xEBE4D7)
    static let viewfinder = Color(hex: 0x15140F)

    // text
    static let textStrong = Color(hex: 0x0D0D0B)
    static let textBody   = Color(hex: 0x1A1A17)
    static let textMuted  = Color(hex: 0x5F5D54)
    static let textFaint  = Color(hex: 0x817E72)
    static let onInk      = Color(hex: 0xF3EFE6)

    // borders
    static let line       = Color(hex: 0xDED7C8)
    static let lineSoft   = Color(hex: 0xEBE4D7)
    static let lineStrong = Color(hex: 0xC8BFAC)

    // signal — fg / bg / border
    static let proofFg = Color(hex: 0x1F6B4F), proofBg = Color(hex: 0xEEF5F1), proofBd = Color(hex: 0xDCEBE3)
    static let warnFg  = Color(hex: 0x9A6A16), warnBg  = Color(hex: 0xFAF3E2), warnBd  = Color(hex: 0xF3E7CB)
    static let blockFg = Color(hex: 0x9B3027), blockBg = Color(hex: 0xFAEAE7), blockBd = Color(hex: 0xF1D9D5)
    static let infoFg  = Color(hex: 0x1F4F8F), infoBg  = Color(hex: 0xEAF1F9), infoBd  = Color(hex: 0xD7E4F2)

    // viewfinder readouts — brighter 500 shades on dark
    static let proofLit = Color(hex: 0x3A9170)
    static let warnLit  = Color(hex: 0xD09A2C)
}

// MARK: - Signal set
//
// The four reserved saturated families. Used by status chips, QA gates,
// sensor readouts and notification icons — never as decoration.

enum BPSignal {
    case proof   // validated, pass, available, paid
    case caution // review, missing coverage, recapture
    case blocker // failure, destructive, REC
    case info    // processing, ranking, in-review
    case neutral // ink-on-paper, no saturation

    var fg: Color {
        switch self {
        case .proof:   return BP.proofFg
        case .caution: return BP.warnFg
        case .blocker: return BP.blockFg
        case .info:    return BP.infoFg
        case .neutral: return BP.textMuted
        }
    }

    var bg: Color {
        switch self {
        case .proof:   return BP.proofBg
        case .caution: return BP.warnBg
        case .blocker: return BP.blockBg
        case .info:    return BP.infoBg
        case .neutral: return BP.inset
        }
    }

    var border: Color {
        switch self {
        case .proof:   return BP.proofBd
        case .caution: return BP.warnBd
        case .blocker: return BP.blockBd
        case .info:    return BP.infoBd
        case .neutral: return BP.line
        }
    }
}

// MARK: - Spacing · radius

enum Space {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum Radius {
    static let xs: CGFloat = 2
    static let sm: CGFloat = 4
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
    static let full: CGFloat = 999
}

// MARK: - Motion
//
// Quick and mechanical. No bounce / spring on chrome. Respect reduceMotion.

enum BPMotion {
    static let transition = Animation.easeOut(duration: 0.2)
    static let ring = Animation.easeOut(duration: 0.35)
}
