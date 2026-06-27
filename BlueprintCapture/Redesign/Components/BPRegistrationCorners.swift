import SwiftUI

// MARK: - BPRegistrationCorners
//
// Brass L-shaped registration marks framing a region. Used on the task capture-path
// hero and as the viewfinder framing overlay.

struct BPRegistrationCorners: View {
    var color: Color = BP.brass
    var length: CGFloat = 22
    var thickness: CGFloat = 2
    var inset: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                corner(at: .topLeading, w: w, h: h)
                corner(at: .topTrailing, w: w, h: h)
                corner(at: .bottomLeading, w: w, h: h)
                corner(at: .bottomTrailing, w: w, h: h)
            }
        }
        .allowsHitTesting(false)
    }

    private func corner(at alignment: Alignment, w: CGFloat, h: CGFloat) -> some View {
        let isTop = alignment.vertical == .top
        let isLeading = alignment.horizontal == .leading
        return Path { p in
            let x = isLeading ? inset : w - inset
            let y = isTop ? inset : h - inset
            let hx = isLeading ? x + length : x - length
            let vy = isTop ? y + length : y - length
            p.move(to: CGPoint(x: x, y: vy))
            p.addLine(to: CGPoint(x: x, y: y))
            p.addLine(to: CGPoint(x: hx, y: y))
        }
        .stroke(color, style: StrokeStyle(lineWidth: thickness, lineCap: .square, lineJoin: .miter))
    }
}
