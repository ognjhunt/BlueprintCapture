import Foundation
import CoreLocation
import Testing
@testable import BlueprintCapture

struct NearbyCandidateDiscoveryServiceTests {

    @Test
    func placesNearbyProviderReturnsStructuredPlaces() async throws {
        let places = [
            PlaceDetailsLite(
                placeId: "place-1",
                displayName: "Westside Warehouse",
                formattedAddress: "100 Logistics Way",
                lat: 35.99,
                lng: -78.90,
                types: ["warehouse_store"]
            )
        ]
        let service = NearbyCandidateDiscoveryService(
            placesNearby: StubPlacesNearby(result: .success(places)),
            geminiDiscovery: StubGeminiDiscovery(result: .success([])),
            runtimeConfigProvider: {
                RuntimeConfig.load(environment: [
                    "BLUEPRINT_ENABLE_NEARBY_DISCOVERY": "true",
                    "BLUEPRINT_NEARBY_DISCOVERY_PROVIDER": "places_nearby"
                ])
            }
        )

        let discovered = try await service.discoverCandidatePlaces(
            userLocation: CLLocationCoordinate2D(latitude: 35.99, longitude: -78.90),
            radiusMeters: 1609,
            limit: 8,
            includedTypes: ["warehouse_store"]
        )

        #expect(discovered == places)
    }

    @Test
    func geminiFallbackRunsWhenPlacesNearbyFails() async throws {
        let geminiCandidates = [
            GeminiPlaceCandidate(
                placeId: "place-2",
                name: "Hilton San Francisco Financial District",
                formattedAddress: "750 Kearny St, San Francisco, CA 94108",
                lat: 37.7955,
                lng: -122.4050,
                types: ["lodging", "store"],
                score: 0.74,
                siteType: "hospitality",
                reasoning: "Commercially useful nearby venue."
            )
        ]
        let service = NearbyCandidateDiscoveryService(
            placesNearby: StubPlacesNearby(result: .failure(StubError.failed)),
            geminiDiscovery: StubGeminiDiscovery(result: .success(geminiCandidates)),
            runtimeConfigProvider: {
                RuntimeConfig.load(environment: [
                    "BLUEPRINT_ENABLE_NEARBY_DISCOVERY": "true",
                    "BLUEPRINT_NEARBY_DISCOVERY_PROVIDER": "places_nearby",
                    "BLUEPRINT_ENABLE_GEMINI_MAPS_GROUNDING_FALLBACK": "true"
                ])
            }
        )

        let discovered = try await service.discoverCandidatePlaces(
            userLocation: CLLocationCoordinate2D(latitude: 37.7937, longitude: -122.3965),
            radiusMeters: 1609,
            limit: 8,
            includedTypes: ["store"]
        )

        #expect(discovered == geminiCandidates.map(\.placeDetailsLite))
    }

    @Test
    func geminiMapsProviderCanBePrimaryWithoutFallback() async throws {
        let geminiCandidates = [
            GeminiPlaceCandidate(
                placeId: "place-3",
                name: "Target",
                formattedAddress: "789 Mission St, San Francisco, CA 94103",
                lat: 37.7846,
                lng: -122.4035,
                types: ["department_store", "store"],
                score: 0.81,
                siteType: "retail",
                reasoning: "Large commercial venue aligned with nearby capture demand."
            )
        ]
        let service = NearbyCandidateDiscoveryService(
            placesNearby: StubPlacesNearby(result: .success([])),
            geminiDiscovery: StubGeminiDiscovery(result: .success(geminiCandidates)),
            runtimeConfigProvider: {
                RuntimeConfig.load(environment: [
                    "BLUEPRINT_ENABLE_NEARBY_DISCOVERY": "true",
                    "BLUEPRINT_NEARBY_DISCOVERY_PROVIDER": "gemini_maps_grounding"
                ])
            }
        )

        let discovered = try await service.discoverCandidatePlaces(
            userLocation: CLLocationCoordinate2D(latitude: 37.7937, longitude: -122.3965),
            radiusMeters: 1609,
            limit: 8,
            includedTypes: ["department_store", "store"]
        )

        #expect(discovered == geminiCandidates.map(\.placeDetailsLite))
    }
}

private enum StubError: Error {
    case failed
}

private struct StubPlacesNearby: PlacesNearbyProtocol {
    let result: Result<[PlaceDetailsLite], Error>

    func nearby(lat: Double, lng: Double, radiusMeters: Int, limit: Int, types: [String]) async throws -> [PlaceDetailsLite] {
        try result.get()
    }
}

private struct StubGeminiDiscovery: GeminiDiscoveryServiceProtocol {
    let result: Result<[GeminiPlaceCandidate], Error>

    func discoverCandidates(
        userLocation: CLLocationCoordinate2D,
        radiusMeters: Int,
        limit: Int,
        categories: [String],
        sku: SKU,
        geohashHint: String?
    ) async throws -> [GeminiPlaceCandidate] {
        try result.get()
    }
}
