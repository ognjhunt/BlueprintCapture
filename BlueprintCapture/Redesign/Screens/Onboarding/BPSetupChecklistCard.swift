import SwiftUI
import Combine
import AVFoundation
import UserNotifications

// MARK: - BPSetupChecklistCard
//
// Home's "finish your kit" card. Tracks the real, verifiable setup state —
// rights certification (local store), camera + notification permissions
// (system), and payout onboarding (Stripe account state, only when the
// provider is live for this cohort). Disappears once everything is done.

@MainActor
final class BPSetupChecklistModel: ObservableObject {
    struct Item: Identifiable, Equatable {
        enum Kind: Equatable { case rights, camera, notifications, payout }
        let kind: Kind
        let title: String
        let detail: String
        var done: Bool
        var id: String { title }
    }

    @Published private(set) var items: [Item] = []
    @Published private(set) var loaded = false

    private let payoutReady = RuntimeConfig.current.payoutProviderReady

    var doneCount: Int { items.filter(\.done).count }
    var allDone: Bool { loaded && items.allSatisfy(\.done) }

    func refresh() async {
        var next: [Item] = []

        let rightsCertified = BPCapturerStateStore.shared.isRightsCertified
        next.append(Item(
            kind: .rights,
            title: "Certify rights & privacy",
            detail: "Required before assignments treat you as rights-trained.",
            done: rightsCertified
        ))

        let cameraGranted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        next.append(Item(
            kind: .camera,
            title: "Allow camera",
            detail: "The instrument can't record without it.",
            done: cameraGranted
        ))

        let notifSettings = await UNUserNotificationCenter.current().notificationSettings()
        let notifGranted: Bool
        switch notifSettings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: notifGranted = true
        default: notifGranted = false
        }
        next.append(Item(
            kind: .notifications,
            title: "Turn on alerts",
            detail: "Nearby assignments, review results, payout updates.",
            done: notifGranted
        ))

        // Payout row only exists when the provider is live for this cohort —
        // never implies payout readiness the backend hasn't granted.
        if payoutReady {
            let accountState = try? await StripeConnectService.shared.fetchAccountState()
            next.append(Item(
                kind: .payout,
                title: "Set up payouts",
                detail: "Connect the account accepted captures pay into.",
                done: accountState?.onboardingComplete == true
            ))
        }

        items = next
        loaded = true
    }
}

struct BPSetupChecklistCard: View {
    @Environment(\.openURL) private var openURL
    @ObservedObject var model: BPSetupChecklistModel
    @State private var showingRights = false
    @State private var showingPayoutSetup = false

    var body: some View {
        if model.loaded && !model.allDone {
            VStack(alignment: .leading, spacing: Space.m) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Finish your kit")
                        .font(.bpSans(BPType.bodyL, .semibold))
                        .foregroundStyle(BP.textStrong)
                    Spacer()
                    Text("\(model.doneCount)/\(model.items.count)")
                        .font(.bpMono(BPType.caption))
                        .foregroundStyle(BP.textMuted)
                }

                progressBar

                VStack(spacing: 0) {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { idx, item in
                        checklistRow(item)
                        if idx < model.items.count - 1 { BPDivider(color: BP.lineSoft) }
                    }
                }
            }
            .padding(Space.l)
            .bpCard()
            .sheet(isPresented: $showingRights, onDismiss: refresh) {
                NavigationStack { BPRightsTrainingView() }
            }
            .sheet(isPresented: $showingPayoutSetup, onDismiss: refresh) {
                StripeOnboardingView()
            }
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(BP.sunken)
                Rectangle()
                    .fill(BP.brass)
                    .frame(width: geo.size.width * fraction)
            }
        }
        .frame(height: 3)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
        .accessibilityHidden(true)
    }

    private var fraction: CGFloat {
        guard !model.items.isEmpty else { return 0 }
        return CGFloat(model.doneCount) / CGFloat(model.items.count)
    }

    private func checklistRow(_ item: BPSetupChecklistModel.Item) -> some View {
        Button {
            act(on: item)
        } label: {
            HStack(alignment: .top, spacing: Space.m) {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(item.done ? BP.proofFg : BP.textFaint)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.bpSans(BPType.body, .semibold))
                        .foregroundStyle(item.done ? BP.textMuted : BP.textStrong)
                        .strikethrough(item.done, color: BP.textFaint)
                    if !item.done {
                        Text(item.detail)
                            .font(.bpSans(BPType.caption, .regular))
                            .foregroundStyle(BP.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: Space.s)
                if !item.done {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(BP.textFaint)
                        .padding(.top, 3)
                }
            }
            .padding(.vertical, Space.s + 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(item.done)
        .accessibilityLabel("\(item.title): \(item.done ? "done" : "not done")")
    }

    private func act(on item: BPSetupChecklistModel.Item) {
        switch item.kind {
        case .rights:
            showingRights = true
        case .camera:
            if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
                AVCaptureDevice.requestAccess(for: .video) { _ in
                    Task { @MainActor in refresh() }
                }
            } else if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
        case .notifications:
            Task {
                let center = UNUserNotificationCenter.current()
                let settings = await center.notificationSettings()
                if settings.authorizationStatus == .notDetermined {
                    _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
                    refresh()
                } else if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
        case .payout:
            showingPayoutSetup = true
        }
    }

    private func refresh() {
        Task { await model.refresh() }
    }
}
