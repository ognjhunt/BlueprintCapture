import SwiftUI
import FirebaseAuth

enum BPAccountRoute: Hashable { case settings, rights }

// MARK: - Profile (tab: Profile)
//
// Identity comes from the authenticated Firebase user via RedesignCoordinator.
// No sample personas, fabricated stats, or unearned certification chips —
// capture-truth rules forbid presenting qualification/performance data that
// the backend has not actually produced.

struct BPProfileView: View {
    @EnvironmentObject private var coordinator: RedesignCoordinator
    @Environment(\.openURL) private var openURL
    @State private var showingSignOutConfirmation = false
    @State private var signOutErrorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    BPLargeTitle(eyebrow: "Account", title: "Profile")
                    identityCard
                    menuCard
                    BPGhostButton(title: "Sign out", tint: BP.blockFg, border: BP.blockBd) {
                        showingSignOutConfirmation = true
                    }
                }
                .padding(.horizontal, Space.l)
                .padding(.top, Space.s)
                .padding(.bottom, Space.l)
            }
            .scrollIndicators(.hidden)
            .background(BP.canvas.ignoresSafeArea())
            .navigationBarHidden(true)
            .bpTabBarOverlay(selection: $coordinator.selectedTab, onCapture: { coordinator.startCapture() })
            .navigationDestination(for: BPAccountRoute.self) { route in
                switch route {
                case .settings: BPSettingsView()
                case .rights: BPRightsTrainingView()
                }
            }
            .confirmationDialog(
                "Sign out of Blueprint Capture?",
                isPresented: $showingSignOutConfirmation,
                titleVisibility: .visible
            ) {
                Button("Sign out", role: .destructive) { signOut() }
                Button("Cancel", role: .cancel) {}
            }
            .alert(
                "Sign out failed",
                isPresented: Binding(
                    get: { signOutErrorMessage != nil },
                    set: { if !$0 { signOutErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { signOutErrorMessage = nil }
            } message: {
                Text(signOutErrorMessage ?? "")
            }
        }
    }

    private func signOut() {
        do {
            try Auth.auth().signOut()
            UserDeviceService.ensureAnonymousFirebaseUserIfNeeded()
            NotificationCenter.default.post(name: .AuthStateDidChange, object: nil)
            coordinator.refreshIdentity()
        } catch {
            signOutErrorMessage = error.localizedDescription
        }
    }

    private var identityCard: some View {
        BPCard {
            HStack(spacing: Space.l) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(BP.infoBg)
                    Text(initials)
                        .font(.bpSans(BPType.title, .bold))
                        .foregroundStyle(BP.infoFg)
                }
                .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(displayName)
                        .font(.bpSans(BPType.bodyL, .semibold))
                        .foregroundStyle(BP.textStrong)
                    if !coordinator.capturerEmail.isEmpty {
                        Text(coordinator.capturerEmail)
                            .font(.bpMono(BPType.caption))
                            .foregroundStyle(BP.textMuted)
                    }
                }
                Spacer(minLength: Space.s)
            }
        }
    }

    private var displayName: String {
        coordinator.capturerName.isEmpty ? "Capturer" : coordinator.capturerName
    }

    private var initials: String {
        let parts = displayName.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }

    private var menuCard: some View {
        BPCard(padding: 0) {
            NavigationLink(value: BPAccountRoute.rights) {
                menuRow(icon: "checkmark.shield", title: "Rights & privacy")
            }
            .buttonStyle(.plain)
            BPDivider(color: BP.lineSoft)

            NavigationLink(value: BPAccountRoute.settings) {
                menuRow(icon: "gearshape", title: "Settings")
            }
            .buttonStyle(.plain)

            if let helpURL = AppConfig.helpCenterURL() {
                BPDivider(color: BP.lineSoft)
                Button {
                    openURL(helpURL)
                } label: {
                    menuRow(icon: "questionmark.circle", title: "Help")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func menuRow(
        icon: String,
        title: String,
        trailingText: String? = nil,
        trailingChip: BPChip? = nil,
        showsChevron: Bool = true
    ) -> some View {
        HStack(spacing: Space.m) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(BP.textMuted)
                .frame(width: 24)
            Text(title)
                .font(.bpSans(BPType.body, .semibold))
                .foregroundStyle(BP.textStrong)
            Spacer(minLength: Space.s)
            if let trailingChip {
                BPStatusChip(trailingChip.label, signal: trailingChip.signal)
            }
            if let trailingText {
                Text(trailingText)
                    .font(.bpMono(BPType.caption))
                    .foregroundStyle(BP.textMuted)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(BP.textFaint)
            }
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .contentShape(Rectangle())
    }
}

#if DEBUG
#Preview {
    BPProfileView().environmentObject(RedesignCoordinator())
}
#endif
