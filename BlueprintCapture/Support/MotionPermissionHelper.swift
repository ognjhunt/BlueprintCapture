import Foundation
import CoreMotion

enum MotionPermissionHelper {
    static var isAvailable: Bool {
        CMMotionActivityManager.isActivityAvailable()
    }

    static var isAuthorized: Bool {
        guard isAvailable else { return true }
        return CMMotionActivityManager.authorizationStatus() == .authorized
    }

    static func requestAuthorization(
        activityManager: CMMotionActivityManager = CMMotionActivityManager()
    ) async -> Bool {
        guard isAvailable else { return true }

        switch CMMotionActivityManager.authorizationStatus() {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            let start = Date().addingTimeInterval(-60)
            do {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    activityManager.queryActivityStarting(from: start, to: Date(), to: OperationQueue.main) { _, error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume()
                        }
                    }
                }
            } catch {
                return false
            }
            return CMMotionActivityManager.authorizationStatus() == .authorized
        @unknown default:
            return false
        }
    }
}
