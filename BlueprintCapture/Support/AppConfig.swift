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
    static let blueprintOpenTab = Notification.Name("Blueprint.OpenTab")
    static let blueprintOpenScanJobDetail = Notification.Name("Blueprint.OpenScanJobDetail")
    static let blueprintOpenCaptureDetail = Notification.Name("Blueprint.OpenCaptureDetail")
    static let blueprintOpenPayoutEntry = Notification.Name("Blueprint.OpenPayoutEntry")
    static let blueprintOpenPayoutSetup = Notification.Name("Blueprint.OpenPayoutSetup")
}
