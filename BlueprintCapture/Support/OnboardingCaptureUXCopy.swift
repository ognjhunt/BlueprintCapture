import Foundation
import CoreLocation

enum OnboardingCaptureUXCopy {
    static func completionTitle(glassesConnected: Bool) -> String {
        glassesConnected ? "You're Ready to Capture" : "Start with iPhone Capture"
    }

    static func completionMessage(glassesConnected: Bool) -> String {
        if glassesConnected {
            return "We'll notify you when approved capture opportunities are nearby."
        }
        return "You can submit spaces and capture with your iPhone now. Connect glasses later for hands-free capture."
    }

    static let disconnectedGlassesSubtitle = "Optional for hands-free capture. Approved jobs also work with iPhone."
}

enum CaptureLocationErrorPresenter {
    static func message(for error: Error) -> String {
        let nsError = error as NSError

        if nsError.domain == kCLErrorDomain,
           let code = CLError.Code(rawValue: nsError.code) {
            switch code {
            case .denied:
                return "Location access is off. Turn it on in Settings or enter the address manually."
            case .network, .locationUnknown:
                return "We couldn't determine your location yet. Try again or enter the address manually."
            default:
                break
            }
        }

        return "We couldn't determine your location. Try again or enter the address manually."
    }
}
