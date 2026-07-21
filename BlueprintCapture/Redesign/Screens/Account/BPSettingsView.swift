import SwiftUI
import ARKit
import CoreLocation
import UIKit

// MARK: - Settings (NavBar "Settings")
//
// Every control here is real: alert toggles persist through
// NotificationPreferencesStore (backend-synced), and device/privacy rows report
// actual system state. CAP-09 precedent: dead toggles that configure nothing are
// false capability claims — the old depth/auto-upload/face-blur toggles were
// removed for exactly that reason. New capture behaviors get a toggle only once
// the capture path actually consults it.

struct BPSettingsView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var preferences: NotificationPreferencesStore

    @State private var locationStatusLabel = BPSettingsView.currentLocationStatus()
    @State private var showingDeleteConfirmation = false
    @State private var isDeletingAccount = false
    @State private var deleteErrorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            BPNavBar("Settings")
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    group("Alerts") {
                        let keys = NotificationPreferenceKey.allCases
                        ForEach(Array(keys.enumerated()), id: \.element.id) { idx, key in
                            toggleRow(key.title, key.subtitle, preferences.binding(for: key))
                            if idx < keys.count - 1 { BPDivider(color: BP.lineSoft) }
                        }
                        BPDivider(color: BP.lineSoft)
                        actionRow(
                            icon: "bell.badge",
                            title: "Notification settings",
                            subtitle: "Manage system-level alert permission in iOS Settings."
                        ) {
                            openSystemNotificationSettings()
                        }
                    }

                    group("Capture device") {
                        statusRow(
                            "Depth capture",
                            Self.lidarAvailable
                                ? "LiDAR depth records with every capture on this device."
                                : "This device has no LiDAR — captures record video and poses only.",
                            chip: Self.lidarAvailable
                                ? BPChip(label: "LiDAR", signal: .proof)
                                : BPChip(label: "No LiDAR", signal: .neutral)
                        )
                    }

                    group("Privacy") {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        } label: {
                            statusRow(
                                "Location access",
                                "Used to find nearby assignments and anchor evidence to the site. Managed in iOS Settings.",
                                chip: locationChip,
                                showsChevron: true
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    group("Legal & policies") {
                        linkRows
                    }

                    group("Help") {
                        linkRow("Beta capturer guide", "What to expect, review states, payout expectations, and support escalation.", systemImage: "list.bullet.rectangle") {
                            openURL(AppConfig.betaCapturerGuideURL())
                        }
                        BPDivider(color: BP.lineSoft)
                        linkRow("Contact support", AppConfig.effectiveSupportEmailAddress(), systemImage: "questionmark.circle") {
                            if let url = AppConfig.supportEmailURL(subject: "Blueprint Capture Support") {
                                openURL(url)
                            }
                        }
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
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            locationStatusLabel = Self.currentLocationStatus()
        }
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

    // MARK: Real system state

    static var lidarAvailable: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }

    static func currentLocationStatus() -> String {
        let manager = CLLocationManager()
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return manager.accuracyAuthorization == .fullAccuracy ? "On · precise" : "On · approximate"
        case .notDetermined:
            return "Not set"
        case .denied, .restricted:
            return "Off"
        @unknown default:
            return "Unknown"
        }
    }

    private var locationChip: BPChip {
        switch locationStatusLabel {
        case "On · precise": return BPChip(label: locationStatusLabel, signal: .proof)
        case "On · approximate": return BPChip(label: locationStatusLabel, signal: .caution)
        case "Off": return BPChip(label: locationStatusLabel, signal: .caution)
        default: return BPChip(label: locationStatusLabel, signal: .neutral)
        }
    }

    // MARK: Row builders

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

    private func toggleRow(_ title: String, _ subtitle: String, _ isOn: Binding<Bool>) -> some View {
        HStack(spacing: Space.m) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.bpSans(BPType.body, .semibold))
                    .foregroundStyle(BP.textStrong)
                Text(subtitle)
                    .font(.bpSans(BPType.caption, .regular))
                    .foregroundStyle(BP.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.m)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(BP.brass)
                .accessibilityLabel(title)
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
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

    private func statusRow(
        _ title: String,
        _ subtitle: String,
        chip: BPChip,
        showsChevron: Bool = false
    ) -> some View {
        HStack(spacing: Space.m) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.bpSans(BPType.body, .semibold))
                    .foregroundStyle(BP.textStrong)
                Text(subtitle)
                    .font(.bpSans(BPType.caption, .regular))
                    .foregroundStyle(BP.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.m)
            BPStatusChip(chip.label, signal: chip.signal)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(BP.textFaint)
            }
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func linkRow(
        _ title: String,
        _ subtitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Space.m) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(BP.textMuted)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.bpSans(BPType.body, .semibold))
                        .foregroundStyle(BP.textStrong)
                    Text(subtitle)
                        .font(.bpSans(BPType.caption, .regular))
                        .foregroundStyle(BP.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Space.m)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(BP.textFaint)
            }
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.m)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        BPSettingsView()
            .environmentObject(NotificationPreferencesStore.shared)
    }
}
#endif
