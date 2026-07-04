import SwiftUI
import Combine

// MARK: - RedesignCoordinator
//
// Owns tab selection and the capture full-screen presentation so both the center
// capture FAB and the in-flow "Accept & start capture" buttons launch the same
// viewfinder cover.

struct CaptureLaunch: Identifiable {
    let id = UUID()
    var task: BPCaptureTask?
    /// Real capture-job seed for a reserved/claimed job. When present, the redesign
    /// presents the real `AnywhereCaptureFlowView(seed:)` so recording + upload run
    /// against the reserved `capture_job_id` (CAP-01/CAP-04). Nil for an open capture
    /// launched from the FAB with no reservation.
    var seed: SpaceReviewSeed?
}

@MainActor
final class RedesignCoordinator: ObservableObject {
    @Published var selectedTab: BPTab = .home
    @Published var captureLaunch: CaptureLaunch?

    /// Real capturer identity, bound from auth where available.
    @Published var capturerName: String = BPSample.capturerName
    @Published var capturerCity: String = BPSample.capturerCity

    func startCapture(task: BPCaptureTask? = nil, seed: SpaceReviewSeed? = nil) {
        captureLaunch = CaptureLaunch(task: task, seed: seed)
    }

    func finishCapture() {
        captureLaunch = nil
        selectedTab = .home
    }
}

// MARK: - Tab-bar inset metric

enum BPMetrics {
    /// Bottom space a scrolling tab screen reserves so content clears the tab bar.
    static let tabBarClearance: CGFloat = 84
}
