import SwiftUI

// MARK: - Font families
//
// DM Sans — everything. The public site sets one family for the whole surface
// and leans on size and tracking rather than a second face, so the app does too.
// IBM Plex Mono — every measurable number (IDs, GB, %, payouts, counts, timers, coords)
//
// Display is DM Sans at weight 400, not a serif. On the site headings are
// `font-weight: 400` with heavy negative tracking, which is what gives it the
// bare, drawn-not-branded look; a semibold sans or a Newsreader serif both read
// as a different company.
//
// Custom fonts are registered via Info.plist UIAppFonts; Font.custom falls back to
// the system font automatically if a face is missing (e.g. in some previews).

extension Font {
    static func bpSans(_ size: CGFloat, _ w: Font.Weight = .regular) -> Font {
        let name: String
        switch w {
        case .bold, .heavy, .black: name = "DMSans-Bold"
        case .semibold, .medium:    name = "DMSans-Medium"
        default:                    name = "DMSans-Regular"
        }
        return .custom(name, size: size)
    }

    /// Site headline treatment: DM Sans at 400. Pair with `.bpDisplayTracking`.
    static func bpDisplay(_ size: CGFloat) -> Font {
        .custom("DMSans-Regular", size: size)
    }

    static func bpMono(_ size: CGFloat, _ medium: Bool = true) -> Font {
        .custom(medium ? "IBMPlexMono-Medium" : "IBMPlexMono-Regular", size: size)
    }
}

// MARK: - Tracking
//
// The site's headings run from -.065em (hero) to -.03em (section heads), and
// the eyebrow runs the other way at +.12em uppercase. Tracking in SwiftUI is
// absolute, so these convert from the em value at the call site's size.

extension View {
    /// Negative tracking for headline sizes. `em` defaults to the site's -.055em.
    func bpDisplayTracking(_ size: CGFloat, em: CGFloat = -0.055) -> some View {
        self.tracking(size * em)
    }

    /// The uppercase eyebrow: 11pt, +.12em, muted.
    func bpEyebrowTracking(_ size: CGFloat = 11) -> some View {
        self.tracking(size * 0.12)
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
