import Foundation

enum MapProvider: String {
    case appleSnapshot
    case googleStatic
}

enum AppConfig {
    static let mapProvider: MapProvider = .appleSnapshot
    static let pendingStartScanJobIdKey = "com.blueprint.pendingStartScanJobId"
    static let pendingNotificationRouteKey = "com.blueprint.pendingNotificationRoute"

    private static func plist(named name: String) -> [String: Any]? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "plist"),
              let data = try? Data(contentsOf: url) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }

    private static func secretsValue(_ keys: [String]) -> String? {
        let environment = ProcessInfo.processInfo.environment
        for key in keys {
            if let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
               value.isEmpty == false {
                return value
            }
        }

        for plistName in ["Secrets.local", "Secrets"] {
            guard let plist = plist(named: plistName) else { continue }
            for key in keys {
                if let value = (plist[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   value.isEmpty == false {
                    return value
                }
            }
        }

        return nil
    }

    private static func secretsPlist() -> [String: Any]? {
        plist(named: "Secrets.local") ?? plist(named: "Secrets")
    }

    static func streetViewAPIKey() -> String? {
        secretsValue(["STREET_VIEW_API_KEY"])
    }

    static func placesAPIKey() -> String? {
        secretsValue(["PLACES_API_KEY", "GOOGLE_PLACES_API_KEY"])
    }

    static func geminiAPIKey() -> String? {
        secretsValue(["GEMINI_API_KEY", "GOOGLE_AI_API_KEY", "GEMINI_MAPS_API_KEY"])
    }

    static func perplexityAPIKey() -> String? {
        secretsValue(["PERPLEXITY_API_KEY"])
    }

    // MARK: - Stripe
    static func stripePublishableKey() -> String? {
        secretsValue(["STRIPE_PUBLISHABLE_KEY"])
    }

    static func stripeAccountID() -> String? {
        secretsValue(["STRIPE_ACCOUNT_ID"])
    }

    static func backendBaseURL() -> URL? {
        if let string = secretsValue(["BACKEND_BASE_URL"]) { return URL(string: string) }
        return nil
    }


    static func stripeOnboardingURL() -> URL? {
        if let string = secretsValue(["STRIPE_ONBOARDING_URL"]) { return URL(string: string) }
        return nil
    }

    static func stripePayoutScheduleURL() -> URL? {
        if let string = secretsValue(["STRIPE_PAYOUT_SCHEDULE_URL"]) { return URL(string: string) }
        return nil
    }

    static func stripeInstantPayoutURL() -> URL? {
        if let string = secretsValue(["STRIPE_INSTANT_PAYOUT_URL"]) { return URL(string: string) }
        return nil
    }

    // MARK: - Reservation Guards
    static func maxReservationDriveMinutes() -> Int {
        if let plist = secretsPlist() {
            if let num = plist["MAX_RESERVATION_DRIVE_MINUTES"] as? NSNumber { return num.intValue }
            if let str = plist["MAX_RESERVATION_DRIVE_MINUTES"] as? String, let val = Int(str) { return val }
        }
        return 60
    }

    static func fallbackMaxReservationAirMiles() -> Double {
        if let plist = secretsPlist() {
            if let num = plist["FALLBACK_MAX_RESERVATION_AIR_MILES"] as? NSNumber { return num.doubleValue }
            if let str = plist["FALLBACK_MAX_RESERVATION_AIR_MILES"] as? String, let val = Double(str) { return val }
        }
        return 35.0
    }

    // MARK: - Testing Overrides
    static func allowOffsiteCheckIn() -> Bool {
        #if DEBUG
        return true
        #else
        if let plist = secretsPlist() {
            if let flag = plist["ALLOW_OFFSITE_CHECKIN"] as? Bool { return flag }
            if let str = plist["ALLOW_OFFSITE_CHECKIN"] as? String {
                return (str as NSString).boolValue
            }
        }
        return false
        #endif
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
