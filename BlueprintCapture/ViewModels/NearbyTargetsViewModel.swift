import Foundation
import CoreLocation
import SwiftUI
import Combine
import MapKit
#if canImport(Geohasher)
import Geohasher
#endif

@MainActor
final class NearbyTargetsViewModel: ObservableObject {
    enum SortOption: Int, CaseIterable { case highestPayout, nearest, highestDemand }
    enum RadiusMi: Double, CaseIterable { case half = 0.5, one = 1.0, five = 5.0, ten = 10.0 }
    enum Limit: Int, CaseIterable { case top10 = 10, top25 = 25 }
    enum State: Equatable { case idle, loading, loaded, error(String) }

    // Inputs
    @Published var selectedRadius: RadiusMi = .one { didSet { Task { await refresh() } } }
    @Published var selectedLimit: Limit = .top10 { didSet { Task { await refresh() } } }
    @Published var selectedSort: SortOption = .highestPayout { didSet { applySort() } }

    // Outputs
    @Published private(set) var state: State = .idle
    @Published private(set) var items: [NearbyItem] = []
    @Published private(set) var currentAddress: String?
    @Published private(set) var isUsingCustomSearchCenter: Bool = false
    @Published var isSearchingAddress: Bool = false
    @Published var addressSearchResults: [LocationSearchResult] = []

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

    struct LocationSearchResult: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let coordinate: CLLocationCoordinate2D
        let isEstablishment: Bool // true for businesses/stores, false for addresses
        let types: [String]
        var formatted: String { subtitle.isEmpty ? title : "\(title), \(subtitle)" }
    }

    // Services
    private let locationService: LocationServiceProtocol
    private let targetsAPI: TargetsAPIProtocol
    private let pricingAPI: PricingAPIProtocol
    private let streetService: StreetViewServiceProtocol
    private let geocoding: GeocodingServiceProtocol
    private let reservationService: ReservationServiceProtocol
    private let targetStateService: TargetStateServiceProtocol
    // private let discoveryService: GeminiDiscoveryServiceProtocol // 🔕 Gemini grounding temporarily disabled (using Places Nearby only)
    private let placesDetailsService: PlacesDetailsServiceProtocol
    private let placesAutocomplete: PlacesAutocompleteServiceProtocol
    private let notifications: NotificationServiceProtocol

    // Data
    private var pricing: [SKU: SkuPricing] = defaultPricing
    private var userLocation: CLLocation?
    private var streetViewCache: [String: (has: Bool, url: URL?)] = [:]
    @Published private(set) var reservations: [String: ReservationStatus] = [:]
    private var reservationObservers: [String: ReservationObservation] = [:]
    @Published private(set) var targetStates: [String: TargetState] = [:]
    private var stateObservers: [String: TargetStateObservation] = [:]
    private var addressTask: Task<Void, Never>?
    private var customSearchCenter: CLLocationCoordinate2D?
    private var placesSessionToken: String?
    private var searchDebounceTask: Task<Void, Never>?
    private var currentSearchQuery: String = ""

    init(locationService: LocationServiceProtocol = LocationService(),
         targetsAPI: TargetsAPIProtocol = MockTargetsAPI(),
         pricingAPI: PricingAPIProtocol = MockPricingAPI(),
         streetService: StreetViewServiceProtocol = StreetViewService(apiKeyProvider: { AppConfig.streetViewAPIKey() }),
         geocoding: GeocodingServiceProtocol = GeocodingService(),
         reservationService: ReservationServiceProtocol = ReservationService(),
         targetStateService: TargetStateServiceProtocol = TargetStateService(),
         // discoveryService: GeminiDiscoveryServiceProtocol = GeminiDiscoveryService(), // 🔕 Gemini grounding temporarily disabled (using Places Nearby only)
         placesDetailsService: PlacesDetailsServiceProtocol = PlacesDetailsService(),
         placesAutocomplete: PlacesAutocompleteServiceProtocol = PlacesAutocompleteService(),
         notifications: NotificationServiceProtocol = NotificationService()) {
         self.locationService = locationService
        self.targetsAPI = targetsAPI
        self.pricingAPI = pricingAPI
        self.streetService = streetService
        self.geocoding = geocoding
        self.reservationService = reservationService
        self.targetStateService = targetStateService
        // self.discoveryService = discoveryService
        self.placesDetailsService = placesDetailsService
        self.placesAutocomplete = placesAutocomplete
        self.notifications = notifications

        self.locationService.setListener { [weak self] loc in
            Task { @MainActor in
                self?.userLocation = loc
                // Kick off initial refresh as soon as we have a real location
                if loc != nil {
                    if let self = self {
                        // If we have prefetch seeds, use them immediately for instant UI
                        let seeds = NearbySeedsStore.shared.read()
                        if !seeds.isEmpty {
                            print("⚡️ [Nearby] Using \(seeds.count) prefetched seeds for instant list")
                            let targets = self.mapDetailsToTargets(details: seeds, fallbackSKU: .B, candidateScores: [:])
                            await self.applyTargetsImmediate(targets)
                        }
                        await self.refresh()
                    }
                    if let self = self { await self.updateCurrentAddress() }
                }
            }
        }
    }

    deinit {
        // Ensure observer cleanup even when deinit runs off-main
        Task { @MainActor in
            clearTargetStateObservers()
        }
    }

    func onAppear() {
        locationService.requestWhenInUseAuthorization()
        locationService.startUpdatingLocation()
        Task { await loadPricing() }
        // Show loading until the first location arrives; listener will trigger refresh
        state = .loading
        // Ask for notification permission early (one-time)
        Task { await notifications.requestAuthorizationIfNeeded() }
        logAPIStatus()
        startAddressUpdates()
        // If prefetched seeds exist and we don't have a location yet, show them
        let seeds = NearbySeedsStore.shared.read()
        if !seeds.isEmpty {
            Task { [weak self] in
                guard let self = self else { return }
                let targets = self.mapDetailsToTargets(details: seeds, fallbackSKU: .B, candidateScores: [:])
                await self.applyTargetsImmediate(targets)
            }
        }
    }

    func onDisappear() {
        locationService.stopUpdatingLocation()
        clearReservationObservers()
        stopAddressUpdates()
    }

    // MARK: - Logging

    private func logAPIStatus() {
        let placesKey = AppConfig.placesAPIKey()
        let streetViewKey = AppConfig.streetViewAPIKey()

        print("🔍 [Blueprint Nearby] API Configuration Status:")
        print("  ✅ Places API Key: \(placesKey != nil ? "✓ Present" : "✗ Missing")")
        print("  ✅ Street View API Key: \(streetViewKey != nil ? "✓ Present" : "✗ Missing")")

        if placesKey != nil {
            print("  🚀 Places Nearby pipeline ENABLED (Gemini temporarily disabled)")
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

    enum ReservationGuardError: LocalizedError {
        case tooFar(minutes: Int)
        case locationUnavailable

        var errorDescription: String? {
            switch self {
            case .tooFar(let minutes):
                return "This location is approximately \(minutes) minutes away. Reservations are limited to within \(AppConfig.maxReservationDriveMinutes()) minutes of your current location."
            case .locationUnavailable:
                return "We couldn’t determine your current location. Enable Location Services to reserve."
            }
        }
    }

    /// Attempts to reserve the target for one hour
    func reserveTarget(_ target: Target) async throws -> Reservation {
        // Pre‑guard: block reservations that are beyond configured travel time threshold
        if let origin = locationService.latestLocation ?? userLocation {
            let dest = CLLocationCoordinate2D(latitude: target.lat, longitude: target.lng)
            let maxMinutes = AppConfig.maxReservationDriveMinutes()
            // Try driving ETA first; fall back to air miles heuristic
            let etaMinutes = await estimateDriveMinutes(from: origin.coordinate, to: dest)
            if let eta = etaMinutes {
                if eta > maxMinutes { throw ReservationGuardError.tooFar(minutes: eta) }
            } else {
                let miles = origin.distance(from: CLLocation(latitude: dest.latitude, longitude: dest.longitude)) / 1609.34
                if miles > AppConfig.fallbackMaxReservationAirMiles() {
                    // Approximate minutes at 35 mph average urban speed
                    let approx = Int(ceil(miles / 35.0 * 60.0))
                    throw ReservationGuardError.tooFar(minutes: max(approx, maxMinutes + 1))
                }
            }
        } else {
            throw ReservationGuardError.locationUnavailable
        }

        let oneHour: TimeInterval = 60 * 60
        // Use new target_state path first; fall back to older service if fails
        do {
            let reservation = try await targetStateService.reserve(target: target, for: oneHour)
            reservations[target.id] = .reserved(until: reservation.reservedUntil)
            notifications.scheduleReservationExpiryNotification(target: target, at: reservation.reservedUntil)
            return reservation
        } catch {
            let reservation = try await reservationService.reserve(target: target, for: oneHour)
            reservations[target.id] = .reserved(until: reservation.reservedUntil)
            notifications.scheduleReservationExpiryNotification(target: target, at: reservation.reservedUntil)
            return reservation
        }
    }

    func reservationStatus(for targetId: String) -> ReservationStatus {
        // Prefer live target_state for UI badges when available
        if let state = targetStates[targetId] {
            switch state.status {
            case .reserved:
                if let until = state.reservedUntil { return .reserved(until: until) }
            case .in_progress:
                // Treat in_progress like reserved without countdown
                if let until = state.reservedUntil { return .reserved(until: until) }
                return .reserved(until: Date().addingTimeInterval(5 * 60))
            case .completed, .available:
                return .none
            }
        }
        return reservations[targetId] ?? reservationService.reservationStatus(for: targetId)
    }

    func cancelReservation(for targetId: String) async {
        await reservationService.cancelReservation(for: targetId)
        await targetStateService.cancelReservation(for: targetId)
        reservations.removeValue(forKey: targetId)
        notifications.cancelReservationExpiryNotification(for: targetId)
    }

    func checkIn(_ target: Target) async throws {
        let oneHour: TimeInterval = 60 * 60
        // Implicitly reserve to ensure target_state has full metadata (lat/lng/geohash/reservedBy)
        _ = try? await targetStateService.reserve(target: target, for: oneHour)
        try await targetStateService.checkIn(targetId: target.id)
        // User started mapping → do not send expiry notification anymore
        notifications.cancelReservationExpiryNotification(for: target.id)
    }

    // MARK: - Reservation expiry notifications
    func scheduleReservationExpiryNotification(for target: Target, at date: Date) {
        notifications.scheduleReservationExpiryNotification(target: target, at: date)
    }

    func cancelReservationExpiryNotification(for targetId: String) {
        notifications.cancelReservationExpiryNotification(for: targetId)
    }

    /// Returns the user's current active reservation if it exists (based on backend state), regardless of local UI state
    func fetchCurrentUserActiveReservation() async -> Reservation? {
        if let r = await targetStateService.fetchActiveReservationForCurrentUser() { return r }
        return await reservationService.fetchActiveReservationForCurrentUser()
    }

    private func loadPricing() async {
        do { pricing = try await pricingAPI.fetchPricing() } catch { pricing = defaultPricing }
    }

    func refresh() async {
        guard let loc = currentSearchLocation() else {
            state = .error("Location unavailable. Enable location or enter an address.")
            return
        }
        state = .loading
        do {
            let meters = Int(selectedRadius.rawValue * 1609.34)
            let limit = selectedLimit.rawValue
            var targets: [Target] = []
            // Use Places Nearby pipeline (Gemini disabled)
            if AppConfig.placesAPIKey() != nil {
                if let places = try? await loadUsingHybridPipeline(loc: loc, radiusMeters: meters, limit: limit) { // function now uses Places only
                    targets = places
                }
            }
            // Fallback to legacy pipeline if Places produced nothing
            if targets.isEmpty {
                print("📡 [Pipeline] Falling back to Legacy TargetsAPI...")
                targets = try await targetsAPI.fetchTargets(lat: loc.coordinate.latitude, lng: loc.coordinate.longitude, radiusMeters: meters, limit: limit)
                print("✅ [Legacy] Fetched \(targets.count) targets")
            } else {
                print("🎯 [Pipeline] Using Places results: \(targets.count) targets")
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

            // Merge with live target_state to filter and badge
            let ids = mapped.map { $0.id }
            let stateMap = await targetStateService.batchFetchStates(for: ids)
            self.targetStates = stateMap
            // Filter out completed and any reserved/in_progress targets owned by others
            let currentUserId = UserDeviceService.resolvedUserId()
            let visible = mapped.filter { item in
                guard let s = stateMap[item.id] else { return true }
                switch s.status {
                case .completed:
                    return false
                case .reserved:
                    if let owner = s.reservedBy, owner != currentUserId { return false }
                    return true
                case .in_progress:
                    // Hide if someone else is mapping; show if it's me
                    if let owner = s.checkedInBy ?? s.reservedBy {
                        return owner == currentUserId
                    }
                    // Unknown owner (legacy): hide by default
                    return false
                case .available:
                    return true
                }
            }
            self.items = visible
            // Refresh proximity notifications for the top results so we can nudge users when nearby
            let reservedIds = Set(visible.compactMap { item -> String? in
                switch reservationStatus(for: item.id) {
                case .reserved:
                    return item.id
                case .none:
                    return nil
                }
            })
            let metersPerMile = 1609.34
            let proximityTargets = visible.map { item -> ProximityNotificationTarget in
                let distanceMeters = item.target.computedDistanceMeters ?? (item.distanceMiles * metersPerMile)
                return ProximityNotificationTarget(
                    target: item.target,
                    distanceMeters: distanceMeters,
                    estimatedPayoutUsd: item.estimatedPayoutUsd,
                    isReserved: reservedIds.contains(item.id)
                )
            }
            notifications.scheduleProximityNotifications(for: proximityTargets, maxRegions: 10, radiusMeters: 200)
            applySort()
            // Attach observers for visible items
            updateTargetStateObservers(for: visible.map { $0.id })
            state = visible.isEmpty ? .loaded : .loaded
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
        updateReservationObservers(for: items.map { $0.id })
        updateTargetStateObservers(for: items.map { $0.id })
    }

    private func applyTargetsImmediate(_ targets: [Target]) async {
        let origin = currentSearchLocation() ?? CLLocation(latitude: userLocation?.coordinate.latitude ?? 0, longitude: userLocation?.coordinate.longitude ?? 0)
        let currentPricing = pricing
        let streetService = self.streetService
        do {
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
                arr.sort { $0.1 > $1.1 }
                return arr.map { $0.0 }
            }
            self.items = mapped
            applySort()
            state = .loaded
        } catch {
            // Ignore; normal refresh will follow
        }
    }

    // MARK: - Reservation pinning helpers
    /// Builds a NearbyItem for a given targetId even if it is outside current filters
    func buildItemForTargetId(_ targetId: String) async -> NearbyItem? {
        if let existing = items.first(where: { $0.id == targetId }) { return existing }

        // Attempt to retrieve coordinates from live state
        let stateMap = await targetStateService.batchFetchStates(for: [targetId])
        let state = stateMap[targetId]

        var lat: Double? = state?.lat
        var lng: Double? = state?.lng
        var displayName: String? = nil
        var address: String? = nil
        var types: [String] = []

        // If this is a Google Place ID, try to fetch details for nicer name/address
        if let details = try? await placesDetailsService.fetchDetails(placeIds: [targetId]), let d = details.first {
            displayName = d.displayName
            address = d.formattedAddress
            lat = lat ?? d.lat
            lng = lng ?? d.lng
            types = d.types ?? []
        }

        guard let latVal = lat, let lngVal = lng else { return nil }

        // Fill in an address if missing via reverse geocoding
        if address == nil {
            if let a = try? await geocoding.reverseGeocode(lat: latVal, lng: lngVal) { address = a }
        }

        let origin = currentSearchLocation() ?? locationService.latestLocation ?? userLocation ?? CLLocation(latitude: latVal, longitude: lngVal)
        let distanceMeters = origin.distance(from: CLLocation(latitude: latVal, longitude: lngVal))
        let miles = distanceMeters / 1609.34
        let target = Target(
            id: targetId,
            displayName: displayName ?? "Reserved location",
            sku: .B,
            lat: latVal,
            lng: lngVal,
            address: address,
            demandScore: dynamicDemand(forTypes: types),
            sizeSqFt: nil,
            category: types.first,
            computedDistanceMeters: distanceMeters
        )
        let payout = estimatedPayout(for: target, pricing: pricing)

        // Street View availability (optional)
        var hasSV = false
        var url: URL? = nil
        let cacheKey = "\(latVal.rounded(to: 5)),\(lngVal.rounded(to: 5))"
        if let cached = streetViewCache[cacheKey] {
            hasSV = cached.has
            url = cached.url
        } else if let service = streetService as? StreetViewServiceProtocol {
            hasSV = (try? await service.hasStreetView(lat: latVal, lng: lngVal)) ?? false
            url = hasSV ? service.imageURL(lat: latVal, lng: lngVal, size: CGSize(width: 600, height: 400)) : nil
            streetViewCache[cacheKey] = (hasSV, url)
        }

        return NearbyItem(id: targetId, target: target, distanceMiles: miles, estimatedPayoutUsd: payout, streetImageURL: url, hasStreetView: hasSV)
    }

    /// Estimates driving minutes using MapKit; returns nil if unable to compute quickly
    private func estimateDriveMinutes(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async -> Int? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        request.transportType = .automobile
        request.requestsAlternateRoutes = false

        return await withTaskGroup(of: Int?.self) { group -> Int? in
            // Calculation task
            group.addTask {
                await withCheckedContinuation { continuation in
                    let directions = MKDirections(request: request)
                    directions.calculate { response, _ in
                        if let eta = response?.routes.first?.expectedTravelTime { continuation.resume(returning: Int(ceil(eta / 60.0))) }
                        else { continuation.resume(returning: nil) }
                    }
                }
            }
            // Timeout task (3 seconds)
            group.addTask { try? await Task.sleep(nanoseconds: 3_000_000_000); return nil }
            for await result in group { if let val = result { return val } }
            return nil
        }
    }

    private func updateReservationObservers(for targetIds: [String]) {
        let ids = Set(targetIds)

        for (id, observer) in reservationObservers where !ids.contains(id) {
            observer.cancel()
            reservationObservers.removeValue(forKey: id)
            reservations.removeValue(forKey: id)
        }

        for id in ids where reservationObservers[id] == nil {
            let observation = reservationService.observeReservation(for: id) { [weak self] status in
                Task { @MainActor in
                    guard let self = self else { return }
                    switch status {
                    case .none:
                        self.reservations.removeValue(forKey: id)
                    case .reserved:
                        self.reservations[id] = status
                    }
                }
            }
            reservationObservers[id] = observation
        }
    }

    private func updateTargetStateObservers(for targetIds: [String]) {
        let ids = Set(targetIds)

        // Remove observers for items no longer visible
        for (id, obs) in stateObservers where !ids.contains(id) {
            obs.cancel()
            stateObservers.removeValue(forKey: id)
            targetStates.removeValue(forKey: id)
        }

        for id in ids where stateObservers[id] == nil {
            let obs = targetStateService.observeState(for: id) { [weak self] state in
                Task { @MainActor in
                    guard let self = self else { return }
                    if let state = state {
                        self.targetStates[id] = state
                        // If it flipped to completed, remove from list
                        if state.status == .completed {
                            self.items.removeAll { $0.id == id }
                        }
                        // Hide if reserved/in_progress by another user
                        if state.status == .reserved || state.status == .in_progress {
                            let uid = UserDeviceService.resolvedUserId()
                            let owner = state.checkedInBy ?? state.reservedBy
                            if owner == nil || owner != uid {
                                self.items.removeAll { $0.id == id }
                            }
                        }
                        // If reservation expired, clear local reservation badge
                        if state.status == .available {
                            self.reservations.removeValue(forKey: id)
                        }
                    } else {
                        self.targetStates.removeValue(forKey: id)
                    }
                }
            }
            stateObservers[id] = obs
        }
    }

    @MainActor
    private func clearReservationObservers() {
        reservationObservers.values.forEach { $0.cancel() }
        reservationObservers.removeAll()
        reservations.removeAll()
    }

    @MainActor
    private func clearTargetStateObservers() {
        stateObservers.values.forEach { $0.cancel() }
        stateObservers.removeAll()
        targetStates.removeAll()
    }

    // MARK: - Address updates

    private func startAddressUpdates() {
        addressTask?.cancel()
        addressTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.updateCurrentAddress()
                try? await Task.sleep(nanoseconds: 60_000_000_000) // 60s
            }
        }
    }

    private func stopAddressUpdates() {
        addressTask?.cancel()
        addressTask = nil
    }

    private func updateCurrentAddress() async {
        // If user picked a custom center, keep showing that address and do not override
        if isUsingCustomSearchCenter { return }
        guard let loc = locationService.latestLocation ?? userLocation else { return }
        if let address = try? await geocoding.reverseGeocode(lat: loc.coordinate.latitude, lng: loc.coordinate.longitude) {
            await MainActor.run { self.currentAddress = address }
        }
    }
}

// MARK: - Hybrid Pipeline

extension NearbyTargetsViewModel {
    private func loadUsingHybridPipeline(loc: CLLocation, radiusMeters: Int, limit: Int) async throws -> [Target] {
        // Build categories from UI intent - retail & commercial properties with high demand (kept for reference)
        // let categories = [
        //     "grocery", "supermarket", "electronics", "shopping_mall",
        //     "department_store", "home_goods_store", "convenience_store",
        //     "pharmacy", "clothing_store"
        // ]
        // Use geohash hint if Geohasher package is available at runtime (unused while Gemini disabled)
        // let geohashHint = computeGeohash(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)

        // Ask for SKU B by default for higher payout, but we can adjust later
        // 🔕 Gemini grounded discovery temporarily disabled — using Places Nearby directly
        // if AppConfig.geminiAPIKey() != nil {
        //     print("📡 [Pipeline] Attempting Gemini grounded discovery...")
        //     do {
        //         let candidates = try await discoveryService.discoverCandidates(
        //             userLocation: loc.coordinate,
        //             radiusMeters: radiusMeters,
        //             limit: limit,
        //             categories: categories,
        //             sku: .B,
        //             geohashHint: geohashHint
        //         )
        //         if !candidates.isEmpty {
        //             print("✅ [Gemini] Found \(candidates.count) candidates")
        //             for c in candidates { print("   - \(c.name) [\(c.placeId)] types=\(c.types.joined(separator: ", ")) score=\(String(format: "%.2f", c.score ?? 0))") }
        //             let details = try await placesDetailsService.fetchDetails(placeIds: candidates.map { $0.placeId })
        //             if !details.isEmpty {
        //                 print("✅ [Places Details] Fetched \(details.count) place details")
        //                 for d in details { print("   • \(d.displayName) — \(d.formattedAddress ?? "(no address)") [\(d.placeId)] @ (\(d.lat), \(d.lng))") }
        //                 return mapDetailsToTargets(details: details, fallbackSKU: .B, candidateScores: Dictionary(uniqueKeysWithValues: candidates.map { ($0.placeId, $0.score) }))
        //             } else {
        //                 print("⚠️  [Places Details] Failed to fetch details for candidates")
        //             }
        //         } else {
        //             print("⚠️  [Gemini] No candidates returned")
        //         }
        //     } catch {
        //         print("❌ [Gemini] Error: \(error.localizedDescription)")
        //     }
        // } else {
        //     print("⏭️  [Pipeline] Gemini API key not configured, skipping")
        // }

        // Fallback 2: Google Places Nearby Search (types-based)
        print("📡 [Pipeline] Using Places Nearby Search…")
        let nearby = GooglePlacesNearby()
        do {
            // Places v1 includedTypes aligned to our prior demand targets
            let includedTypes: [String] = [
                // Valid Table A types for Nearby Search per Google docs
                // https://developers.google.com/maps/documentation/places/web-service/place-types
                "supermarket",
                "electronics_store",
                "shopping_mall",
                "department_store",
                "convenience_store",
                "pharmacy",
                "clothing_store"
            ]
            let nearbyPlaces = try await nearby.nearby(
                lat: loc.coordinate.latitude,
                lng: loc.coordinate.longitude,
                radiusMeters: radiusMeters,
                limit: 2,
                types: includedTypes
            )
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

    fileprivate func dynamicDemand(forTypes types: [String]) -> Double {
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

// MARK: - Custom search center & address search
extension NearbyTargetsViewModel {
    private func currentSearchLocation() -> CLLocation? {
        if let custom = customSearchCenter {
            return CLLocation(latitude: custom.latitude, longitude: custom.longitude)
        }
        return locationService.latestLocation ?? userLocation
    }

    func clearCustomSearchCenter() {
        customSearchCenter = nil
        isUsingCustomSearchCenter = false
        Task { await refresh() }
        Task { await updateCurrentAddress() }
    }

    func setCustomSearchCenter(coordinate: CLLocationCoordinate2D, address: String) {
        customSearchCenter = coordinate
        isUsingCustomSearchCenter = true
        currentAddress = address
        // Clear session token on selection (matching React solution approach)
        placesSessionToken = nil
        // Clear search results
        addressSearchResults = []
        Task { await refresh() }
    }

    /// Debounced address search with proper cleanup and state management
    /// Matches the approach from the React autocomplete solution
    func searchAddresses(query: String) async {
        // Cancel any pending search task
        searchDebounceTask?.cancel()
        
        // Update current query immediately
        currentSearchQuery = query
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Clear results if query is too short
        guard trimmed.count >= 3 else {
            await MainActor.run { 
                self.addressSearchResults = []
                self.isSearchingAddress = false
            }
            // Reset session token when clearing search
            placesSessionToken = nil
            return
        }
        
        // Set loading state immediately
        await MainActor.run { self.isSearchingAddress = true }
        
        // Create debounced search task (350ms delay matching React solution)
        searchDebounceTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 350_000_000) // 350ms
                
                // Check if this task was cancelled during sleep
                guard !Task.isCancelled else {
                    print("🔍 [Autocomplete] Search cancelled for '\(trimmed)'")
                    return
                }
                
                // Perform the actual search
                await performAddressSearch(query: trimmed)
            } catch {
                // Task was cancelled
                print("🔍 [Autocomplete] Search task cancelled")
            }
        }
    }
    
    /// Internal method that performs the actual autocomplete search
    /// This is called after debounce delay
    private func performAddressSearch(query: String) async {
        // Ensure session token exists (reuse across autocomplete requests, reset on selection)
        if placesSessionToken == nil {
            placesSessionToken = UUID().uuidString
            print("🔑 [Autocomplete] Created new session token: \(placesSessionToken ?? "")")
        }
        
        // Check if query still matches current query (prevent stale results)
        guard query == currentSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines) else {
            print("🔍 [Autocomplete] Query changed, skipping stale search for '\(query)'")
            await MainActor.run { self.isSearchingAddress = false }
            return
        }
        
        defer { 
            Task { @MainActor in 
                self.isSearchingAddress = false 
            } 
        }

        // Prefer Google Places Autocomplete if configured; otherwise fall back to MapKit
        if AppConfig.placesAPIKey() != nil {
            do {
                let origin = currentSearchLocation()?.coordinate
                let radius = Int(selectedRadius.rawValue * 1609.34)
                let suggestions = try await placesAutocomplete.autocomplete(
                    input: query,
                    sessionToken: placesSessionToken ?? UUID().uuidString,
                    origin: origin,
                    radiusMeters: radius
                )
                print("🔍 [Autocomplete] Got \(suggestions.count) suggestions for '\(query)'")
                
                // Check again if query is still current
                guard query == currentSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines) else {
                    print("🔍 [Autocomplete] Query changed after fetch, discarding results")
                    return
                }
                
                guard !suggestions.isEmpty else {
                    print("⚠️ [Autocomplete] No suggestions returned, falling back to MapKit")
                    throw NSError(domain: "AutocompleteError", code: -1, userInfo: nil)
                }
                
                let details = try await placesDetailsService.fetchDetails(placeIds: suggestions.map { $0.placeId })
                print("📋 [Places Details] Got details for \(details.count) of \(suggestions.count) suggestions")
                
                // Final check if query is still current before showing results
                guard query == currentSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines) else {
                    print("🔍 [Autocomplete] Query changed after details fetch, discarding results")
                    return
                }
                
                let detailById = Dictionary(uniqueKeysWithValues: details.map { ($0.placeId, $0) })
                let results: [LocationSearchResult] = suggestions.compactMap { s in
                    // If we have details, use them; otherwise use the suggestion text
                    if let d = detailById[s.placeId] {
                        let coord = CLLocationCoordinate2D(latitude: d.lat, longitude: d.lng)
                        let title = s.primaryText.isEmpty ? d.displayName : s.primaryText
                        let subtitle = s.secondaryText.isEmpty ? (d.formattedAddress ?? "") : s.secondaryText
                        
                        // Determine if this is an establishment (business/store) or just an address/location
                        let types = s.types.isEmpty ? (d.types ?? []) : s.types
                        let isEstablishment = isPlaceAnEstablishment(types: types)
                        
                        return LocationSearchResult(
                            title: title,
                            subtitle: subtitle,
                            coordinate: coord,
                            isEstablishment: isEstablishment,
                            types: types
                        )
                    } else {
                        // Fallback: use suggestion text alone (this will require reverse geocoding the place ID, but at least show it)
                        print("⚠️ [Autocomplete] Missing details for placeId \(s.placeId), using suggestion text only")
                        // For now, skip results without details since we need coordinates
                        return nil
                    }
                }
                
                // Sort results: establishments first (stores/businesses), then addresses
                let sorted = results.sorted { lhs, rhs in
                    if lhs.isEstablishment != rhs.isEstablishment {
                        return lhs.isEstablishment // establishments first
                    }
                    return false // keep original order within same category
                }
                
                print("✅ [Autocomplete] Displaying \(sorted.count) search results (\(sorted.filter { $0.isEstablishment }.count) establishments, \(sorted.filter { !$0.isEstablishment }.count) addresses)")
                await MainActor.run { self.addressSearchResults = Array(sorted.prefix(10)) }
                return
            } catch {
                print("❌ [Autocomplete] Error: \(error.localizedDescription)")
                // Fall through to MapKit fallback below
            }
        }

        // MapKit Fallback
        print("📍 [MapKit] Falling back to MapKit search for '\(query)'")
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        let search = MKLocalSearch(request: request)
        do {
            let response = try await search.start()
            
            // Final check if query is still current
            guard query == currentSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines) else {
                print("📍 [MapKit] Query changed after fetch, discarding results")
                return
            }
            
            let results: [LocationSearchResult] = response.mapItems.prefix(8).compactMap { item in
                guard let coord = item.placemark.location?.coordinate else { return nil }
                let title = item.name ?? item.placemark.name ?? "Unknown"
                let subtitle = [item.placemark.locality, item.placemark.administrativeArea]
                    .compactMap { $0 }
                    .joined(separator: ", ")
                // Assume MapKit POI results are establishments
                let isEstablishment = item.pointOfInterestCategory != nil
                return LocationSearchResult(
                    title: title,
                    subtitle: subtitle,
                    coordinate: coord,
                    isEstablishment: isEstablishment,
                    types: []
                )
            }
            print("📍 [MapKit] Displaying \(results.count) search results")
            await MainActor.run { self.addressSearchResults = results }
        } catch {
            print("❌ [MapKit Search] Error: \(error.localizedDescription)")
            await MainActor.run { self.addressSearchResults = [] }
        }
    }
    
    /// Determines if a place is an establishment (business/store) vs just an address/location
    private func isPlaceAnEstablishment(types: [String]) -> Bool {
        let establishmentTypes = Set([
            "store", "supermarket", "shopping_mall", "convenience_store",
            "grocery_store", "department_store", "electronics_store",
            "clothing_store", "pharmacy", "gas_station", "restaurant",
            "cafe", "bar", "lodging", "establishment", "point_of_interest",
            "food", "school", "hospital", "bank", "post_office",
            "gym", "hair_care", "beauty_salon", "car_dealer", "car_rental",
            "car_repair", "car_wash", "veterinary_care", "meal_takeaway",
            "meal_delivery", "bakery", "book_store", "furniture_store",
            "hardware_store", "home_goods_store", "jewelry_store",
            "liquor_store", "pet_store", "shoe_store", "store",
            "shopping_center"
        ])
        return types.contains(where: { establishmentTypes.contains($0) })
    }
}
