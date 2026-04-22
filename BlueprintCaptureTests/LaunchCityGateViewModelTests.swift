import CoreLocation
import Testing
@testable import BlueprintCapture

@MainActor
struct LaunchCityGateViewModelTests {

    @Test
    func missingCreatorBackendConfigSurfacesExplicitFailureMessage() async throws {
        let location = CLLocation(latitude: 35.960017, longitude: -78.894193)
        let locationService = StubLocationService(
            authorizationStatus: .authorizedWhenInUse,
            latestLocation: location
        )
        let resolver = StubLaunchCityResolver(
            resolvedCity: ResolvedLaunchCity(city: "Durham", stateCode: "NC", countryCode: "US")
        )
        let launchStatusService = StubCreatorLaunchStatusService(
            error: APIService.APIError.missingBaseURL
        )

        let viewModel = LaunchCityGateViewModel(
            locationService: locationService,
            resolver: resolver,
            launchStatusService: launchStatusService
        )

        viewModel.start()
        try await Task.sleep(for: .milliseconds(50))

        guard case .failed(let message) = viewModel.state else {
            Issue.record("Expected launch city gate to fail when creator backend base URL is missing.")
            return
        }

        #expect(message.contains("BLUEPRINT_BACKEND_BASE_URL"))
        #expect(message.contains("location"))
    }

    @Test
    func alreadyAuthorizedGateRequestsCurrentLocationWhenCacheIsEmpty() async throws {
        let locationService = StubLocationService(
            authorizationStatus: .authorizedWhenInUse,
            latestLocation: nil
        )
        let launchStatusService = StubCreatorLaunchStatusService(
            response: CreatorLaunchStatusResponse(supportedCities: [], currentCity: nil)
        )

        let viewModel = LaunchCityGateViewModel(
            locationService: locationService,
            resolver: StubLaunchCityResolver(resolvedCity: nil),
            launchStatusService: launchStatusService
        )

        viewModel.start()

        #expect(locationService.startUpdatingLocationCallCount == 1)
        #expect(locationService.requestCurrentLocationCallCount == 1)
        #expect(viewModel.state == .checking)
    }
}

private final class StubLocationService: LocationServiceProtocol {
    let authorizationStatus: CLAuthorizationStatus
    let latestLocation: CLLocation?
    private var listener: ((CLLocation?) -> Void)?
    private(set) var startUpdatingLocationCallCount = 0
    private(set) var requestCurrentLocationCallCount = 0

    init(
        authorizationStatus: CLAuthorizationStatus,
        latestLocation: CLLocation?
    ) {
        self.authorizationStatus = authorizationStatus
        self.latestLocation = latestLocation
    }

    func requestWhenInUseAuthorization() {}

    func startUpdatingLocation() {
        startUpdatingLocationCallCount += 1
        listener?(latestLocation)
    }

    func requestCurrentLocation() {
        requestCurrentLocationCallCount += 1
    }

    func stopUpdatingLocation() {}

    func setListener(_ listener: @escaping (CLLocation?) -> Void) {
        self.listener = listener
    }
}

private struct StubLaunchCityResolver: LaunchCityResolving {
    let resolvedCity: ResolvedLaunchCity?

    func resolveCity(for location: CLLocation) async throws -> ResolvedLaunchCity? {
        resolvedCity
    }
}

private struct StubCreatorLaunchStatusService: CreatorLaunchStatusServiceProtocol {
    var error: Error?
    var response: CreatorLaunchStatusResponse?

    func fetchCreatorLaunchStatus(city: String?, stateCode: String?) async throws -> CreatorLaunchStatusResponse {
        if let error {
            throw error
        }
        return response ?? CreatorLaunchStatusResponse(supportedCities: [], currentCity: nil)
    }
}
