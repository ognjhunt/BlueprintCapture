import Foundation
import CoreLocation

struct PlaceDetailsLite: Codable, Equatable {
    let placeId: String
    let displayName: String
    let formattedAddress: String?
    let lat: Double
    let lng: Double
    let types: [String]?
}

protocol PlacesDetailsServiceProtocol {
    func fetchDetails(placeIds: [String]) async throws -> [PlaceDetailsLite]
}

final class PlacesDetailsService: PlacesDetailsServiceProtocol {
    private let backend: NearbyProxyBackendService

    init(
        backend: NearbyProxyBackendService = .shared
    ) {
        self.backend = backend
    }

    enum ServiceError: Error { case featureDisabled }

    /// Batch Place Details (New) with minimal field mask
    func fetchDetails(placeIds: [String]) async throws -> [PlaceDetailsLite] {
        guard !placeIds.isEmpty else { return [] }
        guard RuntimeConfig.current.availability(for: .nearbyDiscovery).isEnabled else {
            throw ServiceError.featureDisabled
        }
        let response = try await backend.fetchDetails(placeIds: placeIds)
        return response.places.map(\.placeDetailsLite)
    }
}

final class MockPlacesDetailsService: PlacesDetailsServiceProtocol {
    func fetchDetails(placeIds: [String]) async throws -> [PlaceDetailsLite] {
        return placeIds.map { id in
            PlaceDetailsLite(
                placeId: id,
                displayName: ["Center Plaza", "Community Center", "Premium Shopping", "Metro Market", "Town Square"].randomElement()!,
                formattedAddress: [
                    "258 Poplar Street",
                    "321 Maple Drive",
                    "987 Spruce Way",
                    "1123 Market St, Suite 100"
                ].randomElement(),
                lat: 37.3317 + Double.random(in: -0.01...0.01),
                lng: -122.0301 + Double.random(in: -0.01...0.01),
                types: ["shopping_mall", "grocery_or_supermarket", "electronics_store"]
            )
        }
    }
}
