import Foundation
import CoreLocation

/// Fetches a single best-effort user location and returns it via async/await
enum OneShotLocationFetcher {
    static func fetch(timeout: TimeInterval = 8.0) async -> CLLocationCoordinate2D? {
        return await withCheckedContinuation { continuation in
            final class Box: NSObject, CLLocationManagerDelegate {
                let manager = CLLocationManager()
                var cont: CheckedContinuation<CLLocationCoordinate2D?, Never>?

                func start() {
                    manager.delegate = self
                    manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
                    manager.requestLocation()
                }

                func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
                    if let loc = locations.last?.coordinate {
                        cont?.resume(returning: loc)
                        cont = nil
                    } else {
                        cont?.resume(returning: nil)
                        cont = nil
                    }
                    manager.delegate = nil
                }

                func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
                    cont?.resume(returning: nil)
                    cont = nil
                    manager.delegate = nil
                }
            }

            let box = Box()
            box.cont = continuation
            box.start()
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                if let cont = box.cont {
                    cont.resume(returning: nil)
                }
                box.manager.delegate = nil
                box.cont = nil
            }
        }
    }
}


