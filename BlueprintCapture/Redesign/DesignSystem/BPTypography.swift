import SwiftUI

// MARK: - Font families
//
// Manrope — UI / headlines (semibold, tight)
// Newsreader — display / editorial moments (onboarding headline, large titles)
// IBM Plex Mono — every measurable number (IDs, GB, %, payouts, counts, timers, coords)
//
// Custom fonts are registered via Info.plist UIAppFonts; Font.custom falls back to
// the system font automatically if a face is missing (e.g. in some previews).

extension Font {
    static func bpSans(_ size: CGFloat, _ w: Font.Weight = .semibold) -> Font {
        let name: String
        switch w {
        case .bold, .heavy, .black: name = "Manrope-Bold"
        case .semibold:             name = "Manrope-SemiBold"
        case .medium:               name = "Manrope-Medium"
        default:                    name = "Manrope-Regular"
        }
        return .custom(name, size: size)
    }

    static func bpDisplay(_ size: CGFloat) -> Font {
        .custom("Newsreader-Medium", size: size)
    }

    static func bpMono(_ size: CGFloat, _ medium: Bool = true) -> Font {
        .custom(medium ? "IBMPlexMono-Medium" : "IBMPlexMono-Regular", size: size)
    }
}

// MARK: - Type scale (pt)

enum BPType {
    static let largeTitle: CGFloat = 26
    static let title: CGFloat = 20
    static let bodyL: CGFloat = 18
    static let body: CGFloat = 16
    static let bodyS: CGFloat = 14
    static let caption: CGFloat = 13
    static let micro: CGFloat = 11 // eyebrow
}

// MARK: - Tracking

enum BPTracking {
    static let headlineLarge: CGFloat = -0.8
    static let headline: CGFloat = -0.4
    static let eyebrow: CGFloat = 1.6
}

// MARK: - Semantic text modifiers

extension View {
    /// UPPERCASE, wide-tracked muted eyebrow. Rendered in mono so any figures it
    /// carries (counts, IDs) obey the "numbers are always mono" rule and it reads
    /// as a precise instrument label.
    func bpEyebrow(_ color: Color = BP.textMuted) -> some View {
        self
            .font(.bpMono(BPType.micro))
            .tracking(BPTracking.eyebrow)
            .foregroundStyle(color)
            .textCase(.uppercase)
    }
}

/// Eyebrow label — small uppercase brass-or-muted kicker above a title.
struct BPEyebrow: View {
    let text: String
    var color: Color = BP.textMuted
    init(_ text: String, color: Color = BP.textMuted) {
        self.text = text
        self.color = color
    }
    var body: some View {
        Text(text)
            .bpEyebrow(color)
    }
}
