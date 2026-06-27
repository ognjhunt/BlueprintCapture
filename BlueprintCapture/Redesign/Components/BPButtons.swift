import SwiftUI

// MARK: - Brass primary button
//
// The "next step" on every screen. Brass fill, ink label, square chrome (8pt),
// quick mechanical press. No glow.

struct BPPrimaryButtonStyle: ButtonStyle {
    var enabled: Bool = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.bpSans(BPType.body, .semibold))
            .foregroundStyle(BP.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(enabled ? BP.brass : BP.sunken)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(BP.brassDeep.opacity(enabled ? 0.45 : 0), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Ghost / secondary button
//
// Transparent with a hairline border, ink label. Used for the "or" action.

struct BPGhostButtonStyle: ButtonStyle {
    var tint: Color = BP.textStrong
    var border: Color = BP.lineStrong
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.bpSans(BPType.body, .semibold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Brass outline chip button (onboarding feature chips)

struct BPOutlineChipStyle: ButtonStyle {
    var onDark: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.bpSans(BPType.caption, .semibold))
            .foregroundStyle(onDark ? BP.onInk : BP.textStrong)
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.s)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(BP.brass.opacity(onDark ? 0.55 : 0.7), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: - Convenience views

/// Full-width brass primary action.
struct BPPrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s) {
                Text(title)
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .regular))
                }
            }
        }
        .buttonStyle(BPPrimaryButtonStyle(enabled: enabled))
        .disabled(!enabled)
    }
}

/// Full-width ghost action.
struct BPGhostButton: View {
    let title: String
    var tint: Color = BP.textStrong
    var border: Color = BP.lineStrong
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(BPGhostButtonStyle(tint: tint, border: border))
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 16) {
        BPPrimaryButton(title: "Accept & start capture", action: {})
        BPGhostButton(title: "Recapture far end", action: {})
        BPGhostButton(title: "Sign out", tint: BP.blockFg, border: BP.blockBd, action: {})
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .bpPaperBackground()
}
#endif
