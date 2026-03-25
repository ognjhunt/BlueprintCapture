import Foundation
import CoreLocation

struct GeminiPlaceCandidate: Codable, Equatable {
    let placeId: String
    let name: String
    let formattedAddress: String?
    let lat: Double
    let lng: Double
    let types: [String]
    let score: Double?
    let siteType: String?
    let reasoning: String?

    var placeDetailsLite: PlaceDetailsLite {
        PlaceDetailsLite(
            placeId: placeId,
            displayName: name,
            formattedAddress: formattedAddress,
            lat: lat,
            lng: lng,
            types: types
        )
    }
}

protocol GeminiDiscoveryServiceProtocol {
    func discoverCandidates(
        userLocation: CLLocationCoordinate2D,
        radiusMeters: Int,
        limit: Int,
        categories: [String],
        sku: SKU,
        geohashHint: String?
    ) async throws -> [GeminiPlaceCandidate]
}

final class GeminiDiscoveryService: GeminiDiscoveryServiceProtocol {
    private let backend: NearbyProxyBackendService

    init(
        backend: NearbyProxyBackendService = .shared
    ) {
        self.backend = backend
    }

    enum ServiceError: LocalizedError {
        case featureDisabled

        var errorDescription: String? {
            switch self {
            case .featureDisabled:
                return "Live nearby discovery is disabled for this build."
            }
        }
    }

    func discoverCandidates(
        userLocation: CLLocationCoordinate2D,
        radiusMeters: Int,
        limit: Int,
        categories: [String],
        sku: SKU,
        geohashHint: String?
    ) async throws -> [GeminiPlaceCandidate] {
        guard RuntimeConfig.current.availability(for: .nearbyDiscovery).isEnabled else {
            throw ServiceError.featureDisabled
        }
        let response = try await backend.discover(
            userLocation: userLocation,
            radiusMeters: radiusMeters,
            limit: limit,
            includedTypes: categories,
            providerHint: .geminiMapsGrounding,
            allowFallback: false
        )
        return Array(response.places.prefix(limit)).map { place in
            GeminiPlaceCandidate(
                placeId: place.placeId,
                name: place.displayName,
                formattedAddress: place.formattedAddress,
                lat: place.lat,
                lng: place.lng,
                types: place.placeTypes,
                score: nil,
                siteType: nil,
                reasoning: nil
            )
        }
    }
}

final class MockGeminiDiscoveryService: GeminiDiscoveryServiceProtocol {
    func discoverCandidates(
        userLocation: CLLocationCoordinate2D,
        radiusMeters: Int,
        limit: Int,
        categories: [String],
        sku: SKU,
        geohashHint: String?
    ) async throws -> [GeminiPlaceCandidate] {
        return (0..<limit).map { i in
            GeminiPlaceCandidate(
                placeId: "ChIJ_mock_\(i)",
                name: ["Center Plaza", "Community Center", "Premium Shopping", "Metro Market", "Town Square"].randomElement()!,
                formattedAddress: [
                    "258 Poplar Street",
                    "321 Maple Drive",
                    "987 Spruce Way",
                    "1123 Market St, Suite 100"
                ].randomElement(),
                lat: 37.3317 + Double.random(in: -0.01...0.01),
                lng: -122.0301 + Double.random(in: -0.01...0.01),
                types: ["shopping_mall", "grocery_or_supermarket", "electronics_store"],
                score: Double.random(in: 0.5...0.99),
                siteType: "retail",
                reasoning: "Commercially relevant nearby candidate."
            )
        }
    }
}
