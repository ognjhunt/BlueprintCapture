import Foundation
import CoreLocation
import Testing
@testable import BlueprintCapture

struct OnboardingCaptureUXCopyTests {

    @Test
    func completionCopyReflectsWhetherGlassesWereConnected() {
        #expect(OnboardingCaptureUXCopy.completionTitle(glassesConnected: true) == "Capture Setup Complete")
        #expect(OnboardingCaptureUXCopy.completionMessage(glassesConnected: true) == "We'll show assigned-site work, approved opportunities, and review-gated submissions separately. Payout and downstream use depend on backend review.")
        #expect(OnboardingCaptureUXCopy.completionTitle(glassesConnected: false) == "Start with iPhone Capture")
        #expect(OnboardingCaptureUXCopy.completionMessage(glassesConnected: false) == "You can capture assigned or operator-approved facility sites with your iPhone now. Connect glasses later for supported hands-free capture.")
    }

    @Test
    func disconnectedGlassesSubtitleMatchesIPhoneFallback() {
        #expect(OnboardingCaptureUXCopy.disconnectedGlassesSubtitle == "Optional for supported hands-free capture. Assigned-site work, approved jobs, and review submissions can still start with iPhone.")
    }

    @Test
    func firstCaptureGoalsLeadWithAssignedIndustrialOrApprovedSitePath() {
        #expect(OnboardingFirstCaptureGoal.storageKey == "com.blueprint.firstCaptureGoal")
        #expect(OnboardingFirstCaptureGoal.allCases.first == .assignedOrApprovedSite)
        #expect(OnboardingFirstCaptureGoal.assignedOrApprovedSite.rawValue == "current_place_raw_capture")
        #expect(OnboardingFirstCaptureGoal.nearbyOpportunity.rawValue == "nearby_approved_opportunity")

        let assignedCopy = [
            OnboardingFirstCaptureGoal.assignedOrApprovedSite.title,
            OnboardingFirstCaptureGoal.assignedOrApprovedSite.subtitle
        ].joined(separator: " ")

        #expect(assignedCopy.contains("assigned"))
        #expect(assignedCopy.contains("industrial"))
        #expect(assignedCopy.contains("facility"))
        #expect(assignedCopy.contains("operator-approved"))
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

    @MainActor
    @Test
    func captureFlowLocationFailureUsesHumanReadableGuidance() {
        let viewModel = CaptureFlowViewModel()
        let error = NSError(domain: kCLErrorDomain, code: CLError.Code.locationUnknown.rawValue)

        viewModel.locationManager(CLLocationManager(), didFailWithError: error)

        #expect(viewModel.locationError == "We couldn't determine your location yet. Try again or enter the address manually.")
    }
}
