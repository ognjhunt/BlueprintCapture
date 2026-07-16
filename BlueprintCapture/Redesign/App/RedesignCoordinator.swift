import SwiftUI
import Combine
import FirebaseAuth
import FirebaseCore

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

    /// Real capturer identity bound from the authenticated Firebase user.
    /// Empty when unknown — screens show neutral fallbacks, never sample data.
    @Published var capturerName: String = ""
    @Published var capturerEmail: String = ""

    private var authObserver: NSObjectProtocol?

    init() {
        refreshIdentity()
        authObserver = NotificationCenter.default.addObserver(
            forName: .AuthStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshIdentity() }
        }
    }

    deinit {
        if let authObserver {
            NotificationCenter.default.removeObserver(authObserver)
        }
    }

    /// Reads identity from the signed-in Firebase user. Anonymous/guest
    /// sessions get no name — the UI must not present a persona that does
    /// not exist.
    func refreshIdentity() {
        guard FirebaseApp.app() != nil, let user = Auth.auth().currentUser, !user.isAnonymous else {
            capturerName = ""
            capturerEmail = ""
            return
        }
        let displayName = user.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let email = user.email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        capturerName = displayName.isEmpty ? String(email.split(separator: "@").first ?? "") : displayName
        capturerEmail = email
    }

    /// First name (or full fallback) for greetings; empty when unknown.
    var capturerFirstName: String {
        String(capturerName.split(separator: " ").first ?? "")
    }

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
