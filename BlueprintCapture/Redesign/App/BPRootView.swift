import SwiftUI

// MARK: - BPRootView
//
// The redesign's shipping root: 4 paper tabs under the custom tab bar, with the
// center brass capture FAB presenting the dark viewfinder flow as a full-screen
// cover. Paper everywhere; the cover is the only dark surface.

struct BPRootView: View {
    @EnvironmentObject private var coordinator: RedesignCoordinator
    @EnvironmentObject private var alertsManager: NearbyAlertsManager

    var body: some View {
        ZStack {
            BP.canvas.ignoresSafeArea()

            // Each tab root attaches the tab bar via safeAreaInset so it hides on
            // pushed detail screens (which own their bottom bars).
            tabContent
                .environmentObject(coordinator)
        }
        // CAP-01: the center capture FAB and job "Continue capture" launch the REAL
        // capture engine (AnywhereCaptureFlowView → CaptureFlowViewModel →
        // CaptureSessionView) which records a real video + ARKit bundle and enqueues
        // it via CaptureUploadService with the reserved capture_job_id (from the seed)
        // and the CAP-03 creatorId. The old sample-data BPCaptureFlow is retired from
        // the shipping path.
        .fullScreenCover(item: $coordinator.captureLaunch) { launch in
            AnywhereCaptureFlowView(seed: launch.seed)
                .onDisappear { coordinator.finishCapture() }
        }
        // Capture-time rights gate (parity with Android's
        // RightsAcknowledgementDialog): recording never starts without an explicit
        // per-capture confirmation. `startCapture` parks the launch here.
        .alert(
            "Review capture rights",
            isPresented: Binding(
                get: { coordinator.pendingRightsLaunch != nil },
                set: { if !$0 { coordinator.cancelPendingCapture() } }
            )
        ) {
            Button("I confirm") { coordinator.confirmRightsAndLaunch() }
            Button("Cancel", role: .cancel) { coordinator.cancelPendingCapture() }
        } message: {
            Text("Only continue if you have permission to capture this space, will avoid restricted or private areas, and understand quality, privacy, and rights review may still block downstream use.")
        }
        // Notification deep links: these were previously consumed only by the
        // retired legacy screens, so every push tap was a no-op in the
        // shipping UI. Route them to the matching redesign tab.
        .onReceive(NotificationCenter.default.publisher(for: .blueprintOpenTab)) { note in
            switch note.userInfo?["tab"] as? String {
            case "scan": coordinator.selectedTab = .home
            case "wallet": coordinator.selectedTab = .earnings
            default: break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .blueprintOpenScanJobDetail)) { _ in
            coordinator.selectedTab = .home
        }
        .onReceive(NotificationCenter.default.publisher(for: .blueprintOpenCaptureDetail)) { _ in
            coordinator.selectedTab = .history
        }
        .onReceive(NotificationCenter.default.publisher(for: .blueprintOpenPayoutEntry)) { _ in
            coordinator.selectedTab = .earnings
        }
        .onReceive(NotificationCenter.default.publisher(for: .blueprintOpenPayoutSetup)) { _ in
            coordinator.selectedTab = .earnings
        }
        .tint(BP.brassDeep)
        .preferredColorScheme(.light)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch coordinator.selectedTab {
        case .home:     BPHomeTab(alertsManager: alertsManager)
        case .history:  BPHistoryView()
        case .earnings: BPEarningsView()
        case .profile:  BPProfileView()
        }
    }
}

#if DEBUG
#Preview {
    BPRootView()
        .environmentObject(NearbyAlertsManager())
        .environmentObject(RedesignCoordinator())
}
#endif
