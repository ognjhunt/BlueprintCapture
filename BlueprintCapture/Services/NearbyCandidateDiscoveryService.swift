import Foundation
import CoreLocation

protocol NearbyCandidateDiscoveryServiceProtocol {
    func discoverCandidatePlaces(
        userLocation: CLLocationCoordinate2D,
        radiusMeters: Int,
        limit: Int,
        includedTypes: [String]
    ) async throws -> [PlaceDetailsLite]
}

final class NearbyCandidateDiscoveryService: NearbyCandidateDiscoveryServiceProtocol {
    private let placesNearby: PlacesNearbyProtocol
    private let geminiDiscovery: GeminiDiscoveryServiceProtocol
    private let runtimeConfigProvider: () -> RuntimeConfig

    init(
        placesNearby: PlacesNearbyProtocol = GooglePlacesNearby(),
        geminiDiscovery: GeminiDiscoveryServiceProtocol = GeminiDiscoveryService(),
        runtimeConfigProvider: @escaping () -> RuntimeConfig = { RuntimeConfig.current }
    ) {
        self.placesNearby = placesNearby
        self.geminiDiscovery = geminiDiscovery
        self.runtimeConfigProvider = runtimeConfigProvider
    }

    func discoverCandidatePlaces(
        userLocation: CLLocationCoordinate2D,
        radiusMeters: Int,
        limit: Int,
        includedTypes: [String]
    ) async throws -> [PlaceDetailsLite] {
        let config = runtimeConfigProvider()
        let primary = config.nearbyDiscoveryProvider
        let fallbackEnabled = config.enableGeminiMapsGroundingFallback
        SessionEventManager.shared.logInteraction(
            kind: "nearby_provider_selected",
            metadata: [
                "provider_hint": primary.rawValue,
                "fallback_enabled": fallbackEnabled,
                "radius_m": radiusMeters,
                "limit": limit
            ]
        )

        do {
            let primaryResults = try await discover(
                via: primary,
                userLocation: userLocation,
                radiusMeters: radiusMeters,
                limit: limit,
                includedTypes: includedTypes
            )
            if !primaryResults.isEmpty {
                return primaryResults
            }
            SessionEventManager.shared.logInteraction(
                kind: "nearby_zero_results",
                metadata: [
                    "provider_used": primary.rawValue,
                    "fallback_enabled": fallbackEnabled
                ]
            )
            guard fallbackEnabled else { return [] }
            let secondary = alternateProvider(for: primary)
            SessionEventManager.shared.logInteraction(
                kind: "nearby_fallback_used",
                metadata: [
                    "from_provider": primary.rawValue,
                    "to_provider": secondary.rawValue,
                    "reason": "primary_empty"
                ]
            )
            return try await discover(
                via: secondary,
                userLocation: userLocation,
                radiusMeters: radiusMeters,
                limit: limit,
                includedTypes: includedTypes
            )
        } catch {
            SessionEventManager.shared.logError(
                errorCode: "nearby_provider_failed",
                metadata: [
                    "provider_used": primary.rawValue,
                    "message": error.localizedDescription
                ]
            )
            guard fallbackEnabled else { throw error }
            let secondary = alternateProvider(for: primary)
            SessionEventManager.shared.logInteraction(
                kind: "nearby_fallback_used",
                metadata: [
                    "from_provider": primary.rawValue,
                    "to_provider": secondary.rawValue,
                    "reason": "primary_error"
                ]
            )
            return try await discover(
                via: secondary,
                userLocation: userLocation,
                radiusMeters: radiusMeters,
                limit: limit,
                includedTypes: includedTypes
            )
        }
    }

    private func discover(
        via provider: NearbyDiscoveryProvider,
        userLocation: CLLocationCoordinate2D,
        radiusMeters: Int,
        limit: Int,
        includedTypes: [String]
    ) async throws -> [PlaceDetailsLite] {
        switch provider {
        case .placesNearby:
            print("📡 [Nearby Discovery] Provider = Places Nearby Search")
            return try await placesNearby.nearby(
                lat: userLocation.latitude,
                lng: userLocation.longitude,
                radiusMeters: radiusMeters,
                limit: limit,
                types: includedTypes
            )
        case .geminiMapsGrounding:
            print("🧭 [Nearby Discovery] Provider = Gemini Maps Grounding")
            let candidates = try await geminiDiscovery.discoverCandidates(
                userLocation: userLocation,
                radiusMeters: radiusMeters,
                limit: limit,
                categories: includedTypes,
                sku: .B,
                geohashHint: nil
            )
            return Array(candidates.prefix(limit)).map(\.placeDetailsLite)
        }
    }

    private func alternateProvider(for provider: NearbyDiscoveryProvider) -> NearbyDiscoveryProvider {
        switch provider {
        case .placesNearby:
            return .geminiMapsGrounding
        case .geminiMapsGrounding:
            return .placesNearby
        }
    }
}
