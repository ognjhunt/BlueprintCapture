import SwiftUI

// MARK: - BPAppRoot
//
// The redesign is the shipping UI. Unauthenticated capturers see the value-first
// onboarding flow (dark hero → read-only nearby preview → auth); the
// capture/upload path only unlocks once a real (non-anonymous) Firebase account
// exists. The anonymous-guest bootstrap still runs so pre-auth state (guest
// session banner, discovery reads, the onboarding nearby preview) works, but
// `BPRootView` is gated on `UserDeviceService.hasRegisteredAccount()` — see
// beta-launch-audit CAP-02.

struct BPAppRoot: View {
    @State private var guestBootstrapState = UserDeviceService.currentGuestBootstrapState()
    @State private var hasRegisteredAccount = UserDeviceService.hasRegisteredAccount()
    @State private var showingAuth = false
    @State private var authMode: AuthViewModel.Mode = .signIn

    var body: some View {
        Group {
            if hasRegisteredAccount {
                BPRootView()
            } else {
                BPOnboardingFlowView { request in
                    authMode = (request == .signIn) ? .signIn : .signUp
                    showingAuth = true
                }
            }
        }
        .safeAreaInset(edge: .top) {
            guestBootstrapBanner
        }
        // CAP-02: present the real email + Google auth flow. AuthView dismisses
        // itself and posts `.AuthStateDidChange` on success; we re-read the
        // registered-account state so the app advances to the paper tabs only for a
        // non-anonymous Firebase user. The onboarding flow picks which mode the
        // sheet opens in (create-account vs sign-in) so returning capturers skip
        // the sign-up form.
        .sheet(isPresented: $showingAuth) {
            AuthView(initialMode: authMode)
        }
        .onAppear {
            guestBootstrapState = UserDeviceService.currentGuestBootstrapState()
            hasRegisteredAccount = UserDeviceService.hasRegisteredAccount()
            UserDeviceService.ensureAnonymousFirebaseUserIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .FirebaseGuestBootstrapStateDidChange)) { _ in
            guestBootstrapState = UserDeviceService.currentGuestBootstrapState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .AuthStateDidChange)) { _ in
            hasRegisteredAccount = UserDeviceService.hasRegisteredAccount()
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
