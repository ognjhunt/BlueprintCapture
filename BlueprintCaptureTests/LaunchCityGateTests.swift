import Foundation
import Testing
@testable import BlueprintCapture

struct LaunchCityGateTests {

    @Test
    func matcherAllowsConfiguredLaunchCities() {
        let austin = ResolvedLaunchCity(city: "Austin", stateCode: "TX", countryCode: "US")
        let durham = ResolvedLaunchCity(city: "Durham", stateCode: "NC", countryCode: "US")
        let sanFrancisco = ResolvedLaunchCity(city: "San Francisco", stateCode: "CA", countryCode: "US")

        #expect(LaunchCityMatcher.supportedCity(for: austin)?.displayName == "Austin, TX")
        #expect(LaunchCityMatcher.supportedCity(for: durham)?.displayName == "Durham, NC")
        #expect(LaunchCityMatcher.supportedCity(for: sanFrancisco)?.displayName == "San Francisco, CA")
    }

    @Test
    func matcherRejectsUnsupportedCities() {
        let seattle = ResolvedLaunchCity(city: "Seattle", stateCode: "WA", countryCode: "US")
        let dallas = ResolvedLaunchCity(city: "Dallas", stateCode: "TX", countryCode: "US")

        #expect(LaunchCityMatcher.supportedCity(for: seattle) == nil)
        #expect(LaunchCityMatcher.supportedCity(for: dallas) == nil)
    }

    @Test
    func matcherNormalizesStateAliases() {
        let sanFrancisco = ResolvedLaunchCity(city: "San Francisco", stateCode: "California", countryCode: "US")
        let durham = ResolvedLaunchCity(city: "Durham", stateCode: "north carolina", countryCode: "US")
        let austin = ResolvedLaunchCity(city: "Austin", stateCode: "texas", countryCode: "US")

        #expect(LaunchCityMatcher.supportedCity(for: sanFrancisco)?.stateCode == "CA")
        #expect(LaunchCityMatcher.supportedCity(for: durham)?.stateCode == "NC")
        #expect(LaunchCityMatcher.supportedCity(for: austin)?.stateCode == "TX")
    }
}
