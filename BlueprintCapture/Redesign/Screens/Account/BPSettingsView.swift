import SwiftUI
import UIKit

// MARK: - Settings (NavBar "Settings")
//
// Every row here performs a real action. The previous version rendered seven
// local @State toggles ("Auto-upload on Wi-Fi", "Face-blur preview", "Precise
// location", …) that configured nothing — user-visible controls that imply
// behavior must be wired to a real store or removed (beta-launch-audit H-2,
// same rule as CAP-09 which removed the dead Meta smart-glasses toggle).

struct BPSettingsView: View {
    @Environment(\.openURL) private var openURL
    @State private var showingDeleteConfirmation = false
    @State private var isDeletingAccount = false
    @State private var deleteErrorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            BPNavBar("Settings")
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    group("Notifications") {
                        actionRow(
                            icon: "bell.badge",
                            title: "Notification settings",
                            subtitle: "Manage capture and assignment alerts in iOS Settings."
                        ) {
                            openSystemNotificationSettings()
                        }
                    }

                    group("Legal & policies") {
                        linkRows
                    }

                    group("Account") {
                        deleteAccountRow
                    }
                }
                .padding(.horizontal, Space.l)
                .padding(.top, Space.l)
                .padding(.bottom, Space.xl)
            }
            .scrollIndicators(.hidden)
        }
        .background(BP.canvas.ignoresSafeArea())
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
        .confirmationDialog(
            "Delete your account?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete account", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes your account and profile data. Uploaded capture evidence is retained per the capture policy.")
        }
        .alert(
            "Account deletion failed",
            isPresented: Binding(
                get: { deleteErrorMessage != nil },
                set: { if !$0 { deleteErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { deleteErrorMessage = nil }
        } message: {
            Text(deleteErrorMessage ?? "")
        }
    }

    // MARK: Rows

    @ViewBuilder
    private var linkRows: some View {
        let links: [(icon: String, title: String, url: URL?)] = [
            ("doc.text", "Terms of service", AppConfig.termsOfServiceURL()),
            ("hand.raised", "Privacy policy", AppConfig.privacyPolicyURL()),
            ("camera.badge.ellipsis", "Capture policy", AppConfig.capturePolicyURL()),
            ("questionmark.circle", "Help center", AppConfig.helpCenterURL())
        ]
        let available = links.filter { $0.url != nil }
        ForEach(Array(available.enumerated()), id: \.element.title) { idx, link in
            actionRow(icon: link.icon, title: link.title, subtitle: nil) {
                if let url = link.url { openURL(url) }
            }
            if idx < available.count - 1 { BPDivider(color: BP.lineSoft) }
        }
    }

    private var deleteAccountRow: some View {
        Button {
            showingDeleteConfirmation = true
        } label: {
            HStack(spacing: Space.m) {
                Image(systemName: "trash")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(BP.blockFg)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Delete account")
                        .font(.bpSans(BPType.body, .semibold))
                        .foregroundStyle(BP.blockFg)
                    Text("Permanently remove your account and profile data.")
                        .font(.bpSans(BPType.caption, .regular))
                        .foregroundStyle(BP.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Space.m)
                if isDeletingAccount {
                    ProgressView()
                }
            }
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.m)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDeletingAccount)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            BPEyebrow(title)
            BPCard(padding: 0) { content() }
        }
    }

    private func actionRow(
        icon: String,
        title: String,
        subtitle: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Space.m) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(BP.textMuted)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.bpSans(BPType.body, .semibold))
                        .foregroundStyle(BP.textStrong)
                    if let subtitle {
                        Text(subtitle)
                            .font(.bpSans(BPType.caption, .regular))
                            .foregroundStyle(BP.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: Space.m)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BP.textFaint)
            }
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.m)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    private func openSystemNotificationSettings() {
        let urlString: String
        if #available(iOS 16.0, *) {
            urlString = UIApplication.openNotificationSettingsURLString
        } else {
            urlString = UIApplication.openSettingsURLString
        }
        if let url = URL(string: urlString) {
            openURL(url)
        }
    }

    private func deleteAccount() async {
        guard UserDeviceService.hasRegisteredAccount() else {
            deleteErrorMessage = "No registered account to delete."
            return
        }
        isDeletingAccount = true
        defer { isDeletingAccount = false }

        let deleted = await withCheckedContinuation { continuation in
            FirestoreManager.deleteAccount { success in
                continuation.resume(returning: success)
            }
        }

        if deleted {
            UserDeviceService.ensureAnonymousFirebaseUserIfNeeded()
            NotificationCenter.default.post(name: .AuthStateDidChange, object: nil)
        } else if let fallback = AppConfig.accountDeletionURL() {
            // Recent-login requirement or network failure — hand off to the
            // hosted deletion flow rather than failing silently.
            deleteErrorMessage = "Couldn't delete in-app (you may need to sign in again). Opening the account deletion page."
            openURL(fallback)
        } else {
            deleteErrorMessage = "Couldn't delete your account. Sign in again and retry."
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack { BPSettingsView() }
}
#endif
