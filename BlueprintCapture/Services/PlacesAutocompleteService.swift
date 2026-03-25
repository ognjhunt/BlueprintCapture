import Foundation
import CoreLocation

struct AutocompleteSuggestion: Identifiable, Equatable {
    let id = UUID()
    let placeId: String
    let primaryText: String
    let secondaryText: String
    let types: [String]
}

protocol PlacesAutocompleteServiceProtocol {
    func autocomplete(
        input: String,
        sessionToken: String,
        origin: CLLocationCoordinate2D?,
        radiusMeters: Int?
    ) async throws -> [AutocompleteSuggestion]
}

final class PlacesAutocompleteService: PlacesAutocompleteServiceProtocol {
    private let backend: NearbyProxyBackendService

    init(
        backend: NearbyProxyBackendService = .shared
    ) {
        self.backend = backend
    }

    enum ServiceError: Error {
        case featureDisabled
        case noResults
    }

    // Google Places v1 Autocomplete (NEW API)
    // https://developers.google.com/maps/documentation/places/web-service/place-autocomplete
    func autocomplete(
        input: String,
        sessionToken: String,
        origin: CLLocationCoordinate2D?,
        radiusMeters: Int?
    ) async throws -> [AutocompleteSuggestion] {
        guard RuntimeConfig.current.availability(for: .nearbyDiscovery).isEnabled else {
            throw ServiceError.featureDisabled
        }
        print("🔍 [Places Autocomplete] Searching for '\(input)' near \(origin.map { "(\($0.latitude), \($0.longitude))" } ?? "unknown")")
        let response = try await backend.autocomplete(
            query: input,
            sessionToken: sessionToken,
            origin: origin,
            radiusMeters: radiusMeters
        )
        let results = response.suggestions.map(\.autocompleteSuggestion)
        print("✅ [Places Autocomplete] Found \(results.count) suggestions")
        for (idx, result) in results.prefix(5).enumerated() {
            print("   \(idx+1). \(result.primaryText) - \(result.secondaryText) [types: \(result.types.prefix(3).joined(separator: ", "))]")
        }

        return results
    }
}
