import SwiftUI

// MARK: - BPAppRoot
//
// The redesign is the shipping UI. Unauthenticated capturers see the dark sign-in
// hero; once onboarded they land on the paper tab experience. The onboarding flag
// reuses the app's existing AppStorage key so state is shared with the rest of the app.

struct BPAppRoot: View {
    @AppStorage("com.blueprint.isOnboarded") private var isOnboarded: Bool = false
    @State private var guestBootstrapState = UserDeviceService.currentGuestBootstrapState()

    var body: some View {
        Group {
            if isOnboarded {
                BPRootView()
            } else {
                BPSignInView(
                    onContinue: { isOnboarded = true },
                    onHasAccount: { isOnboarded = true }
                )
            }
        }
        .safeAreaInset(edge: .top) {
            guestBootstrapBanner
        }
        .onAppear {
            guestBootstrapState = UserDeviceService.currentGuestBootstrapState()
            UserDeviceService.ensureAnonymousFirebaseUserIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .FirebaseGuestBootstrapStateDidChange)) { _ in
            guestBootstrapState = UserDeviceService.currentGuestBootstrapState()
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
