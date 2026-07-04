import SwiftUI

// MARK: - BPRootView
//
// The redesign's shipping root: 4 paper tabs under the custom tab bar, with the
// center brass capture FAB presenting the dark viewfinder flow as a full-screen
// cover. Paper everywhere; the cover is the only dark surface.

struct BPRootView: View {
    @StateObject private var coordinator = RedesignCoordinator()

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
        .tint(BP.brassDeep)
        .preferredColorScheme(.light)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch coordinator.selectedTab {
        case .home:     BPHomeTab()
        case .history:  BPHistoryView()
        case .earnings: BPEarningsView()
        case .profile:  BPProfileView()
        }
    }
}

#if DEBUG
#Preview {
    BPRootView()
}
#endif
