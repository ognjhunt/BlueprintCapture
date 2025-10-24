import Foundation
import CoreLocation

/// Caches a small set of discovered nearby places to make the first Nearby load instant
final class NearbySeedsStore {
    static let shared = NearbySeedsStore()
    private init() {}

    private var seeds: [PlaceDetailsLite] = []
    private var timestamp: Date = .distantPast

    func write(_ items: [PlaceDetailsLite]) {
        seeds = items
        timestamp = Date()
    }

    func read(maxAgeSeconds: TimeInterval = 300) -> [PlaceDetailsLite] {
        guard Date().timeIntervalSince(timestamp) <= maxAgeSeconds else { return [] }
        return seeds
    }
}

/// Fire-and-forget prefetch once we get user's location the first time
struct NearbyDiscoveryPrefetcher {
    private let discovery: GeminiDiscoveryServiceProtocol
    private let details: PlacesDetailsServiceProtocol

    init(discovery: GeminiDiscoveryServiceProtocol = GeminiDiscoveryService(),
         details: PlacesDetailsServiceProtocol = PlacesDetailsService()) {
        self.discovery = discovery
        self.details = details
    }

    func runOnceIfPossible(userLocation: CLLocationCoordinate2D, radiusMeters: Int = 1609, limit: Int = 25) {
        guard AppConfig.geminiAPIKey() != nil, AppConfig.placesAPIKey() != nil else { return }
        Task.detached(priority: .utility) {
            do {
                let candidates = try await discovery.discoverCandidates(
                    userLocation: userLocation,
                    radiusMeters: radiusMeters,
                    limit: limit,
                    categories: ["grocery", "electronics"],
                    sku: .B,
                    geohashHint: nil
                )
                guard !candidates.isEmpty else { return }
                let ids = candidates.map { $0.placeId }
                let detailsLite = try await details.fetchDetails(placeIds: ids)
                guard !detailsLite.isEmpty else { return }
                let first = Array(detailsLite.prefix(10))
                NearbySeedsStore.shared.write(first)
                print("🌱 [Prefetch] Seeded \(first.count) nearby items")
            } catch {
                print("⚠️ [Prefetch] Failed: \(error.localizedDescription)")
            }
        }
    }
}


