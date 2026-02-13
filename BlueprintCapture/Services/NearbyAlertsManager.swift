import Foundation
import CoreLocation
import UserNotifications

/// Owns location authorization upgrades (When-In-Use -> Always) and proximity alert scheduling.
@MainActor
final class NearbyAlertsManager: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var notificationsGranted: Bool = false

    private let locationManager: CLLocationManager
    private let notificationService: NotificationServiceProtocol

    override init() {
        self.locationManager = CLLocationManager()
        self.notificationService = NotificationService()
        self.authorizationStatus = locationManager.authorizationStatus
        super.init()
        locationManager.delegate = self
        refreshNotificationStatus()
    }

    var isLocationAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    var isAlwaysAuthorized: Bool {
        authorizationStatus == .authorizedAlways
    }

    func requestWhenInUseAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }

    func requestAlwaysAuthorization() {
        // iOS will only show the Always prompt after When-In-Use has been granted at least once.
        locationManager.requestAlwaysAuthorization()
    }

    func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.notificationsGranted = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            }
        }
    }

    func scheduleNearbyAlerts(for jobs: [ScanJob], userLocation: CLLocation, maxRegions: Int = 10, reservedJobIds: Set<String> = []) {
        guard notificationsGranted else {
            notificationService.clearProximityNotifications()
            return
        }
        // Geofence-based notifications are only reliable when Always location is enabled.
        guard isAlwaysAuthorized else {
            notificationService.clearProximityNotifications()
            return
        }

        let targets = jobs.map { job in
            ProximityScanJobTarget(
                job: job,
                distanceMeters: job.distanceMeters(from: userLocation),
                isReserved: reservedJobIds.contains(job.id)
            )
        }
        notificationService.scheduleProximityNotifications(for: targets, maxRegions: maxRegions)
    }
}

extension NearbyAlertsManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        authorizationStatus = status
    }
}
