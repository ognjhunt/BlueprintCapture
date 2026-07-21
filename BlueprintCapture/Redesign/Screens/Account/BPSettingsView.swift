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
