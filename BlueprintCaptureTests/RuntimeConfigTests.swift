import Foundation
import Testing
@testable import BlueprintCapture

struct RuntimeConfigTests {

    @Test
    func defaultsDisableSensitiveFeaturesWithoutBundleSecrets() {
        let config = RuntimeConfig.load(environment: [:], infoDictionary: [:])

        #expect(config.backendBaseURL == nil)
        #expect(config.isUITesting == false)
        #expect(config.uiTestScenario == .disabled)
        #expect(config.availability(for: .payouts).isEnabled == false)
        #expect(config.availability(for: .nearbyDiscovery).isEnabled == false)
        #expect(config.availability(for: .streetView).isEnabled == false)
        #expect(config.allowOffsiteCheckIn == false)
        #expect(config.allowMockJobsFallback == false)
    }

    @Test
    func environmentAndBuildSettingsEnablePublicRuntimeConfig() {
        let config = RuntimeConfig.load(
            environment: [
                "BLUEPRINT_UI_TEST_MODE": "1",
                "BLUEPRINT_UI_TEST_SCENARIO": "wallet",
                "BLUEPRINT_ENABLE_DIRECT_PROVIDER_FEATURES": "true",
                "BLUEPRINT_ALLOW_MOCK_JOBS_FALLBACK": "true",
                "BLUEPRINT_MAX_RESERVATION_DRIVE_MINUTES": "90",
                "BLUEPRINT_FALLBACK_MAX_RESERVATION_AIR_MILES": "50.5"
            ],
            infoDictionary: [
                "BLUEPRINT_BACKEND_BASE_URL": "https://alpha.example.com"
            ]
        )

        #expect(config.backendBaseURL?.absoluteString == "https://alpha.example.com")
        #expect(config.isUITesting == true)
        #expect(config.uiTestScenario == .wallet)
        #expect(config.availability(for: .payouts).isEnabled == true)
        #expect(config.availability(for: .nearbyDiscovery).isEnabled == true)
        #expect(config.allowOffsiteCheckIn == true)
        #expect(config.allowMockJobsFallback == true)
        #expect(config.maxReservationDriveMinutes == 90)
        #expect(config.fallbackMaxReservationAirMiles == 50.5)
    }
}
