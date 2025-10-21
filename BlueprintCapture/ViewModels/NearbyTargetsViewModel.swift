import Foundation
import CoreLocation
import SwiftUI
import Combine
#if canImport(Geohasher)
import Geohasher
#endif

@MainActor
final class NearbyTargetsViewModel: ObservableObject {
    enum SortOption: Int, CaseIterable { case highestPayout, nearest, highestDemand }
    enum RadiusMi: Double, CaseIterable { case half = 0.5, one = 1.0, five = 5.0 }
    enum Limit: Int, CaseIterable { case top10 = 10, top25 = 25 }
    enum State { case idle, loading, loaded, error(String) }

    // Inputs
    @Published var selectedRadius: RadiusMi = .one { didSet { Task { await refresh() } } }
    @Published var selectedLimit: Limit = .top10 { didSet { Task { await refresh() } } }
    @Published var selectedSort: SortOption = .highestPayout { didSet { applySort() } }

    // Outputs
    @Published private(set) var state: State = .idle
    @Published private(set) var items: [NearbyItem] = []

    struct NearbyItem: Identifiable, Equatable {
        let id: String
        let target: Target
        let distanceMiles: Double
        let estimatedPayoutUsd: Int
        let streetImageURL: URL?
        let hasStreetView: Bool
        var accessibilityLabel: String {
            "\(target.displayName), SKU \(target.sku.rawValue), payout $\(estimatedPayoutUsd), distance \(String(format: "%.1f", distanceMiles)) miles"
        }
    }

    // Services
    private let locationService: LocationServiceProtocol
    private let targetsAPI: TargetsAPIProtocol
    private let pricingAPI: PricingAPIProtocol
    private let streetService: StreetViewServiceProtocol
    private let geocoding: GeocodingServiceProtocol
    private let reservationService: ReservationServiceProtocol
    private let discoveryService: GeminiDiscoveryServiceProtocol
    private let placesDetailsService: PlacesDetailsServiceProtocol

    // Data
    private var pricing: [SKU: SkuPricing] = defaultPricing
    private var userLocation: CLLocation?
    private var streetViewCache: [String: (has: Bool, url: URL?)] = [:]

    init(locationService: LocationServiceProtocol = LocationService(),
         targetsAPI: TargetsAPIProtocol = MockTargetsAPI(),
         pricingAPI: PricingAPIProtocol = MockPricingAPI(),
         streetService: StreetViewServiceProtocol = StreetViewService(apiKeyProvider: { AppConfig.streetViewAPIKey() }),
         geocoding: GeocodingServiceProtocol = GeocodingService(),
         reservationService: ReservationServiceProtocol = MockReservationService(),
         discoveryService: GeminiDiscoveryServiceProtocol = GeminiDiscoveryService(),
         placesDetailsService: PlacesDetailsServiceProtocol = PlacesDetailsService()) {
        self.locationService = locationService
        self.targetsAPI = targetsAPI
        self.pricingAPI = pricingAPI
        self.streetService = streetService
        self.geocoding = geocoding
        self.reservationService = reservationService
        self.discoveryService = discoveryService
        self.placesDetailsService = placesDetailsService

        self.locationService.setListener { [weak self] loc in
            Task { @MainActor in
                self?.userLocation = loc
            }
        }
    }

    func onAppear() {
        locationService.requestWhenInUseAuthorization()
        locationService.startUpdatingLocation()
        Task { await loadPricing() }
        Task { await refresh() }
        logAPIStatus()
    }

    func onDisappear() {
        locationService.stopUpdatingLocation()
    }

    // MARK: - Logging

    private func logAPIStatus() {
        let geminiKey = AppConfig.geminiAPIKey()
        let placesKey = AppConfig.placesAPIKey()
        let streetViewKey = AppConfig.streetViewAPIKey()

        print("🔍 [Blueprint Nearby] API Configuration Status:")
        print("  ✅ Gemini API Key: \(geminiKey != nil ? "✓ Present" : "✗ Missing")")
        print("  ✅ Places API Key: \(placesKey != nil ? "✓ Present" : "✗ Missing")")
        print("  ✅ Street View API Key: \(streetViewKey != nil ? "✓ Present" : "✗ Missing")")

        if geminiKey != nil && placesKey != nil {
            print("  🚀 Hybrid pipeline ENABLED: Gemini → Places Nearby → Legacy")
        } else if placesKey != nil {
            print("  🚀 Places Nearby fallback ENABLED (Gemini unavailable)")
        } else {
            print("  ⚠️  No Google APIs configured; using Legacy TargetsAPI only")
        }
    }

    // MARK: - Actions

    /// Returns true if user's current location is within the on-site threshold of the target
    func isOnSite(_ target: Target, thresholdMeters: CLLocationDistance = 150) -> Bool {
        guard let user = locationService.latestLocation ?? userLocation else { return false }
        let targetLocation = CLLocation(latitude: target.lat, longitude: target.lng)
        return user.distance(from: targetLocation) <= thresholdMeters
    }

    /// Attempts to reserve the target for one hour
    func reserveTarget(_ target: Target) async throws -> Reservation {
        let oneHour: TimeInterval = 60 * 60
        let reservation = try await reservationService.reserve(target: target, for: oneHour)
        return reservation
    }

    func reservationStatus(for targetId: String) -> ReservationStatus {
        reservationService.reservationStatus(for: targetId)
    }

    func cancelReservation(for targetId: String) async {
        await reservationService.cancelReservation(for: targetId)
    }

    private func loadPricing() async {
        do { pricing = try await pricingAPI.fetchPricing() } catch { pricing = defaultPricing }
    }

    func refresh() async {
        guard let loc = locationService.latestLocation ?? userLocation else {
            state = .error("Location unavailable. Enable location or enter an address.")
            return
        }
        state = .loading
        do {
            let meters = Int(selectedRadius.rawValue * 1609.34)
            let limit = selectedLimit.rawValue
            var targets: [Target] = []
            // Try the hybrid Gemini + Places pipeline first
            if AppConfig.geminiAPIKey() != nil, AppConfig.placesAPIKey() != nil {
                if let hybrid = try? await loadUsingHybridPipeline(loc: loc, radiusMeters: meters, limit: limit) {
                    targets = hybrid
                }
            }
            // Fallback to legacy pipeline if hybrid produced nothing
            if targets.isEmpty {
                print("📡 [Pipeline] Falling back to Legacy TargetsAPI...")
                targets = try await targetsAPI.fetchTargets(lat: loc.coordinate.latitude, lng: loc.coordinate.longitude, radiusMeters: meters, limit: limit)
                print("✅ [Legacy] Fetched \(targets.count) targets")
            } else {
                print("🎯 [Pipeline] Using hybrid results: \(targets.count) targets")
            }

            // Parallelize missing address resolution instead of sequential
            let geocoding = self.geocoding
            let targetsToGeocode = targets.indices.filter { targets[$0].address == nil }
            
            if !targetsToGeocode.isEmpty {
                let geocoded: [(index: Int, address: String)] = try await withThrowingTaskGroup(of: (Int, String)?.self) { group in
                    for i in targetsToGeocode {
                        group.addTask {
                            if let a = try? await geocoding.reverseGeocode(lat: targets[i].lat, lng: targets[i].lng) {
                                return (i, a)
                            }
                            return nil
                        }
                    }
                    var results: [(Int, String)] = []
                    for try await result in group {
                        if let result = result {
                            results.append(result)
                        }
                    }
                    return results
                }
                
                // Apply geocoded addresses back to targets
                for (index, address) in geocoded {
                    targets[index] = Target(
                        id: targets[index].id,
                        displayName: targets[index].displayName,
                        sku: targets[index].sku,
                        lat: targets[index].lat,
                        lng: targets[index].lng,
                        address: address,
                        demandScore: targets[index].demandScore,
                        sizeSqFt: targets[index].sizeSqFt,
                        category: targets[index].category,
                        computedDistanceMeters: targets[index].computedDistanceMeters
                    )
                }
            }

            let origin = CLLocation(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
            let currentPricing = pricing
            let streetService = self.streetService
            let mapped: [NearbyItem] = try await withThrowingTaskGroup(of: (NearbyItem, Double).self) { group in
                for t in targets {
                    group.addTask { @MainActor [weak self] in
                        let distanceMeters = origin.distance(from: CLLocation(latitude: t.lat, longitude: t.lng))
                        let miles = distanceMeters / 1609.34
                        let payout = estimatedPayout(for: t, pricing: currentPricing)
                        let cacheKey = "\(t.lat.rounded(to: 5)),\(t.lng.rounded(to: 5))"
                        var hasSV = false
                        var url: URL? = nil
                        if let cached = self?.streetViewCache[cacheKey] {
                            hasSV = cached.has
                            url = cached.url
                        } else if let service = streetService as? StreetViewServiceProtocol {
                            hasSV = (try? await service.hasStreetView(lat: t.lat, lng: t.lng)) ?? false
                            url = hasSV ? service.imageURL(lat: t.lat, lng: t.lng, size: CGSize(width: 600, height: 400)) : nil
                            self?.streetViewCache[cacheKey] = (hasSV, url)
                        }
                        // Hybrid score: payout × demand × proximity × coverage
                        let demand = max(0.3, min(1.0, t.demandScore ?? 0.6))
                        let proximity = max(0.3, 1.0 - min(1.0, miles / (self?.selectedRadius.rawValue ?? 1.0)))
                        let coverage = hasSV ? 1.0 : 0.7
                        let score = Double(payout) * demand * proximity * coverage
                        let item = NearbyItem(id: t.id, target: t, distanceMiles: miles, estimatedPayoutUsd: payout, streetImageURL: url, hasStreetView: hasSV)
                        return (item, score)
                    }
                }
                var arr: [(NearbyItem, Double)] = []
                for try await tuple in group { arr.append(tuple) }
                // Pre-rank by hybrid score before presenting
                arr.sort { $0.1 > $1.1 }
                // Return just items
                return arr.map { $0.0 }
            }

            self.items = mapped
            applySort()
            state = mapped.isEmpty ? .loaded : .loaded
        } catch {
            state = .error("Failed to load targets. Please try again.")
        }
    }

    private func applySort() {
        switch selectedSort {
        case .highestPayout:
            items.sort { $0.estimatedPayoutUsd > $1.estimatedPayoutUsd }
        case .nearest:
            items.sort { $0.distanceMiles < $1.distanceMiles }
        case .highestDemand:
            items.sort { ($0.target.demandScore ?? 0) > ($1.target.demandScore ?? 0) }
        }
        if items.count > selectedLimit.rawValue {
            items = Array(items.prefix(selectedLimit.rawValue))
        }
    }
}

// MARK: - Hybrid Pipeline

extension NearbyTargetsViewModel {
    private func loadUsingHybridPipeline(loc: CLLocation, radiusMeters: Int, limit: Int) async throws -> [Target] {
        // Build categories from UI intent; for now favor Grocery and Electronics
        let categories = ["grocery", "electronics"]
        // Use geohash hint if Geohasher package is available at runtime
        let geohashHint = computeGeohash(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)

        // Ask for SKU B by default for higher payout, but we can adjust later
        if AppConfig.geminiAPIKey() != nil {
            print("📡 [Pipeline] Attempting Gemini grounded discovery...")
            do {
                let candidates = try await discoveryService.discoverCandidates(
                    userLocation: loc.coordinate,
                    radiusMeters: radiusMeters,
                    limit: limit,
                    categories: categories,
                    sku: .B,
                    geohashHint: geohashHint
                )
                if !candidates.isEmpty {
                    print("✅ [Gemini] Found \(candidates.count) candidates")
                    let details = try await placesDetailsService.fetchDetails(placeIds: candidates.map { $0.placeId })
                    if !details.isEmpty {
                        print("✅ [Places Details] Fetched \(details.count) place details")
                        return mapDetailsToTargets(details: details, fallbackSKU: .B, candidateScores: Dictionary(uniqueKeysWithValues: candidates.map { ($0.placeId, $0.score) }))
                    } else {
                        print("⚠️  [Places Details] Failed to fetch details for candidates")
                    }
                } else {
                    print("⚠️  [Gemini] No candidates returned")
                }
            } catch {
                print("❌ [Gemini] Error: \(error.localizedDescription)")
            }
        } else {
            print("⏭️  [Pipeline] Gemini API key not configured, skipping")
        }

        // Fallback 2: Google Places Nearby Search (types-based)
        print("📡 [Pipeline] Attempting Places Nearby Search...")
        let nearby = GooglePlacesNearby()
        do {
            let nearbyPlaces = try await nearby.nearby(lat: loc.coordinate.latitude, lng: loc.coordinate.longitude, radiusMeters: radiusMeters, limit: limit, types: ["grocery_or_supermarket", "electronics_store"])
            if !nearbyPlaces.isEmpty {
                print("✅ [Places Nearby] Found \(nearbyPlaces.count) places")
                return mapDetailsToTargets(details: nearbyPlaces, fallbackSKU: .B, candidateScores: [:])
            } else {
                print("⚠️  [Places Nearby] No places returned")
            }
        } catch {
            print("❌ [Places Nearby] Error: \(error.localizedDescription)")
        }

        print("⏭️  [Pipeline] All Google APIs exhausted, returning empty (will fallback to Legacy TargetsAPI)")
        return []
    }

    private func mapDetailsToTargets(details: [PlaceDetailsLite], fallbackSKU: SKU, candidateScores: [String: Double?]) -> [Target] {
        return details.map { d in
            let demand = candidateScores[d.placeId] ?? nil
            return Target(
                id: d.placeId,
                displayName: d.displayName,
                sku: fallbackSKU,
                lat: d.lat,
                lng: d.lng,
                address: d.formattedAddress,
                demandScore: demand ?? dynamicDemand(forTypes: d.types ?? []),
                sizeSqFt: nil,
                category: d.types?.first,
                computedDistanceMeters: nil
            )
        }
    }

    private func dynamicDemand(forTypes types: [String]) -> Double {
        // Type-driven baseline demand learned from AI lab requests (tweak as needed)
        // 0.0 - 1.0 scale
        let table: [String: Double] = [
            "electronics_store": 0.95,
            "shopping_mall": 0.9,
            "grocery_or_supermarket": 0.85,
            "supermarket": 0.85,
            "department_store": 0.8,
            "warehouse_store": 0.8,
            "home_goods_store": 0.7,
            "convenience_store": 0.65,
            "gas_station": 0.6,
            "pharmacy": 0.6,
            "clothing_store": 0.55
        ]
        let best = types.compactMap { table[$0] }.max() ?? 0.6
        // Slight lift for multiple high-demand categories present
        let extras = types.compactMap { table[$0] }.sorted(by: >).dropFirst().prefix(2)
        let bonus = extras.reduce(0.0) { $0 + ($1 - 0.5) * 0.1 }
        return min(0.99, max(0.3, best + bonus))
    }

    private func computeGeohash(latitude: Double, longitude: Double) -> String? {
        #if canImport(Geohasher)
        // Precision 7 ≈ neighborhood level (~153m)
        return Geohasher.encode(latitude: latitude, longitude: longitude, length: 7)
        #else
        // Simple, portable hint when Geohasher isn't available at runtime
        let latStr = String(format: "%.3f", latitude)
        let lngStr = String(format: "%.3f", longitude)
        return "\(latStr),\(lngStr)"
        #endif
    }
}

private extension Double {
    func rounded(to places: Int) -> Double {
        let pow10 = pow(10.0, Double(places))
        return (self * pow10).rounded() / pow10
    }
}


