import SwiftUI

// MARK: - Welcome hero (dark)
//
// The first screen a new capturer sees. Full-bleed ink with a faint evidence
// grid; wordmark top-left, editorial Newsreader headline and the onboarding
// actions pinned to the bottom. Copy stays review-gated per the capturer copy
// positioning doc: quoted payouts appear only on eligible jobs, review decides
// payout eligibility, and there are no blanket "start earning" claims.

struct BPSignInView: View {
    /// Primary action: continue into the nearby-preview onboarding step.
    var onExplore: () -> Void
    /// Escape hatch for returning capturers: straight to sign-in.
    var onSignIn: () -> Void = {}

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
                Spacer(minLength: Space.xl)
                headline
                Spacer().frame(height: Space.xl)
                howItWorks
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
            Text("Capture real places.\nEarn on eligible jobs.")
                .font(.bpDisplay(30))
                .foregroundStyle(BP.onInk)
                .fixedSize(horizontal: false, vertical: true)
            Text("Robot and AI teams need walkthrough video of real places. Eligible capture jobs near you show a quoted payout up front — every capture goes through quality and rights review before any payout.")
                .font(.bpSans(BPType.body, .regular))
                .foregroundStyle(BP.onInk.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            BPNumberedStepRow(index: 1, text: "Find capture jobs and candidate spaces near you", onDark: true)
            BPNumberedStepRow(index: 2, text: "Walk the space and record a guided capture with your iPhone", onDark: true)
            BPNumberedStepRow(index: 3, text: "Quality and rights review decides payout eligibility", onDark: true)
        }
    }

    private var actions: some View {
        VStack(spacing: Space.s) {
            BPPrimaryButton(title: "See what's near me", systemImage: "location.fill", action: onExplore)
                .accessibilityIdentifier("onboarding_explore_button")
            Button("I already have an account", action: onSignIn)
                .buttonStyle(BPGhostButtonStyle(tint: BP.onInk, border: BP.onInk.opacity(0.25)))
                .accessibilityIdentifier("onboarding_sign_in_button")
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
    BPSignInView(onExplore: {}, onSignIn: {})
}
#endif
