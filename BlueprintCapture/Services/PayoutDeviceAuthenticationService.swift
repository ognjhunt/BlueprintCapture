import Foundation
import LocalAuthentication

final class PayoutDeviceAuthenticationService {
    enum AuthenticationError: LocalizedError {
        case unavailable
        case failed(Error)

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "Set up a device passcode, Face ID, or Touch ID before managing payouts."
            case .failed(let error):
                return error.localizedDescription
            }
        }
    }

    static let shared = PayoutDeviceAuthenticationService()

    private init() {}

    func authenticate(reason: String = "Unlock to manage Blueprint payouts.") async throws {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw AuthenticationError.unavailable
        }

        do {
            let accepted = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
            if !accepted {
                throw AuthenticationError.unavailable
            }
        } catch {
            throw AuthenticationError.failed(error)
        }
    }
}
