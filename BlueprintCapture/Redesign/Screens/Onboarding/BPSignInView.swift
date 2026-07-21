import SwiftUI

// MARK: - Sign in (dark)
//
// The onboarding hero. Full-bleed ink with a faint evidence grid; wordmark top-left,
// editorial Newsreader headline and the sign-in actions pinned to the bottom.

struct BPSignInView: View {
    @Environment(\.openURL) private var openURL
    @State private var captureConsentAcknowledged = false

    var onContinue: () -> Void
    var onHasAccount: () -> Void = {}
    var consentPolicy: CaptureLegalConsentPolicy = .current()

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
            consentAcknowledgement
            legalLinks
            BPPrimaryButton(
                title: "Continue with email",
                enabled: consentPolicy.canContinue(hasAcknowledged: captureConsentAcknowledged),
                action: onContinue
            )
            Button("I already have an account", action: onHasAccount)
                .buttonStyle(BPGhostButtonStyle(tint: BP.onInk, border: BP.onInk.opacity(0.25)))
        }
    }

    private var fineprint: some View {
        Group {
            if consentPolicy.hasRequiredLegalLinks {
                Text("You can review the legal links above before continuing. Existing accounts still confirm consent in the auth sheet before sign-in.")
            } else {
                Text(CaptureLegalConsentPolicy.missingLegalLinksMessage)
            }
        }
        .font(.bpSans(BPType.caption, .regular))
        .foregroundStyle(consentPolicy.hasRequiredLegalLinks ? BP.onInk.opacity(0.5) : BP.blockFg)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, Space.m)
    }

    private var consentAcknowledgement: some View {
        Button {
            captureConsentAcknowledged.toggle()
        } label: {
            HStack(alignment: .top, spacing: Space.s) {
                Image(systemName: captureConsentAcknowledged ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(captureConsentAcknowledged ? BP.brass : BP.onInk.opacity(0.45))
                Text(CaptureLegalConsentPolicy.acknowledgementText)
                    .font(.bpSans(BPType.caption, .regular))
                    .foregroundStyle(BP.onInk.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("captureLegalConsentAcknowledgement")
    }

    private var legalLinks: some View {
        HStack(spacing: Space.s) {
            ForEach(consentPolicy.requiredLinks, id: \.title) { link in
                Button(link.title) {
                    guard let url = link.url else { return }
                    openURL(url)
                }
                .font(.bpSans(BPType.caption, .semibold))
                .foregroundStyle(link.url == nil ? BP.onInk.opacity(0.35) : BP.onInk)
                .underline(link.url != nil)
                .disabled(link.url == nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
#Preview {
    BPSignInView(onContinue: {})
}
#endif
