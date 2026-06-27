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
}

@MainActor
final class RedesignCoordinator: ObservableObject {
    @Published var selectedTab: BPTab = .home
    @Published var captureLaunch: CaptureLaunch?

    /// Real capturer identity, bound from auth where available.
    @Published var capturerName: String = BPSample.capturerName
    @Published var capturerCity: String = BPSample.capturerCity

    func startCapture(task: BPCaptureTask? = nil) {
        captureLaunch = CaptureLaunch(task: task)
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
