import Foundation
import Testing
@testable import BlueprintCapture

struct LaunchAccessURLResolverTests {

    @Test
    func websitePresentBuildsLaunchAccessURLWithSourceAndCity() {
        let result = LaunchAccessURLResolver.resolve(
            websiteURL: URL(string: "https://blueprint.example.com"),
            helpCenterURL: nil,
            supportEmailURL: nil,
            resolvedCityDisplayName: "Seattle, WA"
        )

        #expect(result.path.contains("capture-app/launch-access"))
        let components = URLComponents(url: result, resolvingAgainstBaseURL: false)
        #expect(components?.queryItems?.contains(
            URLQueryItem(name: "source", value: "ios-capture-app-launch-gate")
        ) == true)
        #expect(components?.queryItems?.contains(
            URLQueryItem(name: "city", value: "Seattle, WA")
        ) == true)
    }

    @Test
    func websiteNilFallsBackToHelpCenter() {
        let helpCenter = URL(string: "https://help.example.com/launch")!
        let result = LaunchAccessURLResolver.resolve(
            websiteURL: nil,
            helpCenterURL: helpCenter,
            supportEmailURL: nil,
            resolvedCityDisplayName: nil
        )

        #expect(result == helpCenter)
    }

    @Test
    func websiteAndHelpCenterNilFallsBackToSupportEmail() {
        let supportEmail = URL(string: "mailto:support@example.com?subject=Request%20launch%20access")!
        let result = LaunchAccessURLResolver.resolve(
            websiteURL: nil,
            helpCenterURL: nil,
            supportEmailURL: supportEmail,
            resolvedCityDisplayName: nil
        )

        #expect(result == supportEmail)
    }

    @Test
    func allRuntimeURLsNilStillReturnsHardCodedRecoveryURL() {
        let result = LaunchAccessURLResolver.resolve(
            websiteURL: nil,
            helpCenterURL: nil,
            supportEmailURL: nil,
            resolvedCityDisplayName: "Enterprise Industrial Park, TX"
        )

        // R019: never a dead-end — the fallback is independent of RuntimeConfig.
        #expect(result.host == "blueprintcapture.app")
        #expect(result.path.contains("capture-app/launch-access"))
        let components = URLComponents(url: result, resolvingAgainstBaseURL: false)
        #expect(components?.queryItems?.contains(
            URLQueryItem(name: "city", value: "Enterprise Industrial Park, TX")
        ) == true)
    }

    @Test
    func fallbackURLIsValidWithoutResolvedCity() {
        let result = LaunchAccessURLResolver.resolve(
            websiteURL: nil,
            helpCenterURL: nil,
            supportEmailURL: nil,
            resolvedCityDisplayName: nil
        )

        #expect(result.host == "blueprintcapture.app")
        #expect(result.path.contains("capture-app/launch-access"))
    }
}
