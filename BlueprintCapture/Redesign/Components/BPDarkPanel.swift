import SwiftUI

// MARK: - BPDarkPanel
//
// The few sanctioned dark surfaces outside the viewfinder: the earnings balance
// card and the onboarding hero. Ink fill with a faint evidence grid; brass + mono
// readouts on top. (Screens stay paper; these are explicit dark *panels*.)

struct BPDarkPanel<Content: View>: View {
    var corner: CGFloat = Radius.md
    var padding: CGFloat = Space.l
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(
                ZStack {
                    BP.ink
                    BPEvidenceGrid(spacing: 22, lineColor: BP.onInk.opacity(0.06))
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(BP.graphite, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.10), radius: 10, x: 0, y: 4)
    }
}
