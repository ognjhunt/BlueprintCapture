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

// MARK: - BP — the tryblueprint.io palette
//
// These are the public site's tokens, not an app-specific palette. The site
// (`client/src/components/site/minimal-site.css` in Blueprint-WebApp) is built
// from five colours and nothing else: paper, ink, muted, one green, one rule.
// The app is the same product, so it uses the same five.
//
// What that rules out is as important as what it allows. The site has no
// shadows, no filled cards and no second accent — structure is carried by
// hairline rules on bare paper. Anything here that reads as "card chrome" is a
// leftover and should go, not be restyled.
//
// Saturated colour stays reserved for the signal set (proof / caution /
// blocker / info), which already matches the webapp's signal ramp exactly.
// The live viewfinder is the only dark surface; everywhere else is paper.

enum BP {
    // brand — the five site tokens
    static let ink        = Color(hex: 0x22251E) // --ms-ink
    static let graphite   = Color(hex: 0x2F332B) // ink, lifted for secondary chrome
    static let brass      = Color(hex: 0x203D2E) // --ms-green: the only accent
    static let brassDeep  = Color(hex: 0x315440) // .ms-button:hover
    static let brassLit   = Color(hex: 0x46705A) // nav/link hover

    // surfaces
    static let canvas     = Color(hex: 0xF6F5EF) // --ms-paper
    static let card       = Color(hex: 0xFCFCF8) // .ms-form input / .ms-verdict fill
    static let inset      = Color(hex: 0xF1F0E9)
    static let sunken     = Color(hex: 0xE8E7DE)
    static let viewfinder = Color(hex: 0x22251E) // ink, so recording reads as the same product

    // text
    static let textStrong = Color(hex: 0x22251E) // --ms-ink
    static let textBody   = Color(hex: 0x32362D)
    static let textMuted  = Color(hex: 0x62645D) // --ms-muted
    static let textFaint  = Color(hex: 0x777E70) // .ms-form input::placeholder
    static let onInk      = Color(hex: 0xF6F5EF) // paper on green/ink, per .ms-button

    // borders
    static let line       = Color(hex: 0xBABDB3) // --ms-rule
    static let lineSoft   = Color(hex: 0xD7DBD0) // .ms-legal section / .ms-inquiry-aside
    static let lineStrong = Color(hex: 0xBAC0B2) // .ms-form input border

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

// The site is effectively square: 3pt on buttons, 2pt on inputs, and nothing
// else is rounded at all. Panels and sheets get 0 — on paper a rule does the
// separating, not a corner. `full` stays for status dots and avatars.
enum Radius {
    static let xs: CGFloat = 2   // .ms-form input
    static let sm: CGFloat = 3   // .ms-button
    static let md: CGFloat = 3
    static let lg: CGFloat = 0   // panels / sheets: square
    static let full: CGFloat = 999
}

// MARK: - Motion
//
// Quick and mechanical. No bounce / spring on chrome. Respect reduceMotion.

enum BPMotion {
    static let transition = Animation.easeOut(duration: 0.2)
    static let ring = Animation.easeOut(duration: 0.35)
}
