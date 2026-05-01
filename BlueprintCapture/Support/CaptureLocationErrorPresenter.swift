import CoreLocation
import Foundation

enum CaptureLocationErrorPresenter {
    static func message(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == kCLErrorDomain {
            let hasExplicitLocalizedDescription = nsError.userInfo[NSLocalizedDescriptionKey] != nil
            switch CLError.Code(rawValue: nsError.code) {
            case .locationUnknown:
                if hasExplicitLocalizedDescription {
                    return "We couldn't determine your location. Try again or enter the address manually."
                }
                return "We couldn't determine your location yet. Try again or enter the address manually."
            case .denied:
                return "Location access is off. Turn it on in Settings or enter the address manually."
            default:
                return "We couldn't determine your location. Try again or enter the address manually."
            }
        }

        let description = nsError.localizedDescription
        if description.contains("kCLErrorDomain") || description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "We couldn't determine your location. Try again or enter the address manually."
        }
        return description
    }
}
