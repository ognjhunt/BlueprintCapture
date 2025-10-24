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
        // IMPORTANT: retain the delegate proxy until it invokes the callback, otherwise
        // the continuation can be leaked if ARC deallocates the proxy before delegate fires.
        return await withCheckedContinuation { continuation in
            // Retain both the proxy and continuation safely; allows timeout to resume
            // exactly once if the delegate never fires for any reason.
            final class Box {
                var proxy: AuthorizationDelegateProxy?
                var cont: CheckedContinuation<Bool, Never>?
            }
            let box = Box()
            box.cont = continuation
            box.proxy = AuthorizationDelegateProxy { status in
                let allowed = (status == .authorizedAlways || status == .authorizedWhenInUse)
                if let cont = box.cont { cont.resume(returning: allowed) }
                box.cont = nil
                box.proxy = nil
            }

            // Fallback timeout to avoid indefinite spinner if the system never calls back
            // (rare, but can happen due to OS bugs or app lifecycle interruptions).
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
                guard let cont = box.cont else { return }
                cont.resume(returning: false)
                box.cont = nil
                box.proxy = nil
            }

            box.proxy?.request()
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


