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
    /// Capture launch waiting on the per-capture rights acknowledgement (parity
    /// with Android's RightsAcknowledgementDialog — the only path into recording).
    @Published var pendingRightsLaunch: CaptureLaunch?

    /// Real capturer identity bound from Firebase Auth (+ creator profile when the
    /// backend is reachable). Empty strings mean "unknown" — screens render neutral
    /// copy instead of a fabricated name/city.
    @Published var capturerName: String = ""
    @Published var capturerEmail: String = ""
    @Published var capturerCity: String = ""
    /// Short, stable capturer reference derived from the Firebase uid (honest
    /// stand-in for the prototype's fake "Capturer #214").
    @Published var capturerReference: String = ""

    private var identityBound = false

    /// First name (or full fallback) for greetings; empty when unknown.
    var capturerFirstName: String {
        String(capturerName.split(separator: " ").first ?? "")
    }

    /// Re-reads identity from the local Firebase user. Kept as the pre-induction
    /// screens' entry point; equivalent to `applyLocalIdentity()`.
    func refreshIdentity() {
        applyLocalIdentity()
    }

    /// Every capture entry point (FAB, active card, task detail) funnels through
    /// here; recording only starts after the rights acknowledgement is confirmed.
    func startCapture(task: BPCaptureTask? = nil, seed: SpaceReviewSeed? = nil) {
        pendingRightsLaunch = CaptureLaunch(task: task, seed: seed)
    }

    func confirmRightsAndLaunch() {
        guard let pending = pendingRightsLaunch else { return }
        pendingRightsLaunch = nil
        BPCapturerStateStore.shared.recordCaptureRightsAcknowledgement()
        captureLaunch = pending
    }

    func cancelPendingCapture() {
        pendingRightsLaunch = nil
    }

    func finishCapture() {
        captureLaunch = nil
        selectedTab = .home
    }

    // MARK: Identity binding

    /// Binds identity from the signed-in Firebase user immediately, then upgrades
    /// the display name from the creator profile when the backend is configured.
    /// Safe to call repeatedly (e.g. on auth-state changes).
    func bindIdentity() async {
        applyLocalIdentity()
        guard !identityBound else { return }
        identityBound = true

        // Backend profile is optional — beta builds without a backend keep the
        // Firebase-derived name. Never block the UI on this.
        if let profile = try? await APIService.shared.fetchUserProfile() {
            let trimmed = profile.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                capturerName = Self.firstName(from: trimmed)
            }
        }
    }

    /// Re-reads identity from the local Firebase user (no network).
    func applyLocalIdentity() {
        guard FirebaseApp.app() != nil, let user = Auth.auth().currentUser, !user.isAnonymous else {
            capturerName = ""
            capturerEmail = ""
            capturerReference = ""
            identityBound = false
            return
        }
        capturerEmail = user.email ?? ""
        capturerReference = Self.reference(fromUserId: user.uid)
        let displayName = (user.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !displayName.isEmpty {
            capturerName = Self.firstName(from: displayName)
        } else if let email = user.email, let local = email.split(separator: "@").first, !local.isEmpty {
            capturerName = String(local)
        }
    }

    /// City is resolved by whichever surface learns it first (onboarding city step,
    /// Home discovery geocode). Keeps the last non-empty value.
    func updateCity(_ city: String) {
        let trimmed = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != capturerCity else { return }
        capturerCity = trimmed
    }

    static func firstName(from fullName: String) -> String {
        fullName.split(separator: " ").first.map(String.init) ?? fullName
    }

    /// Uppercased short suffix of the uid — stable, non-identifying, mono-friendly.
    static func reference(fromUserId uid: String) -> String {
        let suffix = String(uid.suffix(4)).uppercased()
        return suffix.isEmpty ? "" : "CAPTURER · \(suffix)"
    }
}

// MARK: - Tab-bar inset metric

enum BPMetrics {
    /// Bottom space a scrolling tab screen reserves so content clears the tab bar.
    static let tabBarClearance: CGFloat = 84
}
