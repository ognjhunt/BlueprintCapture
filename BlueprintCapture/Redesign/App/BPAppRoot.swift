import SwiftUI

// MARK: - BPAppRoot
//
// The redesign is the shipping UI. Unauthenticated capturers see the dark sign-in
// hero; the capture/upload path only unlocks once a real (non-anonymous) Firebase
// account exists. The anonymous-guest bootstrap still runs so pre-auth state (guest
// session banner, discovery reads) works, but `BPRootView` is gated on
// `UserDeviceService.hasRegisteredAccount()` — see beta-launch-audit CAP-02.
//
// First-run induction: a freshly registered capturer walks the BPOnboardingFlow
// (how it works → launch city → permissions → rights certification → payouts)
// exactly once; the Home setup checklist covers anything skipped.

struct BPAppRoot: View {
    @State private var guestBootstrapState = UserDeviceService.currentGuestBootstrapState()
    @State private var hasRegisteredAccount = UserDeviceService.hasRegisteredAccount()
    @State private var showingAuth = false
    @StateObject private var coordinator = RedesignCoordinator()
    @ObservedObject private var capturerState = BPCapturerStateStore.shared

    /// DEBUG-only visual verification escape: launch with
    /// BLUEPRINT_DEBUG_FORCE_BP_SURFACE=onboarding|tabs to render that surface
    /// without a signed-in account (simulator screenshot walkthroughs). Never
    /// active in release builds.
    private var debugForcedSurface: String? {
        #if DEBUG
        ProcessInfo.processInfo.environment["BLUEPRINT_DEBUG_FORCE_BP_SURFACE"]
        #else
        nil
        #endif
    }

    /// "onboarding-3" → step at raw index 3 (rights). Defaults to welcome.
    private static func debugOnboardingStep(from value: String) -> BPOnboardingStateMachine.Step {
        guard let dash = value.firstIndex(of: "-"),
              let raw = Int(value[value.index(after: dash)...]),
              let step = BPOnboardingStateMachine.Step(rawValue: raw) else { return .welcome }
        return step
    }

    /// "tabs-earnings" → earnings tab. Defaults to home.
    private static func debugTab(from value: String) -> BPTab {
        switch value.split(separator: "-").last.map(String.init) {
        case "history": return .history
        case "earnings": return .earnings
        case "profile": return .profile
        default: return .home
        }
    }

    var body: some View {
        Group {
            if let forced = debugForcedSurface, forced.hasPrefix("onboarding") {
                BPOnboardingFlow(initialStep: Self.debugOnboardingStep(from: forced))
                    .environmentObject(coordinator)
            } else if let forced = debugForcedSurface, forced.hasPrefix("tabs") {
                BPRootView()
                    .environmentObject(coordinator)
                    .onAppear { coordinator.selectedTab = Self.debugTab(from: forced) }
            } else if hasRegisteredAccount {
                if capturerState.hasCompletedOnboarding {
                    BPRootView()
                        .environmentObject(coordinator)
                } else {
                    BPOnboardingFlow()
                        .environmentObject(coordinator)
                }
            } else {
                BPSignInView(
                    onContinue: { showingAuth = true },
                    onHasAccount: { showingAuth = true }
                )
            }
        }
        .safeAreaInset(edge: .top) {
            guestBootstrapBanner
        }
        // CAP-02: present the real email + Google auth flow. AuthView dismisses
        // itself and posts `.AuthStateDidChange` on success; we re-read the
        // registered-account state so the app advances to the paper tabs only for a
        // non-anonymous Firebase user.
        .sheet(isPresented: $showingAuth) {
            AuthView()
        }
        .onAppear {
            guestBootstrapState = UserDeviceService.currentGuestBootstrapState()
            hasRegisteredAccount = UserDeviceService.hasRegisteredAccount()
            UserDeviceService.ensureAnonymousFirebaseUserIfNeeded()
        }
        .task(id: hasRegisteredAccount) {
            if hasRegisteredAccount {
                await coordinator.bindIdentity()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .FirebaseGuestBootstrapStateDidChange)) { _ in
            guestBootstrapState = UserDeviceService.currentGuestBootstrapState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .AuthStateDidChange)) { _ in
            hasRegisteredAccount = UserDeviceService.hasRegisteredAccount()
            coordinator.applyLocalIdentity()
            if hasRegisteredAccount {
                showingAuth = false
            }
        }
    }

    @ViewBuilder
    private var guestBootstrapBanner: some View {
        switch guestBootstrapState {
        case .idle, .ready:
            EmptyView()
        case .bootstrapping:
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Starting guest session")
                    .font(.footnote.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        case .failed(let message):
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(3)
                Spacer()
                Button("Retry") {
                    UserDeviceService.ensureAnonymousFirebaseUserIfNeeded()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.orange.opacity(0.12))
        }
    }
}

#if DEBUG
#Preview {
    BPAppRoot()
}
#endif
