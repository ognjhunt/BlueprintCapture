import Foundation
import CoreLocation
import Testing
@testable import BlueprintCapture

struct OnboardingCaptureUXCopyTests {

    @Test
    func completionCopyReflectsWhetherGlassesWereConnected() {
        #expect(OnboardingCaptureUXCopy.completionTitle(glassesConnected: true) == "You're Ready to Capture")
        #expect(OnboardingCaptureUXCopy.completionMessage(glassesConnected: true) == "We'll notify you when approved capture opportunities are nearby.")
        #expect(OnboardingCaptureUXCopy.completionTitle(glassesConnected: false) == "Start with iPhone Capture")
        #expect(OnboardingCaptureUXCopy.completionMessage(glassesConnected: false) == "You can submit spaces and capture with your iPhone now. Connect glasses later for hands-free capture.")
    }

    @Test
    func disconnectedGlassesSubtitleMatchesIPhoneFallback() {
        #expect(OnboardingCaptureUXCopy.disconnectedGlassesSubtitle == "Optional for hands-free capture. Approved jobs also work with iPhone.")
    }

    @Test
    func locationUnknownErrorGetsHumanReadableGuidance() {
        let error = NSError(domain: kCLErrorDomain, code: CLError.Code.locationUnknown.rawValue)

        #expect(CaptureLocationErrorPresenter.message(for: error) == "We couldn't determine your location yet. Try again or enter the address manually.")
    }

    @Test
    func deniedLocationErrorExplainsSettingsAndManualFallback() {
        let error = NSError(domain: kCLErrorDomain, code: CLError.Code.denied.rawValue)

        #expect(CaptureLocationErrorPresenter.message(for: error) == "Location access is off. Turn it on in Settings or enter the address manually.")
    }

    @Test
    func unknownErrorsNeverExposeRawSystemDomains() {
        let error = NSError(domain: "kCLErrorDomain", code: 0, userInfo: [NSLocalizedDescriptionKey: "The operation couldn’t be completed. (kCLErrorDomain error 0.)"])
        let message = CaptureLocationErrorPresenter.message(for: error)

        #expect(message == "We couldn't determine your location. Try again or enter the address manually.")
        #expect(!message.contains("kCLErrorDomain"))
    }
}
