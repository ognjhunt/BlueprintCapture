import Foundation
import CoreLocation
import SwiftUI
import Combine

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

    // Data
    private var pricing: [SKU: SkuPricing] = defaultPricing
    private var userLocation: CLLocation?
    private var streetViewCache: [String: (has: Bool, url: URL?)] = [:]

    init(locationService: LocationServiceProtocol = LocationService(),
         targetsAPI: TargetsAPIProtocol = MockTargetsAPI(),
         pricingAPI: PricingAPIProtocol = MockPricingAPI(),
         streetService: StreetViewServiceProtocol = StreetViewService(apiKeyProvider: { AppConfig.streetViewAPIKey() }),
         geocoding: GeocodingServiceProtocol = GeocodingService()) {
        self.locationService = locationService
        self.targetsAPI = targetsAPI
        self.pricingAPI = pricingAPI
        self.streetService = streetService
        self.geocoding = geocoding

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
    }

    func onDisappear() {
        locationService.stopUpdatingLocation()
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
            var targets = try await targetsAPI.fetchTargets(lat: loc.coordinate.latitude, lng: loc.coordinate.longitude, radiusMeters: meters, limit: limit)

            // Fill missing addresses with reverse geocode (throttled service already)
            for i in targets.indices {
                if targets[i].address == nil {
                    if let a = try? await geocoding.reverseGeocode(lat: targets[i].lat, lng: targets[i].lng) {
                        targets[i] = Target(
                            id: targets[i].id,
                            displayName: targets[i].displayName,
                            sku: targets[i].sku,
                            lat: targets[i].lat,
                            lng: targets[i].lng,
                            address: a,
                            demandScore: targets[i].demandScore,
                            sizeSqFt: targets[i].sizeSqFt,
                            category: targets[i].category,
                            computedDistanceMeters: targets[i].computedDistanceMeters
                        )
                    }
                }
            }

            let origin = CLLocation(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
            let currentPricing = pricing
            let streetService = self.streetService
            let mapped: [NearbyItem] = try await withThrowingTaskGroup(of: NearbyItem.self) { group in
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
                        return NearbyItem(id: t.id, target: t, distanceMiles: miles, estimatedPayoutUsd: payout, streetImageURL: url, hasStreetView: hasSV)
                    }
                }
                var arr: [NearbyItem] = []
                for try await item in group { arr.append(item) }
                return arr
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

private extension Double {
    func rounded(to places: Int) -> Double {
        let pow10 = pow(10.0, Double(places))
        return (self * pow10).rounded() / pow10
    }
}


