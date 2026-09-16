import SwiftUI

// MARK: - Card surface
//
// Paper-grounded and flat. The site draws no shadows anywhere — depth is not
// part of the language — so a "card" here is just paper with a hairline. The
// `shadow` parameter is kept so the ~dozen existing call sites still compile,
// but it no longer draws anything; passing `shadow: true` is a no-op rather
// than a lie about the surface.

extension View {
    /// Paper card: hairline border, near-square, no shadow.
    func bpCard(
        radius: CGFloat = Radius.md,
        fill: Color = BP.card,
        border: Color = BP.line,
        shadow: Bool = false
    ) -> some View {
        _ = shadow
        return self
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            )
    }

    /// Full-screen paper background.
    func bpPaperBackground() -> some View {
        self.background(BP.canvas.ignoresSafeArea())
    }

    /// A section separated by a rule rather than boxed into a card — the site's
    /// default way of grouping. Prefer this over `bpCard` for new surfaces.
    func bpRuledSection(top: Bool = true, bottom: Bool = false) -> some View {
        self
            .overlay(alignment: .top) { if top { BPDivider() } }
            .overlay(alignment: .bottom) { if bottom { BPDivider() } }
    }
}

// MARK: - BPCard
//
// (The app already declares a `Card` type elsewhere, so the redesign card is `BPCard`.)

struct BPCard<Content: View>: View {
    var padding: CGFloat = Space.l
    var radius: CGFloat = Radius.md
    var fill: Color = BP.card
    var border: Color = BP.line
    var shadow: Bool = false
    @ViewBuilder var content: () -> Content

    init(
        padding: CGFloat = Space.l,
        radius: CGFloat = Radius.md,
        fill: Color = BP.card,
        border: Color = BP.line,
        shadow: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.padding = padding
        self.radius = radius
        self.fill = fill
        self.border = border
        self.shadow = shadow
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .bpCard(radius: radius, fill: fill, border: border, shadow: shadow)
    }
}

// MARK: - Hairline divider

struct BPDivider: View {
    var color: Color = BP.line
    var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: 1)
    }
}

// MARK: - Evidence grid
//
// Faint registration grid used on the few dark surfaces (onboarding hero,
// dark balance card, viewfinder backdrop). Procedural so it stays crisp.

struct BPEvidenceGrid: View {
    var spacing: CGFloat = 26
    var lineColor: Color = BP.onInk.opacity(0.05)
    var lineWidth: CGFloat = 1

    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += spacing
            }
            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += spacing
            }
            context.stroke(path, with: .color(lineColor), lineWidth: lineWidth)
        }
        .allowsHitTesting(false)
    }
}
