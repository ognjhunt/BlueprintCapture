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
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
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
        Messaging.messaging().apnsToken = deviceToken
        UserDefaults.standard.set(deviceToken.hexString, forKey: "apnsToken")
        Task {
            await syncCurrentDevice()
        }
    }

    func didFailToRegisterForRemoteNotifications(_ error: Error) {
        print("⚠️ [Notifications] APNs registration failed: \(error.localizedDescription)")
    }

    func syncNotificationPreferences() async {
        do {
            try await APIService.shared.updateNotificationPreferences(NotificationPreferencesStore.shared.preferences)
        } catch {
            print("⚠️ [Notifications] Failed to sync preferences: \(error.localizedDescription)")
        }
    }

    func syncCurrentDevice() async {
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
            print("⚠️ [Notifications] Failed to sync device registration: \(error.localizedDescription)")
        }
    }

    private func notificationSettings() async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
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
