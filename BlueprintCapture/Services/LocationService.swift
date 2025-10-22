import Foundation
import CoreLocation

protocol LocationServiceProtocol: AnyObject {
    var authorizationStatus: CLAuthorizationStatus { get }
    var latestLocation: CLLocation? { get }
    func requestWhenInUseAuthorization()
    func startUpdatingLocation()
    func stopUpdatingLocation()
    func setListener(_ listener: @escaping (CLLocation?) -> Void)
}

final class LocationService: NSObject, LocationServiceProtocol {
    private let manager: CLLocationManager
    private var listener: ((CLLocation?) -> Void)?
    private var lastUpdateAt: Date = .distantPast
    private let debounceInterval: TimeInterval = 5.0

    private(set) var latestLocation: CLLocation?

    init(manager: CLLocationManager = CLLocationManager()) {
        self.manager = manager
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 50
    }

    var authorizationStatus: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    func setListener(_ listener: @escaping (CLLocation?) -> Void) {
        self.listener = listener
    }

    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func startUpdatingLocation() {
        manager.startUpdatingLocation()
    }

    func stopUpdatingLocation() {
        manager.stopUpdatingLocation()
    }
}

extension LocationService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        // If now authorized, request a one-shot location to prime latestLocation quickly
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.requestLocation()
        }
        // Notify listener (may be nil on first grant)
        listener?(latestLocation)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let now = Date()
        // Debounce rapid updates
        if now.timeIntervalSince(lastUpdateAt) < debounceInterval { return }
        lastUpdateAt = now
        latestLocation = location
        listener?(location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        listener?(latestLocation)
    }
}


