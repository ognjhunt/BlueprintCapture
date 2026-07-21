import Foundation
import Combine

// MARK: - BPCapturerStateStore
//
// Persisted, device-local capturer setup state for the shipping BP experience:
// whether first-run onboarding finished and when rights & privacy training was
// last certified. This is advisory UX state (see AGENTS.md) — it never asserts
// backend qualification, payout readiness, or rights truth on its own.
//
// Deliberately NOT @MainActor: isolated deinit crashes libmalloc on the iOS 26
// simulator runtime when instances release off-executor (seen in unit tests).
// All UI mutation happens from main-thread call sites anyway.

final class BPCapturerStateStore: ObservableObject {
    static let shared = BPCapturerStateStore()

    enum Keys {
        static let onboardingCompletedAt = "com.blueprint.bp.onboarding.completedAt"
        static let rightsCertifiedAt = "com.blueprint.bp.rights.certifiedAt"
        static let captureRightsAcknowledgedAt = "com.blueprint.bp.rights.captureAcknowledgedAt"
    }

    /// Rights training recertifies yearly (SCREENS.md §12 "Recertify yearly").
    static let certificationValidityDays: Double = 365

    @Published private(set) var onboardingCompletedAt: Date?
    @Published private(set) var rightsCertifiedAt: Date?
    /// Last time the capturer confirmed the per-capture rights acknowledgement
    /// (parity with Android's RightsAcknowledgementDialog). Advisory record only.
    @Published private(set) var captureRightsAcknowledgedAt: Date?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        onboardingCompletedAt = Self.storedDate(defaults, Keys.onboardingCompletedAt)
        rightsCertifiedAt = Self.storedDate(defaults, Keys.rightsCertifiedAt)
        captureRightsAcknowledgedAt = Self.storedDate(defaults, Keys.captureRightsAcknowledgedAt)
    }

    var hasCompletedOnboarding: Bool { onboardingCompletedAt != nil }

    var isRightsCertified: Bool {
        guard let certifiedAt = rightsCertifiedAt else { return false }
        let expiry = certifiedAt.addingTimeInterval(Self.certificationValidityDays * 24 * 3600)
        return Date() < expiry
    }

    func completeOnboarding(at date: Date = Date()) {
        onboardingCompletedAt = date
        defaults.set(date.timeIntervalSince1970, forKey: Keys.onboardingCompletedAt)
    }

    func certifyRights(at date: Date = Date()) {
        rightsCertifiedAt = date
        defaults.set(date.timeIntervalSince1970, forKey: Keys.rightsCertifiedAt)
    }

    func recordCaptureRightsAcknowledgement(at date: Date = Date()) {
        captureRightsAcknowledgedAt = date
        defaults.set(date.timeIntervalSince1970, forKey: Keys.captureRightsAcknowledgedAt)
    }

    /// Testing/support hook.
    func reset() {
        onboardingCompletedAt = nil
        rightsCertifiedAt = nil
        captureRightsAcknowledgedAt = nil
        defaults.removeObject(forKey: Keys.onboardingCompletedAt)
        defaults.removeObject(forKey: Keys.rightsCertifiedAt)
        defaults.removeObject(forKey: Keys.captureRightsAcknowledgedAt)
    }

    private static func storedDate(_ defaults: UserDefaults, _ key: String) -> Date? {
        let raw = defaults.double(forKey: key)
        guard raw > 0 else { return nil }
        return Date(timeIntervalSince1970: raw)
    }
}
