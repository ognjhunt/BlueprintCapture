import Foundation
import Combine
import UIKit
import UserNotifications
import FirebaseMessaging

struct NotificationDeviceRegistration: Codable {
    let creatorId: String
    let platform: String
    let fcmToken: String
    let authorizationStatus: String
    let appVersion: String
    let lastSeenAt: Date

    enum CodingKeys: String, CodingKey {
        case creatorId = "creator_id"
        case platform
        case fcmToken = "fcm_token"
        case authorizationStatus = "authorization_status"
        case appVersion = "app_version"
        case lastSeenAt = "last_seen_at"
    }
}

@MainActor
final class PushNotificationManager: NSObject, ObservableObject {
    static let shared = PushNotificationManager()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var fcmToken: String = ""

    private let center = UNUserNotificationCenter.current()
    private var didConfigure = false
    private var hasLoggedMissingBackendBaseURL = false
    private var hasLoggedRemoteNotificationsDisabled = false

    override private init() {
        super.init()
        NotificationCenter.default.addObserver(
            forName: .AuthStateDidChange,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                await self.refreshNotificationSettings()
                await self.syncCurrentDevice()
                await NotificationPreferencesStore.shared.refreshFromBackendIfPossible()
            }
        }
    }

    func configure() {
        guard !didConfigure else { return }
        didConfigure = true

        guard remoteNotificationsEnabled else {
            logRemoteNotificationsDisabledIfNeeded()
            Task {
                await refreshNotificationSettings()
                await syncCurrentDevice()
                await NotificationPreferencesStore.shared.refreshFromBackendIfPossible()
            }
            return
        }

        Messaging.messaging().delegate = self
        fcmToken = UserDefaults.standard.string(forKey: "fcmToken") ?? ""

        Task {
            await refreshNotificationSettings()
            if authorizationStatus == .authorized || authorizationStatus == .provisional || authorizationStatus == .ephemeral {
                UIApplication.shared.registerForRemoteNotifications()
            }
            await syncCurrentDevice()
            await NotificationPreferencesStore.shared.refreshFromBackendIfPossible()
        }
    }

    func requestAuthorizationIfNeeded() async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            UserDefaults.standard.set(true, forKey: "notifications.authorization.asked")
            await refreshNotificationSettings()
            if granted && remoteNotificationsEnabled {
                UIApplication.shared.registerForRemoteNotifications()
            } else if granted {
                logRemoteNotificationsDisabledIfNeeded()
            }
            await syncCurrentDevice()
        } catch {
            print("⚠️ [Notifications] Authorization request failed: \(error.localizedDescription)")
        }
    }

    func refreshNotificationSettings() async {
        let settings = await notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    func didRegisterForRemoteNotifications(deviceToken: Data) {
        guard remoteNotificationsEnabled else { return }
        Messaging.messaging().apnsToken = deviceToken
        UserDefaults.standard.set(deviceToken.hexString, forKey: "apnsToken")
        print("✅ [Notifications] APNs registration succeeded")
        Task {
            await syncCurrentDevice()
        }
    }

    func didFailToRegisterForRemoteNotifications(_ error: Error) {
        guard remoteNotificationsEnabled else { return }
        print("⚠️ [Notifications] APNs registration failed: \(error.localizedDescription)")
    }

    func syncNotificationPreferences() async {
        guard canReachNotificationBackend(operation: "sync preferences") else { return }
        do {
            try await APIService.shared.updateNotificationPreferences(NotificationPreferencesStore.shared.preferences)
        } catch {
            logNotificationFailure(operation: "sync preferences", error: error)
        }
    }

    func syncCurrentDevice() async {
        guard canReachNotificationBackend(operation: "sync device registration") else { return }
        let creatorId = UserDeviceService.resolvedUserId()
        guard !creatorId.isEmpty else { return }

        do {
            try await APIService.shared.registerNotificationDevice(
                NotificationDeviceRegistration(
                    creatorId: creatorId,
                    platform: "iOS",
                    fcmToken: fcmToken,
                    authorizationStatus: authorizationStatus.serverValue,
                    appVersion: Self.appVersion,
                    lastSeenAt: Date()
                )
            )
        } catch {
            logNotificationFailure(operation: "sync device registration", error: error)
        }
    }

    private func canReachNotificationBackend(operation: String) -> Bool {
        guard AppConfig.hasBackendBaseURL() else {
            if !hasLoggedMissingBackendBaseURL {
                hasLoggedMissingBackendBaseURL = true
                print("ℹ️ [Notifications] Skipping notification backend calls because BLUEPRINT_BACKEND_BASE_URL is not configured for this build")
            } else {
                print("ℹ️ [Notifications] Skipping \(operation) because BLUEPRINT_BACKEND_BASE_URL is not configured")
            }
            return false
        }
        return true
    }

    private func notificationSettings() async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
    }

    private var remoteNotificationsEnabled: Bool {
        AppConfig.enableRemoteNotifications()
    }

    private func logRemoteNotificationsDisabledIfNeeded() {
        guard !hasLoggedRemoteNotificationsDisabled else { return }
        hasLoggedRemoteNotificationsDisabled = true
        print("ℹ️ [Notifications] Remote push registration is disabled for this build")
    }

    private func logNotificationFailure(operation: String, error: Error) {
        let message: String
        if let apiError = error as? APIService.APIError {
            message = apiError.errorDescription ?? String(describing: apiError)
        } else {
            message = error.localizedDescription
        }
        SessionEventManager.shared.logError(
            errorCode: "notification_sync_failed",
            metadata: [
                "operation": operation,
                "message": message
            ]
        )
        print("⚠️ [Notifications] Failed to \(operation): \(message)")
    }

    private static var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}

extension PushNotificationManager: MessagingDelegate {
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        Task { @MainActor in
            self.fcmToken = token
            UserDefaults.standard.set(token, forKey: "fcmToken")
            await self.syncCurrentDevice()
        }
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

private extension UNAuthorizationStatus {
    var serverValue: String {
        switch self {
        case .notDetermined: return "not_determined"
        case .denied: return "denied"
        case .authorized: return "authorized"
        case .provisional: return "provisional"
        case .ephemeral: return "ephemeral"
        @unknown default: return "unknown"
        }
    }
}
