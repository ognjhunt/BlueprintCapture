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
    private let discovery: NearbyCandidateDiscoveryServiceProtocol

    init(discovery: NearbyCandidateDiscoveryServiceProtocol = NearbyCandidateDiscoveryService()) {
        self.discovery = discovery
    }

    func runOnceIfPossible(userLocation: CLLocationCoordinate2D, radiusMeters: Int = 1609, limit: Int = 25) {
        guard RuntimeConfig.current.availability(for: .nearbyDiscovery).isEnabled else { return }
        Task(priority: .utility) {
            do {
                let detailsLite = try await discovery.discoverCandidatePlaces(
                    userLocation: userLocation,
                    radiusMeters: radiusMeters,
                    limit: limit,
                    includedTypes: ["supermarket", "electronics_store", "store"]
                )
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
