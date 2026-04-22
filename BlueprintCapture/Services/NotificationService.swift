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

struct ProximityScanJobTarget {
    let job: ScanJob
    let distanceMeters: Double?
    let isReserved: Bool

    init(job: ScanJob, distanceMeters: Double? = nil, isReserved: Bool = false) {
        self.job = job
        self.distanceMeters = distanceMeters
        self.isReserved = isReserved
    }
}

@MainActor
protocol NotificationServiceProtocol: AnyObject {
    func requestAuthorizationIfNeeded() async
    func scheduleProximityNotifications(for targets: [ProximityNotificationTarget], maxRegions: Int, radiusMeters: CLLocationDistance)
    func scheduleProximityNotifications(for jobs: [ProximityScanJobTarget], maxRegions: Int)
    func clearProximityNotifications()
    /// Schedules a one-shot local notification at the reservation expiry time.
    func scheduleReservationExpiryNotification(target: Target, at date: Date)
    /// Cancels a previously scheduled reservation-expiry notification for the given target.
    func cancelReservationExpiryNotification(for targetId: String)
}

@MainActor
final class NotificationService: NSObject, NotificationServiceProtocol {
    private let center: UNUserNotificationCenter
    private let proximityPrefix = "proximity_"
    private let reminderPrefix = "reservation_reminder_"
    private let expiryPrefix = "reservation_expiry_"
    static let categoryId = "SCAN_JOB_PROXIMITY"
    static let actionStartScan = "ACTION_START_SCAN"
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
        await PushNotificationManager.shared.requestAuthorizationIfNeeded()
    }

    func registerCategories() {
        let startScan = UNNotificationAction(
            identifier: Self.actionStartScan,
            title: "Start scan",
            options: [.foreground]
        )
        let directions = UNNotificationAction(
            identifier: Self.actionDirections,
            title: "Directions",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryId,
            actions: [startScan, directions],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    func scheduleProximityNotifications(for targets: [ProximityNotificationTarget], maxRegions: Int = 10, radiusMeters: CLLocationDistance = 200) {
        // iOS limits total monitored regions per app (~20). Keep ours conservative.
        clearProximityNotifications()
        guard NotificationPreferencesStore.shared.isEnabled(.nearbyJobs) else { return }

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
            let route = BlueprintRoute.scanJob(jobId: target.id)
            let content = UNMutableNotificationContent()
            if entry.isReserved {
                content.title = "Reserved scan job nearby"
            } else {
                content.title = "You're near a scan job"
            }
            if let payout = entry.estimatedPayoutUsd,
               let formatted = currencyFormatter.string(from: NSNumber(value: payout)) {
                content.body = "\(target.displayName). Estimated payout \(formatted)."
            } else {
                content.body = "\(target.displayName). Start scanning to earn."
            }
            content.sound = .default
            content.categoryIdentifier = Self.categoryId
            var metadata: [String: String] = [
                "targetId": target.id,
                "jobId": target.id,
                "lat": String(target.lat),
                "lng": String(target.lng)
            ]
            if let payout = entry.estimatedPayoutUsd {
                metadata["estimatedPayoutUsd"] = String(payout)
            }
            let identifier = proximityPrefix + target.id
            content.userInfo = BlueprintNotificationPayload(
                notificationId: identifier,
                type: entry.isReserved ? .reservedJobEntered : .nearbyJobEntered,
                entityType: .job,
                entityId: target.id,
                route: route.url.absoluteString,
                title: content.title,
                body: content.body,
                metadata: metadata
            ).userInfo

            let centerCoord = CLLocationCoordinate2D(latitude: target.lat, longitude: target.lng)
            let region = CLCircularRegion(center: centerCoord, radius: regionRadius, identifier: identifier)
            region.notifyOnEntry = true
            region.notifyOnExit = false

            let trigger = UNLocationNotificationTrigger(region: region, repeats: false)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            center.add(request)
        }
    }

    func scheduleProximityNotifications(for jobs: [ProximityScanJobTarget], maxRegions: Int = 10) {
        clearProximityNotifications()
        guard NotificationPreferencesStore.shared.isEnabled(.nearbyJobs) else { return }
        guard !jobs.isEmpty else { return }

        var final: [ProximityScanJobTarget] = []
        var seen = Set<String>()

        // Preserve the caller's ordering (which is already ranked for the feed),
        // while still prioritizing reserved jobs first.
        for entry in jobs where entry.isReserved {
            guard !seen.contains(entry.job.id) else { continue }
            final.append(entry)
            seen.insert(entry.job.id)
        }

        for entry in jobs where final.count < maxRegions {
            guard !seen.contains(entry.job.id) else { continue }
            final.append(entry)
            seen.insert(entry.job.id)
        }

        for entry in final {
            let job = entry.job
            let route = BlueprintRoute.scanJob(jobId: job.id)
            let content = UNMutableNotificationContent()
            content.title = entry.isReserved ? "Reserved scan job nearby" : "You're near a scan job"

            if let formatted = currencyFormatter.string(from: NSNumber(value: job.payoutDollars)) {
                content.body = "\(job.title). Estimated payout \(formatted)."
            } else {
                content.body = "\(job.title). Start scanning to earn."
            }

            content.sound = .default
            content.categoryIdentifier = Self.categoryId
            let identifier = proximityPrefix + job.id
            content.userInfo = BlueprintNotificationPayload(
                notificationId: identifier,
                type: entry.isReserved ? .reservedJobEntered : .nearbyJobEntered,
                entityType: .job,
                entityId: job.id,
                route: route.url.absoluteString,
                title: content.title,
                body: content.body,
                metadata: [
                    "jobId": job.id,
                    "lat": String(job.lat),
                    "lng": String(job.lng),
                    "estimatedPayoutUsd": String(job.payoutDollars)
                ]
            ).userInfo

            let centerCoord = CLLocationCoordinate2D(latitude: job.lat, longitude: job.lng)
            let radius = max(50, CLLocationDistance(job.alertRadiusM))
            let region = CLCircularRegion(center: centerCoord, radius: radius, identifier: identifier)
            region.notifyOnEntry = true
            region.notifyOnExit = false

            let trigger = UNLocationNotificationTrigger(region: region, repeats: false)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            center.add(request)
        }
    }

    func clearProximityNotifications() {
        let center = center
        let proximityPrefix = proximityPrefix
        center.getPendingNotificationRequests { requests in
            let ids = requests.map { $0.identifier }.filter { $0.hasPrefix(proximityPrefix) }
            if !ids.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: ids)
            }
        }
    }

    // MARK: - Reservation Expiry Notifications

    func scheduleReservationExpiryNotification(target: Target, at date: Date) {
        guard NotificationPreferencesStore.shared.isEnabled(.reservations) else {
            cancelReservationExpiryNotification(for: target.id)
            return
        }

        cancelReservationExpiryNotification(for: target.id)

        let route = BlueprintRoute.scanJob(jobId: target.id)
        let reminderDate = date.addingTimeInterval(-10 * 60)

        if reminderDate.timeIntervalSinceNow > 1 {
            let reminderContent = UNMutableNotificationContent()
            reminderContent.title = "Reservation ending soon"
            reminderContent.body = "Your reservation at \(target.displayName) expires in 10 minutes."
            reminderContent.sound = .default
            reminderContent.interruptionLevel = .timeSensitive
            reminderContent.userInfo = BlueprintNotificationPayload(
                notificationId: reminderPrefix + target.id,
                type: .reservationReminder,
                entityType: .job,
                entityId: target.id,
                route: route.url.absoluteString,
                title: reminderContent.title,
                body: reminderContent.body,
                metadata: [
                    "targetId": target.id,
                    "lat": String(target.lat),
                    "lng": String(target.lng)
                ]
            ).userInfo

            let reminderTrigger = UNTimeIntervalNotificationTrigger(
                timeInterval: reminderDate.timeIntervalSinceNow,
                repeats: false
            )
            let reminderRequest = UNNotificationRequest(
                identifier: reminderPrefix + target.id,
                content: reminderContent,
                trigger: reminderTrigger
            )
            center.add(reminderRequest)
        }

        let expiryContent = UNMutableNotificationContent()
        expiryContent.title = "Reservation expired"
        expiryContent.body = "We auto-cancelled your reservation at \(target.displayName) because mapping didn’t start within 1 hour."
        expiryContent.sound = .default
        expiryContent.userInfo = BlueprintNotificationPayload(
            notificationId: expiryPrefix + target.id,
            type: .reservationExpired,
            entityType: .job,
            entityId: target.id,
            route: route.url.absoluteString,
            title: expiryContent.title,
            body: expiryContent.body,
            metadata: [
                "targetId": target.id,
                "lat": String(target.lat),
                "lng": String(target.lng)
            ]
        ).userInfo

        let expiryTrigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, date.timeIntervalSinceNow),
            repeats: false
        )
        let expiryRequest = UNNotificationRequest(
            identifier: expiryPrefix + target.id,
            content: expiryContent,
            trigger: expiryTrigger
        )
        center.add(expiryRequest)
    }

    func cancelReservationExpiryNotification(for targetId: String) {
        center.removePendingNotificationRequests(withIdentifiers: [
            reminderPrefix + targetId,
            expiryPrefix + targetId
        ])
    }
}
