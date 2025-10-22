import Foundation
import CoreLocation

enum LocationPermissionRequester {
    static func requestWhenInUse() async -> Bool {
        // If already determined, short-circuit
        let current = CLLocationManager().authorizationStatus
        switch current {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            break
        @unknown default:
            return false
        }

        // Ask and wait for the response via delegate
        return await withCheckedContinuation { continuation in
            let delegateProxy = AuthorizationDelegateProxy { status in
                let allowed = (status == .authorizedAlways || status == .authorizedWhenInUse)
                continuation.resume(returning: allowed)
            }
            delegateProxy.request()
        }
    }
}

private final class AuthorizationDelegateProxy: NSObject, CLLocationManagerDelegate {
    private let manager: CLLocationManager
    private let completion: (CLAuthorizationStatus) -> Void

    init(completion: @escaping (CLAuthorizationStatus) -> Void) {
        self.manager = CLLocationManager()
        self.completion = completion
        super.init()
        self.manager.delegate = self
    }

    func request() {
        manager.requestWhenInUseAuthorization()
    }

    // iOS 14+
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        handle(status: manager.authorizationStatus)
    }

    // iOS 13 and earlier
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        handle(status: status)
    }

    private func handle(status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            // Prime a one-shot location so downstream screens have something immediately.
            manager.requestLocation()
            completion(status)
        case .denied, .restricted:
            completion(status)
        case .notDetermined:
            break
        @unknown default:
            completion(.denied)
        }
        // Break the delegate cycle; no more callbacks needed.
        manager.delegate = nil
    }
}


