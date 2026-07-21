import SwiftUI
import UIKit

// MARK: - Notifications (NavBar "Notifications")
//
// Honest alerts surface: real system permission state, real persisted alert
// preferences (NotificationPreferencesStore, backend-synced), and an activity
// feed re-presented from real capture-history + payout-ledger events. No
// synthetic notifications.

struct BPNotificationsView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var preferences: NotificationPreferencesStore
    @StateObject private var activity = BPActivityModel()

    var body: some View {
        VStack(spacing: 0) {
            BPNavBar("Notifications")
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    if activity.notificationsAuthorized == false {
                        permissionCard
                    }
                    preferencesSection
                    activitySection
                }
                .padding(.horizontal, Space.l)
                .padding(.top, Space.l)
                .padding(.bottom, Space.xl)
            }
            .scrollIndicators(.hidden)
            .refreshable { await activity.load() }
        }
        .background(BP.canvas.ignoresSafeArea())
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
        .task { await activity.load() }
    }

    // MARK: Permission

    private var permissionCard: some View {
        BPCard {
            VStack(alignment: .leading, spacing: Space.m) {
                BPStatusChip("Alerts off", signal: .caution)
                Text("Notifications are off for Blueprint Capture")
                    .font(.bpSans(BPType.body, .semibold))
                    .foregroundStyle(BP.textStrong)
                Text("Nearby assignments, review results, and payout updates can't reach you. Turn alerts on in Settings.")
                    .font(.bpSans(BPType.caption, .regular))
                    .foregroundStyle(BP.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                BPGhostButton(title: "Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
        }
    }

    // MARK: Preferences (real, persisted, backend-synced)

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            BPEyebrow("Alert types")
            BPCard(padding: 0) {
                let keys = NotificationPreferenceKey.allCases
                ForEach(Array(keys.enumerated()), id: \.element.id) { idx, key in
                    HStack(alignment: .top, spacing: Space.m) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(key.title)
                                .font(.bpSans(BPType.body, .semibold))
                                .foregroundStyle(BP.textStrong)
                            Text(key.subtitle)
                                .font(.bpSans(BPType.caption, .regular))
                                .foregroundStyle(BP.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: Space.s)
                        Toggle("", isOn: preferences.binding(for: key))
                            .labelsHidden()
                            .tint(BP.brass)
                            .accessibilityLabel(key.title)
                    }
                    .padding(.horizontal, Space.l)
                    .padding(.vertical, Space.m)
                    if idx < keys.count - 1 { BPDivider(color: BP.lineSoft) }
                }
            }
        }
    }

    // MARK: Activity (real events only)

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            BPEyebrow("Recent activity")
            switch activity.phase {
            case .idle, .loading:
                BPCard {
                    HStack(spacing: Space.m) {
                        ProgressView().controlSize(.small)
                        Text("Syncing activity…")
                            .font(.bpSans(BPType.bodyS, .regular))
                            .foregroundStyle(BP.textMuted)
                    }
                }
            case .failed:
                BPCard {
                    Text("Activity sync is unavailable right now. Pull to refresh to try again.")
                        .font(.bpSans(BPType.caption, .regular))
                        .foregroundStyle(BP.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .loaded:
                if activity.events.isEmpty {
                    BPCard {
                        Text("Review results and payout events appear here once your first capture is uploaded.")
                            .font(.bpSans(BPType.caption, .regular))
                            .foregroundStyle(BP.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    VStack(spacing: Space.m) {
                        ForEach(activity.events.prefix(20)) { event in
                            row(event)
                        }
                    }
                }
            }
        }
    }

    private func row(_ event: BPActivityEvent) -> some View {
        HStack(alignment: .top, spacing: Space.m) {
            ZStack {
                Circle().fill(event.signal.bg)
                Image(systemName: event.icon)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(event.signal.fg)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.bpSans(BPType.body, .semibold))
                    .foregroundStyle(BP.textStrong)
                    .fixedSize(horizontal: false, vertical: true)
                Text(event.body)
                    .font(.bpSans(BPType.caption, .regular))
                    .foregroundStyle(BP.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s)
            Text(event.date.formatted(.relative(presentation: .named)))
                .font(.bpMono(BPType.micro))
                .foregroundStyle(BP.textFaint)
        }
        .padding(Space.l)
        .bpCard()
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        BPNotificationsView()
            .environmentObject(NotificationPreferencesStore.shared)
    }
}
#endif
