import Foundation
import Combine
import SwiftUI

enum NotificationPreferenceKey: String, CaseIterable, Identifiable {
    case nearbyJobs = "nearbyJobs"
    case reservations = "reservations"
    case captureStatus = "captureStatus"
    case payouts = "payouts"
    case account = "account"

    var id: String { rawValue }

    fileprivate var defaultsKey: String {
        "notifications.preference.\(rawValue)"
    }

    var title: String {
        switch self {
        case .nearbyJobs: return "Nearby job alerts"
        case .reservations: return "Reservation alerts"
        case .captureStatus: return "Capture status"
        case .payouts: return "Payout updates"
        case .account: return "Account alerts"
        }
    }

    var subtitle: String {
        switch self {
        case .nearbyJobs: return "Nearby approved jobs that enter your geofence"
        case .reservations: return "Reservation reminders and expiry updates"
        case .captureStatus: return "Approved, needs fix, rejected, and paid captures"
        case .payouts: return "Scheduled, sent, and failed payout events"
        case .account: return "Payout method and account action required alerts"
        }
    }

    var isEnabledByDefault: Bool { true }
}

struct NotificationPreferences: Codable, Equatable {
    var nearbyJobs: Bool = true
    var reservations: Bool = true
    var captureStatus: Bool = true
    var payouts: Bool = true
    var account: Bool = true

    static let `default` = NotificationPreferences()

    enum CodingKeys: String, CodingKey {
        case nearbyJobs = "nearby_jobs"
        case reservations
        case captureStatus = "capture_status"
        case payouts
        case account
    }

    func isEnabled(_ key: NotificationPreferenceKey) -> Bool {
        switch key {
        case .nearbyJobs: return nearbyJobs
        case .reservations: return reservations
        case .captureStatus: return captureStatus
        case .payouts: return payouts
        case .account: return account
        }
    }

    mutating func set(_ key: NotificationPreferenceKey, enabled: Bool) {
        switch key {
        case .nearbyJobs: nearbyJobs = enabled
        case .reservations: reservations = enabled
        case .captureStatus: captureStatus = enabled
        case .payouts: payouts = enabled
        case .account: account = enabled
        }
    }
}

@MainActor
final class NotificationPreferencesStore: ObservableObject {
    static let shared = NotificationPreferencesStore()

    @Published private(set) var preferences: NotificationPreferences

    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.preferences = Self.load(from: defaults)
    }

    func isEnabled(_ key: NotificationPreferenceKey) -> Bool {
        preferences.isEnabled(key)
    }

    func binding(for key: NotificationPreferenceKey) -> Binding<Bool> {
        Binding(
            get: { self.preferences.isEnabled(key) },
            set: { newValue in
                self.set(key, enabled: newValue)
            }
        )
    }

    func set(_ key: NotificationPreferenceKey, enabled: Bool) {
        guard preferences.isEnabled(key) != enabled else { return }
        preferences.set(key, enabled: enabled)
        persist()

        Task {
            await PushNotificationManager.shared.syncNotificationPreferences()
        }
    }

    func refreshFromBackendIfPossible() async {
        guard AppConfig.hasBackendBaseURL() else {
            print("ℹ️ [Notifications] Skipping preference refresh because BLUEPRINT_BACKEND_BASE_URL is not configured")
            return
        }
        do {
            guard let remote = try await APIService.shared.fetchNotificationPreferences() else { return }
            preferences = remote
            persist()
        } catch {
            let message: String
            if let apiError = error as? APIService.APIError {
                message = apiError.errorDescription ?? String(describing: apiError)
            } else {
                message = error.localizedDescription
            }
            SessionEventManager.shared.logError(
                errorCode: "notification_sync_failed",
                metadata: [
                    "operation": "refresh preferences",
                    "message": message
                ]
            )
            print("⚠️ [Notifications] Failed to refresh preferences: \(message)")
        }
    }

    private func persist() {
        for key in NotificationPreferenceKey.allCases {
            defaults.set(preferences.isEnabled(key), forKey: key.defaultsKey)
        }
    }

    private static func load(from defaults: UserDefaults) -> NotificationPreferences {
        var preferences = NotificationPreferences.default
        for key in NotificationPreferenceKey.allCases {
            if defaults.object(forKey: key.defaultsKey) == nil {
                preferences.set(key, enabled: key.isEnabledByDefault)
            } else {
                preferences.set(key, enabled: defaults.bool(forKey: key.defaultsKey))
            }
        }
        return preferences
    }
}
