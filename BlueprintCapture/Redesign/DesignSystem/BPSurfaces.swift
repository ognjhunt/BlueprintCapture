import SwiftUI

// MARK: - Card surface
//
// Paper-grounded: white fill, 1pt warm hairline, 8pt radius, low shadow — no glow.

extension View {
    /// White paper card: hairline border, small radius, low paper shadow.
    func bpCard(
        radius: CGFloat = Radius.md,
        fill: Color = BP.card,
        border: Color = BP.line,
        shadow: Bool = true
    ) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            )
            .shadow(color: shadow ? Color.black.opacity(0.06) : .clear, radius: shadow ? 10 : 0, x: 0, y: shadow ? 4 : 0)
    }

    /// Full-screen warm paper background.
    func bpPaperBackground() -> some View {
        self.background(BP.canvas.ignoresSafeArea())
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
    var shadow: Bool = true
    @ViewBuilder var content: () -> Content

    init(
        padding: CGFloat = Space.l,
        radius: CGFloat = Radius.md,
        fill: Color = BP.card,
        border: Color = BP.line,
        shadow: Bool = true,
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
