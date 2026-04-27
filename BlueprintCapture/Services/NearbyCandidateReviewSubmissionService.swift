import Foundation
import CoreLocation

protocol NearbyCandidateReviewSubmissionServiceProtocol {
    func submitCandidatesIfNeeded(userLocation: CLLocation, sourceContext: String, candidates: [PlaceDetailsLite]) async
}

final class NearbyCandidateReviewSubmissionService: NearbyCandidateReviewSubmissionServiceProtocol {
    private let api: CityLaunchCandidateSignalServiceProtocol
    private let geocoder: CLGeocoder
    private let defaults: UserDefaults
    private let cooldownSeconds: TimeInterval = 12 * 60 * 60
    private let maxCandidatesPerSubmission = 25

    init(
        api: CityLaunchCandidateSignalServiceProtocol = APIService.shared,
        geocoder: CLGeocoder = CLGeocoder(),
        defaults: UserDefaults = .standard
    ) {
        self.api = api
        self.geocoder = geocoder
        self.defaults = defaults
    }

    func submitCandidatesIfNeeded(userLocation: CLLocation, sourceContext: String, candidates: [PlaceDetailsLite]) async {
        guard !candidates.isEmpty else { return }

        let storageKey = Self.cooldownStorageKey(
            userId: UserDeviceService.resolvedUserId(),
            sourceContext: sourceContext,
            userLocation: userLocation
        )
        let now = Date()
        if let lastRun = defaults.object(forKey: storageKey) as? Date,
           now.timeIntervalSince(lastRun) < cooldownSeconds {
            return
        }

        let placemark = try? await geocoder.reverseGeocodeLocation(userLocation).first
        let city = [placemark?.locality, placemark?.administrativeArea]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")

        guard !city.isEmpty else { return }

        let payload = CityLaunchCandidateSignalSubmissionRequest(
            candidates: Array(candidates.prefix(maxCandidatesPerSubmission)).map {
                .init(
                    city: city,
                    name: $0.displayName,
                    address: $0.formattedAddress,
                    lat: $0.lat,
                    lng: $0.lng,
                    provider: "nearby_discovery",
                    providerPlaceId: $0.placeId,
                    types: $0.types ?? [],
                    sourceContext: sourceContext
                )
            }
        )

        do {
            try await api.submitCityLaunchCandidateSignals(payload)
            defaults.set(now, forKey: storageKey)
        } catch {
            return
        }
    }

    static func cooldownStorageKey(userId: String, sourceContext: String, userLocation: CLLocation) -> String {
        let areaKey = "\(Int(userLocation.coordinate.latitude * 10)):\(Int(userLocation.coordinate.longitude * 10))"
        return "city-launch-candidate-scan:\(userId):\(sourceContext):\(areaKey)"
    }
}
