import Foundation

enum MapProvider: String {
    case appleSnapshot
    case googleStatic
}

enum AppConfig {
    static let mapProvider: MapProvider = .appleSnapshot
    static let pendingStartScanJobIdKey = "com.blueprint.pendingStartScanJobId"
    static let pendingNotificationRouteKey = "com.blueprint.pendingNotificationRoute"

    static func backendBaseURL() -> URL? {
        RuntimeConfig.current.backendBaseURL
    }

    static func hasBackendBaseURL() -> Bool {
        backendBaseURL() != nil
    }

    static func demandBackendBaseURL() -> URL? {
        RuntimeConfig.current.demandBackendBaseURL
    }

    static func hasDemandBackendBaseURL() -> Bool {
        demandBackendBaseURL() != nil
    }

    static func allowMockJobsFallback() -> Bool {
        RuntimeConfig.current.allowMockJobsFallback
    }

    static func enableInternalTestSpace() -> Bool {
        RuntimeConfig.current.enableInternalTestSpace
    }

    static func enableOpenCaptureHere() -> Bool {
        RuntimeConfig.current.enableOpenCaptureHere
    }

    static func enableRemoteNotifications() -> Bool {
        RuntimeConfig.current.enableRemoteNotifications
    }

    static func mainWebsiteURL() -> URL? {
        RuntimeConfig.current.websiteURL
    }

    static func helpCenterURL() -> URL? {
        RuntimeConfig.current.helpCenterURL
    }

    static func bugReportURL() -> URL? {
        RuntimeConfig.current.bugReportURL
    }

    static func termsOfServiceURL() -> URL? {
        RuntimeConfig.current.termsOfServiceURL
    }

    static func privacyPolicyURL() -> URL? {
        RuntimeConfig.current.privacyPolicyURL
    }

    static func capturePolicyURL() -> URL? {
        RuntimeConfig.current.capturePolicyURL
    }

    static func accountDeletionURL() -> URL? {
        RuntimeConfig.current.accountDeletionURL
    }

    static func supportEmailAddress() -> String? {
        RuntimeConfig.current.supportEmailAddress
    }

    static func supportEmailURL(subject: String? = nil) -> URL? {
        guard let address = supportEmailAddress(),
              address.isEmpty == false else {
            return nil
        }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        if let subject, subject.isEmpty == false {
            components.queryItems = [URLQueryItem(name: "subject", value: subject)]
        }
        return components.url
    }

    // MARK: - Reservation Guards
    static func maxReservationDriveMinutes() -> Int {
        RuntimeConfig.current.maxReservationDriveMinutes
    }

    static func fallbackMaxReservationAirMiles() -> Double {
        RuntimeConfig.current.fallbackMaxReservationAirMiles
    }

    // MARK: - Testing Overrides
    static func allowOffsiteCheckIn() -> Bool {
        RuntimeConfig.current.allowOffsiteCheckIn
    }
}

extension Notification.Name {
    static let blueprintNotificationAction = Notification.Name("Blueprint.NotificationAction")
    static let AuthStateDidChange = Notification.Name("Blueprint.AuthStateDidChange")
    static let FirebaseGuestBootstrapStateDidChange = Notification.Name("Blueprint.FirebaseGuestBootstrapStateDidChange")
    static let blueprintOpenTab = Notification.Name("Blueprint.OpenTab")
    static let blueprintOpenScanJobDetail = Notification.Name("Blueprint.OpenScanJobDetail")
    static let blueprintOpenCaptureDetail = Notification.Name("Blueprint.OpenCaptureDetail")
    static let blueprintOpenPayoutEntry = Notification.Name("Blueprint.OpenPayoutEntry")
    static let blueprintOpenPayoutSetup = Notification.Name("Blueprint.OpenPayoutSetup")
}
