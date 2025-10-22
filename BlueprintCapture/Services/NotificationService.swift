import Foundation
import UserNotifications
import CoreLocation

protocol NotificationServiceProtocol: AnyObject {
    func requestAuthorizationIfNeeded() async
    func scheduleProximityNotifications(for targets: [Target], maxRegions: Int, radiusMeters: CLLocationDistance)
    func clearProximityNotifications()
}

final class NotificationService: NSObject, NotificationServiceProtocol {
    private let center: UNUserNotificationCenter
    private let authorizationAskedKey = "notifications.authorization.asked"
    private let proximityPrefix = "proximity_"
    static let categoryId = "TARGET_PROXIMITY"
    static let actionCheckIn = "ACTION_CHECK_IN"
    static let actionDirections = "ACTION_DIRECTIONS"

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

    func scheduleProximityNotifications(for targets: [Target], maxRegions: Int = 10, radiusMeters: CLLocationDistance = 150) {
        // iOS limits total monitored regions per app (~20). Keep ours conservative.
        let subset = Array(targets.prefix(maxRegions))
        clearProximityNotifications()

        for target in subset {
            let content = UNMutableNotificationContent()
            content.title = "You're near a Blueprint location"
            content.body = "You can check in at \(target.displayName). Start mapping to earn now."
            content.sound = .default
            content.categoryIdentifier = Self.categoryId
            content.userInfo = [
                "targetId": target.id,
                "title": target.displayName,
                "lat": target.lat,
                "lng": target.lng
            ]

            let centerCoord = CLLocationCoordinate2D(latitude: target.lat, longitude: target.lng)
            let region = CLCircularRegion(center: centerCoord, radius: max(50, radiusMeters), identifier: proximityPrefix + target.id)
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
}


