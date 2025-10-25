import Foundation

enum MapProvider: String {
    case appleSnapshot
    case googleStatic
}

enum AppConfig {
    static let mapProvider: MapProvider = .appleSnapshot

    private static func secretsPlist() -> [String: Any]? {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }

    static func streetViewAPIKey() -> String? {
        secretsPlist()? ["STREET_VIEW_API_KEY"] as? String
    }

    static func placesAPIKey() -> String? {
        if let plist = secretsPlist() {
            return plist["PLACES_API_KEY"] as? String ?? plist["GOOGLE_PLACES_API_KEY"] as? String
        }
        return nil
    }

    static func geminiAPIKey() -> String? {
        if let plist = secretsPlist() {
            return plist["GEMINI_API_KEY"] as? String ?? plist["GOOGLE_AI_API_KEY"] as? String ?? plist["GEMINI_MAPS_API_KEY"] as? String
        }
        return nil
    }

    // MARK: - Stripe
    static func stripePublishableKey() -> String? {
        secretsPlist()? ["STRIPE_PUBLISHABLE_KEY"] as? String
    }

    static func stripeAccountID() -> String? {
        secretsPlist()? ["STRIPE_ACCOUNT_ID"] as? String
    }

    static func backendBaseURL() -> URL? {
        if let string = secretsPlist()? ["BACKEND_BASE_URL"] as? String { return URL(string: string) }
        return nil
    }


    static func stripeOnboardingURL() -> URL? {
        if let string = secretsPlist()? ["STRIPE_ONBOARDING_URL"] as? String { return URL(string: string) }
        return nil
    }

    static func stripePayoutScheduleURL() -> URL? {
        if let string = secretsPlist()? ["STRIPE_PAYOUT_SCHEDULE_URL"] as? String { return URL(string: string) }
        return nil
    }

    static func stripeInstantPayoutURL() -> URL? {
        if let string = secretsPlist()? ["STRIPE_INSTANT_PAYOUT_URL"] as? String { return URL(string: string) }
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
}

extension Notification.Name {
    static let blueprintNotificationAction = Notification.Name("Blueprint.NotificationAction")
    static let AuthStateDidChange = Notification.Name("Blueprint.AuthStateDidChange")
}


