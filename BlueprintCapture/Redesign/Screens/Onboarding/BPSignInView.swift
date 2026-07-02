import SwiftUI

// MARK: - Sign in (dark)
//
// The onboarding hero. Full-bleed ink with a faint evidence grid; wordmark top-left,
// editorial Newsreader headline and the sign-in actions pinned to the bottom.

struct BPSignInView: View {
    var onContinue: () -> Void
    var onHasAccount: () -> Void = {}

    var body: some View {
        ZStack {
            BP.ink.ignoresSafeArea()
            BPEvidenceGrid(spacing: 28, lineColor: BP.onInk.opacity(0.05))
                .ignoresSafeArea()
            LinearGradient(
                colors: [.clear, BP.ink.opacity(0.7), BP.ink],
                startPoint: .center, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                BPWordmark(onDark: true)
                Spacer(minLength: Space.xxl)
                headline
                Spacer().frame(height: Space.l)
                chips
                Spacer().frame(height: Space.xl)
                actions
                fineprint
            }
            .padding(.horizontal, Space.l)
            .padding(.top, Space.l)
            .padding(.bottom, Space.l)
        }
        .preferredColorScheme(.dark)
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Capture real sites.\nTrack truthful evidence.")
                .font(.bpDisplay(30))
                .foregroundStyle(BP.onInk)
                .fixedSize(horizontal: false, vertical: true)
            Text("Blueprint is a field instrument for recording privacy-aware walkthroughs of real facilities — not a consumer camera.")
                .font(.bpSans(BPType.body, .regular))
                .foregroundStyle(BP.onInk.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var chips: some View {
        HStack(spacing: Space.s) {
            ForEach(["Field instrument", "Privacy-aware", "Review-gated"], id: \.self) { label in
                Text(label)
                    .font(.bpSans(BPType.caption, .semibold))
                    .foregroundStyle(BP.onInk)
                    .padding(.horizontal, Space.m)
                    .padding(.vertical, Space.s)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .strokeBorder(BP.brass.opacity(0.55), lineWidth: 1)
                    )
            }
        }
    }

    private var actions: some View {
        VStack(spacing: Space.s) {
            BPPrimaryButton(title: "Continue with email", action: onContinue)
            Button("I already have an account", action: onHasAccount)
                .buttonStyle(BPGhostButtonStyle(tint: BP.onInk, border: BP.onInk.opacity(0.25)))
        }
    }

    private var fineprint: some View {
        Text("By continuing you confirm you only capture sites where the operator has granted permission, and you accept Blueprint's privacy terms.")
            .font(.bpSans(BPType.caption, .regular))
            .foregroundStyle(BP.onInk.opacity(0.5))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, Space.m)
    }
}

#if DEBUG
#Preview {
    BPSignInView(onContinue: {})
}
#endif
