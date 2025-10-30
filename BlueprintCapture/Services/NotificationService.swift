import Foundation
import UserNotifications
import CoreLocation

struct ProximityNotificationTarget {
    let target: Target
    let distanceMeters: Double?
    let estimatedPayoutUsd: Int?
    let isReserved: Bool

    init(target: Target,
         distanceMeters: Double? = nil,
         estimatedPayoutUsd: Int? = nil,
         isReserved: Bool = false) {
        self.target = target
        self.distanceMeters = distanceMeters
        self.estimatedPayoutUsd = estimatedPayoutUsd
        self.isReserved = isReserved
    }
}

protocol NotificationServiceProtocol: AnyObject {
    func requestAuthorizationIfNeeded() async
    func scheduleProximityNotifications(for targets: [ProximityNotificationTarget], maxRegions: Int, radiusMeters: CLLocationDistance)
    func clearProximityNotifications()
    /// Schedules a one-shot local notification at the reservation expiry time.
    func scheduleReservationExpiryNotification(target: Target, at date: Date)
    /// Cancels a previously scheduled reservation-expiry notification for the given target.
    func cancelReservationExpiryNotification(for targetId: String)
}

final class NotificationService: NSObject, NotificationServiceProtocol {
    private let center: UNUserNotificationCenter
    private let authorizationAskedKey = "notifications.authorization.asked"
    private let proximityPrefix = "proximity_"
    private let expiryPrefix = "reservation_expiry_"
    static let categoryId = "TARGET_PROXIMITY"
    static let actionCheckIn = "ACTION_CHECK_IN"
    static let actionDirections = "ACTION_DIRECTIONS"
    private lazy var currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    override init() {
        self.center = UNUserNotificationCenter.current()
        super.init()
    }

    func requestAuthorizationIfNeeded() async {
        let alreadyAsked = UserDefaults.standard.bool(forKey: authorizationAskedKey)
        if !alreadyAsked {
            let options: UNAuthorizationOptions = [.alert, .sound, .badge]
            do {
                let granted = try await center.requestAuthorization(options: options)
                UserDefaults.standard.set(true, forKey: authorizationAskedKey)
                if !granted {
                    // No-op; user can enable later in Settings
                }
            } catch {
                // Ignore errors; user can enable later
            }
        }
    }

    func registerCategories() {
        let checkIn = UNNotificationAction(
            identifier: Self.actionCheckIn,
            title: "Check in",
            options: [.foreground]
        )
        let directions = UNNotificationAction(
            identifier: Self.actionDirections,
            title: "Get directions",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryId,
            actions: [checkIn, directions],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    func scheduleProximityNotifications(for targets: [ProximityNotificationTarget], maxRegions: Int = 10, radiusMeters: CLLocationDistance = 200) {
        // iOS limits total monitored regions per app (~20). Keep ours conservative.
        clearProximityNotifications()

        guard !targets.isEmpty else { return }

        let reserved = targets.filter { $0.isReserved }
        let sortedByDistance = targets.sorted {
            let lhs = $0.distanceMeters ?? .greatestFiniteMagnitude
            let rhs = $1.distanceMeters ?? .greatestFiniteMagnitude
            if lhs == rhs { return $0.target.id < $1.target.id }
            return lhs < rhs
        }

        var finalTargets: [ProximityNotificationTarget] = []
        var seen = Set<String>()

        for entry in reserved where !seen.contains(entry.target.id) {
            finalTargets.append(entry)
            seen.insert(entry.target.id)
        }

        for entry in sortedByDistance where finalTargets.count < maxRegions {
            guard !seen.contains(entry.target.id) else { continue }
            finalTargets.append(entry)
            seen.insert(entry.target.id)
        }

        let regionRadius = max(50, radiusMeters)

        for entry in finalTargets {
            let target = entry.target
            let content = UNMutableNotificationContent()
            if entry.isReserved {
                content.title = "Reserved location nearby"
            } else {
                content.title = "You're near a Blueprint location"
            }
            if let payout = entry.estimatedPayoutUsd,
               let formatted = currencyFormatter.string(from: NSNumber(value: payout)) {
                content.body = "\(target.displayName) needs scanning. Estimated payout \(formatted)."
            } else {
                content.body = "\(target.displayName) needs scanning. Start mapping to earn now."
            }
            content.sound = .default
            content.categoryIdentifier = Self.categoryId
            var userInfo: [String: Any] = [
                "targetId": target.id,
                "title": target.displayName,
                "lat": target.lat,
                "lng": target.lng
            ]
            if let payout = entry.estimatedPayoutUsd {
                userInfo["estimatedPayoutUsd"] = payout
            }
            content.userInfo = userInfo

            let centerCoord = CLLocationCoordinate2D(latitude: target.lat, longitude: target.lng)
            let region = CLCircularRegion(center: centerCoord, radius: regionRadius, identifier: proximityPrefix + target.id)
            region.notifyOnEntry = true
            region.notifyOnExit = false

            let trigger = UNLocationNotificationTrigger(region: region, repeats: false)
            let request = UNNotificationRequest(identifier: proximityPrefix + target.id, content: content, trigger: trigger)
            center.add(request)
        }
    }

    func clearProximityNotifications() {
        center.getPendingNotificationRequests { [weak self] requests in
            guard let self = self else { return }
            let ids = requests.map { $0.identifier }.filter { $0.hasPrefix(self.proximityPrefix) }
            if !ids.isEmpty {
                self.center.removePendingNotificationRequests(withIdentifiers: ids)
            }
        }
    }

    // MARK: - Reservation Expiry Notifications

    func scheduleReservationExpiryNotification(target: Target, at date: Date) {
        let seconds = max(1, Int(date.timeIntervalSinceNow))
        // If already scheduled for this target, cancel and reschedule to avoid duplicates
        cancelReservationExpiryNotification(for: target.id)

        let content = UNMutableNotificationContent()
        content.title = "Reservation expired"
        content.body = "We auto-cancelled your reservation at \(target.displayName) because mapping didn’t start within 1 hour."
        content.sound = .default
        content.userInfo = [
            "targetId": target.id,
            "title": target.displayName,
            "lat": target.lat,
            "lng": target.lng
        ]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false)
        let request = UNNotificationRequest(identifier: expiryPrefix + target.id, content: content, trigger: trigger)
        center.add(request)
    }

    func cancelReservationExpiryNotification(for targetId: String) {
        center.removePendingNotificationRequests(withIdentifiers: [expiryPrefix + targetId])
    }
}


