import Foundation
import Testing
@testable import BlueprintCapture

struct CaptureLegalConsentPolicyTests {
    private let terms = URL(string: "https://www.tryblueprint.io/terms")!
    private let privacy = URL(string: "https://www.tryblueprint.io/privacy")!
    private let capture = URL(string: "https://www.tryblueprint.io/capture-policy")!

    @Test
    func requiresExplicitAcknowledgementAndAllLegalLinks() {
        let policy = CaptureLegalConsentPolicy(
            termsOfServiceURL: terms,
            privacyPolicyURL: privacy,
            capturePolicyURL: capture
        )

        #expect(policy.hasRequiredLegalLinks)
        #expect(policy.canContinue(hasAcknowledged: true))
        #expect(policy.canContinue(hasAcknowledged: false) == false)
        #expect(policy.canContinue(hasAcknowledged: true, isBusy: true) == false)
    }

    @Test
    func missingAnyLegalLinkFailsClosed() {
        let policy = CaptureLegalConsentPolicy(
            termsOfServiceURL: terms,
            privacyPolicyURL: nil,
            capturePolicyURL: capture
        )

        #expect(policy.hasRequiredLegalLinks == false)
        #expect(policy.missingRequiredLinkTitles == ["Privacy Policy"])
        #expect(policy.canContinue(hasAcknowledged: true) == false)
    }

    @Test
    func acknowledgementNamesPermissionAndLegalPolicies() {
        let text = CaptureLegalConsentPolicy.acknowledgementText

        #expect(text.contains("permission to capture this site"))
        #expect(text.contains("restricted or private areas"))
        #expect(text.contains("Terms of Service"))
        #expect(text.contains("Privacy Policy"))
        #expect(text.contains("Capture Policy"))
    }

    @Test
    func betaGuideDestinationsUseConfiguredWebsiteOrPublicFallback() {
        let websiteURL = URL(string: "https://beta.example.com")!

        #expect(
            BetaCohortGuideDestination.capturerGuideURL(mainWebsiteURL: websiteURL).absoluteString ==
            "https://beta.example.com/beta/capturer-guide"
        )
        #expect(
            BetaCohortGuideDestination.buyerGuideURL(mainWebsiteURL: websiteURL).absoluteString ==
            "https://beta.example.com/beta/buyer-guide"
        )
        #expect(
            BetaCohortGuideDestination.capturerGuideURL(mainWebsiteURL: nil).absoluteString ==
            "https://www.tryblueprint.io/beta/capturer-guide"
        )
    }

    @Test
    func supportDestinationsFallbackWhenRuntimeLinksAreMissing() {
        let betaGuideURL = URL(string: "https://www.tryblueprint.io/beta/capturer-guide")!

        #expect(CaptureSupportDestination.supportEmailAddress(configuredAddress: nil) == "support@tryblueprint.io")
        #expect(CaptureSupportDestination.supportEmailAddress(configuredAddress: "  ops@example.com  ") == "ops@example.com")
        #expect(
            CaptureSupportDestination.helpCenterURL(configuredURL: nil, betaGuideURL: betaGuideURL)
            == betaGuideURL
        )

        let supportURL = CaptureSupportDestination.bugReportURL(
            configuredURL: nil,
            configuredSupportEmail: nil
        )

        #expect(supportURL.scheme == "mailto")
        #expect(supportURL.absoluteString.contains("support@tryblueprint.io"))
        #expect(supportURL.absoluteString.contains("Blueprint%20Capture%20Bug%20Report"))
    }
}
