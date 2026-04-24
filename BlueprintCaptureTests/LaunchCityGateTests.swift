import Foundation
import Testing
@testable import BlueprintCapture

struct LaunchCityGateTests {

    @Test
    func matcherAllowsBackendProvidedLaunchCities() {
        let supportedCities: [CreatorLaunchStatusResponse.SupportedCity] = [
            .init(city: "Austin", stateCode: "TX", displayName: "Austin, TX", citySlug: "austin-tx"),
            .init(city: "Durham", stateCode: "NC", displayName: "Durham, NC", citySlug: "durham-nc"),
            .init(city: "San Francisco", stateCode: "CA", displayName: "San Francisco, CA", citySlug: "san-francisco-ca")
        ]
        let austin = ResolvedLaunchCity(city: "Austin", stateCode: "TX", countryCode: "US")
        let durham = ResolvedLaunchCity(city: "Durham", stateCode: "NC", countryCode: "US")
        let sanFrancisco = ResolvedLaunchCity(city: "San Francisco", stateCode: "CA", countryCode: "US")

        #expect(LaunchCityMatcher.supportedCity(for: austin, in: supportedCities)?.displayName == "Austin, TX")
        #expect(LaunchCityMatcher.supportedCity(for: durham, in: supportedCities)?.displayName == "Durham, NC")
        #expect(LaunchCityMatcher.supportedCity(for: sanFrancisco, in: supportedCities)?.displayName == "San Francisco, CA")
    }

    @Test
    func matcherHasNoLocalLaunchCityFallback() {
        let austin = ResolvedLaunchCity(city: "Austin", stateCode: "TX", countryCode: "US")

        #expect(LaunchCityMatcher.supportedCity(for: austin, in: []) == nil)
    }

    @Test
    func matcherRejectsUnsupportedCities() {
        let supportedCities: [CreatorLaunchStatusResponse.SupportedCity] = [
            .init(city: "Austin", stateCode: "TX", displayName: "Austin, TX", citySlug: "austin-tx")
        ]
        let seattle = ResolvedLaunchCity(city: "Seattle", stateCode: "WA", countryCode: "US")
        let dallas = ResolvedLaunchCity(city: "Dallas", stateCode: "TX", countryCode: "US")

        #expect(LaunchCityMatcher.supportedCity(for: seattle, in: supportedCities) == nil)
        #expect(LaunchCityMatcher.supportedCity(for: dallas, in: supportedCities) == nil)
    }

    @Test
    func matcherNormalizesStateAliases() {
        let supportedCities: [CreatorLaunchStatusResponse.SupportedCity] = [
            .init(city: "Austin", stateCode: "TX", displayName: "Austin, TX", citySlug: "austin-tx"),
            .init(city: "Durham", stateCode: "NC", displayName: "Durham, NC", citySlug: "durham-nc"),
            .init(city: "San Francisco", stateCode: "CA", displayName: "San Francisco, CA", citySlug: "san-francisco-ca")
        ]
        let sanFrancisco = ResolvedLaunchCity(city: "San Francisco", stateCode: "California", countryCode: "US")
        let durham = ResolvedLaunchCity(city: "Durham", stateCode: "north carolina", countryCode: "US")
        let austin = ResolvedLaunchCity(city: "Austin", stateCode: "texas", countryCode: "US")

        #expect(LaunchCityMatcher.supportedCity(for: sanFrancisco, in: supportedCities)?.stateCode == "CA")
        #expect(LaunchCityMatcher.supportedCity(for: durham, in: supportedCities)?.stateCode == "NC")
        #expect(LaunchCityMatcher.supportedCity(for: austin, in: supportedCities)?.stateCode == "TX")
    }
}
