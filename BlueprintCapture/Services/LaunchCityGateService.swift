import Foundation
import CoreLocation
import Observation

struct ResolvedLaunchCity: Equatable {
    let city: String
    let stateCode: String?
    let countryCode: String?

    var displayName: String {
        if let stateCode, !stateCode.isEmpty {
            return "\(city), \(stateCode)"
        }
        if let countryCode, !countryCode.isEmpty {
            return "\(city), \(countryCode)"
        }
        return city
    }
}

enum LaunchCityMatcher {
    static func supportedCity(
        for city: ResolvedLaunchCity,
        in supportedCities: [CreatorLaunchStatusResponse.SupportedCity]
    ) -> CreatorLaunchStatusResponse.SupportedCity? {
        let normalizedCity = normalizeToken(city.city)
        let normalizedState = normalizeStateToken(city.stateCode)

        return supportedCities.first { supportedCity in
            normalizeToken(supportedCity.city) == normalizedCity
                && normalizeStateToken(supportedCity.stateCode) == normalizedState
        }
    }

    private static func normalizeToken(_ value: String?) -> String {
        String(value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
    }

    private static func normalizeStateToken(_ value: String?) -> String {
        switch normalizeToken(value) {
        case "california":
            return "ca"
        case "north carolina":
            return "nc"
        case "texas":
            return "tx"
        default:
            return normalizeToken(value)
        }
    }
}

protocol LaunchCityResolving {
    func resolveCity(for location: CLLocation) async throws -> ResolvedLaunchCity?
}

final class LaunchCityResolver: LaunchCityResolving {
    private let geocoder: CLGeocoder

    init(geocoder: CLGeocoder = CLGeocoder()) {
        self.geocoder = geocoder
    }

    func resolveCity(for location: CLLocation) async throws -> ResolvedLaunchCity? {
        let placemarks = try await geocoder.reverseGeocodeLocation(location)
        guard let placemark = placemarks.first else { return nil }

        let city = placemark.locality
            ?? placemark.subAdministrativeArea
            ?? placemark.name

        guard let city, city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return nil
        }

        return ResolvedLaunchCity(
            city: city,
            stateCode: placemark.administrativeArea,
            countryCode: placemark.isoCountryCode
        )
    }
}

@MainActor
@Observable
final class LaunchCityGateViewModel {
    enum State: Equatable {
        case checking
        case locationPermissionRequired
        case locationPermissionDenied
        case supported(CreatorLaunchStatusResponse.SupportedCity)
        case unsupported(CreatorLaunchStatusResponse.CurrentCity?)
        case failed(String)
    }

    private let locationService: LocationServiceProtocol
    private let resolver: LaunchCityResolving
    private let launchStatusService: CreatorLaunchStatusServiceProtocol
    private var hasStarted = false
    private var lastResolvedLocation: CLLocation?
    // This task is cancelled during teardown from a nonisolated deinit.
    nonisolated(unsafe) private var evaluationTask: Task<Void, Never>?

    var state: State = .checking
    var supportedCities: [CreatorLaunchStatusResponse.SupportedCity] = []

    init(
        locationService: LocationServiceProtocol = LocationService(),
        resolver: LaunchCityResolving = LaunchCityResolver(),
        launchStatusService: CreatorLaunchStatusServiceProtocol = APIService.shared
    ) {
        self.locationService = locationService
        self.resolver = resolver
        self.launchStatusService = launchStatusService

        locationService.setListener { [weak self] location in
            guard let self else { return }
            Task { @MainActor in
                self.handleLocationUpdate(location)
            }
        }
    }

    deinit {
        evaluationTask?.cancel()
        locationService.stopUpdatingLocation()
    }

    var resolvedCity: ResolvedLaunchCity? {
        switch state {
        case .supported(let city):
            return ResolvedLaunchCity(city: city.city, stateCode: city.stateCode, countryCode: "US")
        case .unsupported(let city):
            guard let city else { return nil }
            return ResolvedLaunchCity(city: city.city, stateCode: city.stateCode, countryCode: "US")
        default:
            return nil
        }
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        syncWithAuthorizationStatus()
    }

    func refresh() {
        syncWithAuthorizationStatus(forceRefresh: true)
    }

    func requestLocationAccess() async {
        state = .checking
        let granted = await LocationPermissionRequester.requestWhenInUse()
        if granted {
            syncWithAuthorizationStatus(forceRefresh: true)
        } else {
            syncWithAuthorizationStatus()
        }
    }

    private func syncWithAuthorizationStatus(forceRefresh: Bool = false) {
        switch locationService.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            state = .checking
            locationService.startUpdatingLocation()
            if forceRefresh {
                lastResolvedLocation = nil
            }
            if let latestLocation = locationService.latestLocation {
                handleLocationUpdate(latestLocation, forceRefresh: forceRefresh)
            } else {
                locationService.requestCurrentLocation()
            }
        case .notDetermined:
            state = .locationPermissionRequired
        case .denied, .restricted:
            state = .locationPermissionDenied
        @unknown default:
            state = .failed("Blueprint could not verify your city on this device.")
        }
    }

    private func handleLocationUpdate(_ location: CLLocation?, forceRefresh: Bool = false) {
        guard let location else {
            if case .supported = state {
                return
            }
            state = .checking
            return
        }

        if !forceRefresh,
           let lastResolvedLocation,
           location.distance(from: lastResolvedLocation) < 100 {
            return
        }

        lastResolvedLocation = location
        state = .checking
        evaluationTask?.cancel()
        evaluationTask = Task { [resolver, launchStatusService] in
            var resolvedCity: ResolvedLaunchCity?
            do {
                resolvedCity = try await resolver.resolveCity(for: location)
                let launchStatus = try await launchStatusService.fetchCreatorLaunchStatus(
                    city: resolvedCity?.city,
                    stateCode: resolvedCity?.stateCode
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.supportedCities = launchStatus.supportedCities
                    self.applyLaunchStatus(launchStatus)
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.state = .failed(Self.failureMessage(for: error, resolvedCity: resolvedCity))
                }
            }
        }
    }

    private func applyLaunchStatus(_ launchStatus: CreatorLaunchStatusResponse) {
        if let currentCity = launchStatus.currentCity,
           currentCity.isSupported,
           let supportedCity = launchStatus.supportedCities.first(where: { $0.citySlug == currentCity.citySlug }) {
            state = .supported(supportedCity)
            return
        }

        state = .unsupported(launchStatus.currentCity)
    }

    private static func failureMessage(for error: Error, resolvedCity: ResolvedLaunchCity?) -> String {
        if let apiError = error as? APIService.APIError,
           apiError == .missingBaseURL {
            if let resolvedCity {
                return "Blueprint found your location (\(resolvedCity.displayName)), but this build cannot verify launch access because BLUEPRINT_BACKEND_BASE_URL is not configured."
            }
            return "This build cannot verify launch access because BLUEPRINT_BACKEND_BASE_URL is not configured."
        }

        return "Blueprint couldn’t verify your city right now. Try again in a moment."
    }
}
