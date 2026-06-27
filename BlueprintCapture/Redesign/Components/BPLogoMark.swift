import SwiftUI

// MARK: - BPLogoMark (placeholder)
//
// Procedural brass registration mark standing in for the final logo. The handoff
// ships the logo as a placeholder; swap for the real mark when ready.

struct BPLogoMark: View {
    var size: CGFloat = 34
    var color: Color = BP.brass

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                .strokeBorder(color, lineWidth: 1.5)
            BPRegistrationCorners(color: color, length: size * 0.26, thickness: 1.5, inset: size * 0.16)
            Image(systemName: "camera.aperture")
                .font(.system(size: size * 0.5, weight: .regular))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Wordmark lockup

struct BPWordmark: View {
    var onDark: Bool = false
    var body: some View {
        HStack(spacing: Space.s) {
            BPLogoMark(size: 30)
            Text("Blueprint")
                .font(.bpSans(BPType.bodyL, .bold))
                .tracking(-0.3)
                .foregroundStyle(onDark ? BP.onInk : BP.textStrong)
            Text("CAPTURE")
                .font(.bpMono(10))
                .tracking(1.6)
                .foregroundStyle(BP.brass)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                        .strokeBorder(BP.brass.opacity(0.5), lineWidth: 1)
                )
        }
    }
}
