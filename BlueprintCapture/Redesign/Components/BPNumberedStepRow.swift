import SwiftUI

// MARK: - Numbered step row
//
// Brass-boxed mono numeral + body text. Shared by the onboarding hero's
// "how it works" list and the home tab's first-session earning explainer so the
// product's core three-step explanation stays visually and editorially in one
// shape.

struct BPNumberedStepRow: View {
    let index: Int
    let text: String
    var onDark: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: Space.m) {
            Text("\(index)")
                .font(.bpMono(BPType.caption))
                .foregroundStyle(onDark ? BP.brass : BP.brassDeep)
                .frame(width: 24, height: 24)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .strokeBorder(BP.brass.opacity(0.55), lineWidth: 1)
                )
            Text(text)
                .font(.bpSans(BPType.bodyS, onDark ? .medium : .regular))
                .foregroundStyle(onDark ? BP.onInk.opacity(0.85) : BP.textBody)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#if DEBUG
#Preview {
    VStack(alignment: .leading, spacing: Space.m) {
        BPNumberedStepRow(index: 1, text: "Find capture jobs and candidate spaces near you")
        BPNumberedStepRow(index: 2, text: "Walk the space and record a guided capture")
    }
    .padding()
    .bpPaperBackground()
}
#endif
