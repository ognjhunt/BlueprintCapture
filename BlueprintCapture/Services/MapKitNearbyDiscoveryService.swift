import Foundation
import CoreLocation
import MapKit

final class MapKitNearbyDiscoveryService: PlacesNearbyProtocol {
    private let maxNaturalLanguageQueries = 8

    func nearby(lat: Double, lng: Double, radiusMeters: Int, limit: Int, types: [String]) async throws -> [PlaceDetailsLite] {
        guard RuntimeConfig.current.availability(for: .nearbyDiscovery).isEnabled else {
            throw GooglePlacesNearby.ServiceError.featureDisabled
        }
        guard limit > 0 else { return [] }

        let center = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        let radius = CLLocationDistance(max(100, radiusMeters))
        var candidates: [MapKitNearbyCandidate] = []

        let poiCategories = MapKitNearbyDiscoveryTransform.pointOfInterestCategories(for: types)
        if !poiCategories.isEmpty {
            let request = MKLocalPointsOfInterestRequest(center: center, radius: radius)
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: poiCategories)
            let response = try await MKLocalSearch(request: request).start()
            candidates.append(contentsOf: response.mapItems.map {
                MapKitNearbyCandidate(mapItem: $0, fallbackTypes: MapKitNearbyDiscoveryTransform.types(for: $0.pointOfInterestCategory))
            })
        }

        for query in MapKitNearbyDiscoveryTransform.naturalLanguageQueries(for: types).prefix(maxNaturalLanguageQueries) {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query.query
            request.region = MKCoordinateRegion(
                center: center,
                latitudinalMeters: radius * 2,
                longitudinalMeters: radius * 2
            )
            request.resultTypes = .pointOfInterest
            let response = try await MKLocalSearch(request: request).start()
            candidates.append(contentsOf: response.mapItems.map {
                let categoryTypes = MapKitNearbyDiscoveryTransform.types(for: $0.pointOfInterestCategory)
                return MapKitNearbyCandidate(
                    mapItem: $0,
                    fallbackTypes: MapKitNearbyDiscoveryTransform.mergedTypes(categoryTypes + query.types)
                )
            })
        }

        let origin = CLLocation(latitude: lat, longitude: lng)
        return MapKitNearbyDiscoveryTransform.places(
            from: candidates,
            origin: origin,
            limit: limit
        )
    }
}

struct MapKitNearbyCandidate {
    let name: String
    let formattedAddress: String?
    let coordinate: CLLocationCoordinate2D
    let types: [String]

    init(
        name: String,
        formattedAddress: String?,
        coordinate: CLLocationCoordinate2D,
        types: [String]
    ) {
        self.name = name
        self.formattedAddress = formattedAddress
        self.coordinate = coordinate
        self.types = types
    }

    init(mapItem: MKMapItem, fallbackTypes: [String]) {
        let placemark = mapItem.placemark
        self.name = mapItem.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.formattedAddress = MapKitNearbyDiscoveryTransform.formattedAddress(from: placemark)
        self.coordinate = placemark.coordinate
        self.types = fallbackTypes
    }
}

enum MapKitNearbyDiscoveryTransform {
    private static let duplicateDistanceMeters: CLLocationDistance = 75

    struct Query: Equatable {
        let query: String
        let types: [String]
    }

    static func places(from candidates: [MapKitNearbyCandidate], origin: CLLocation, limit: Int) -> [PlaceDetailsLite] {
        guard limit > 0 else { return [] }

        let sorted = candidates
            .filter { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
            .sorted {
                let lhs = CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
                    .distance(from: origin)
                let rhs = CLLocation(latitude: $1.coordinate.latitude, longitude: $1.coordinate.longitude)
                    .distance(from: origin)
                return lhs < rhs
            }

        var accepted: [MapKitNearbyCandidate] = []
        var seenIdentityKeys = Set<String>()

        for candidate in sorted {
            let identityKey = normalizedIdentityKey(for: candidate)
            let location = CLLocation(latitude: candidate.coordinate.latitude, longitude: candidate.coordinate.longitude)
            let isNearDuplicate = accepted.contains { existing in
                guard normalizedName(existing.name) == normalizedName(candidate.name) else { return false }
                let existingLocation = CLLocation(latitude: existing.coordinate.latitude, longitude: existing.coordinate.longitude)
                return existingLocation.distance(from: location) <= duplicateDistanceMeters
            }

            guard seenIdentityKeys.contains(identityKey) == false, isNearDuplicate == false else {
                continue
            }

            accepted.append(candidate)
            seenIdentityKeys.insert(identityKey)
            if accepted.count == limit { break }
        }

        return accepted.map { candidate in
            PlaceDetailsLite(
                placeId: placeId(for: candidate),
                displayName: candidate.name,
                formattedAddress: candidate.formattedAddress,
                lat: candidate.coordinate.latitude,
                lng: candidate.coordinate.longitude,
                types: mergedTypes(candidate.types)
            )
        }
    }

    static func pointOfInterestCategories(for types: [String]) -> [MKPointOfInterestCategory] {
        let normalizedTypes = Set(types.map(normalizedType))
        var categories: [MKPointOfInterestCategory] = []

        func include(_ category: MKPointOfInterestCategory, when aliases: [String]) {
            if aliases.contains(where: { normalizedTypes.contains($0) }) {
                categories.append(category)
            }
        }

        include(.foodMarket, when: ["supermarket", "grocery_or_supermarket", "grocery", "convenience_store"])
        include(.store, when: ["store", "shopping_mall", "department_store", "electronics_store", "hardware_store", "home_improvement_store", "home_goods_store", "furniture_store", "clothing_store", "warehouse_store", "retail_store"])
        include(.pharmacy, when: ["pharmacy", "drugstore"])

        if categories.isEmpty {
            categories = [.foodMarket, .store, .pharmacy]
        }

        var seen = Set<String>()
        return categories.filter { seen.insert($0.rawValue).inserted }
    }

    static func naturalLanguageQueries(for types: [String]) -> [Query] {
        let normalizedTypes = Set(types.map(normalizedType))
        let allQueries: [Query] = [
            Query(query: "supermarket", types: ["supermarket", "grocery_or_supermarket", "store"]),
            Query(query: "grocery", types: ["supermarket", "grocery_or_supermarket", "store"]),
            Query(query: "shopping mall", types: ["shopping_mall", "store"]),
            Query(query: "department store", types: ["department_store", "store"]),
            Query(query: "electronics store", types: ["electronics_store", "store"]),
            Query(query: "hardware store", types: ["hardware_store", "home_improvement_store", "store"]),
            Query(query: "pharmacy", types: ["pharmacy", "store"]),
            Query(query: "retail store", types: ["store"])
        ]

        let selected = allQueries.filter { query in
            query.types.contains(where: { normalizedTypes.contains(normalizedType($0)) })
        }

        return selected.isEmpty ? allQueries : selected
    }

    static func types(for category: MKPointOfInterestCategory?) -> [String] {
        switch category {
        case .foodMarket:
            return ["supermarket", "grocery_or_supermarket", "store"]
        case .store:
            return ["store"]
        case .pharmacy:
            return ["pharmacy", "store"]
        default:
            return ["store"]
        }
    }

    static func mergedTypes(_ types: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for type in types.map(normalizedType).filter({ !$0.isEmpty }) {
            if seen.insert(type).inserted {
                result.append(type)
            }
        }
        return result.isEmpty ? ["store"] : result
    }

    static func formattedAddress(from placemark: MKPlacemark) -> String? {
        let street = [placemark.subThoroughfare, placemark.thoroughfare]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let locality = [placemark.locality, placemark.administrativeArea]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        let address = [street, locality, placemark.postalCode]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        return address.isEmpty ? placemark.title : address
    }

    private static func placeId(for candidate: MapKitNearbyCandidate) -> String {
        let raw = [
            normalizedName(candidate.name),
            String(format: "%.5f", candidate.coordinate.latitude),
            String(format: "%.5f", candidate.coordinate.longitude)
        ].joined(separator: ":")
        return "mapkit:\(fnv1a64(raw))"
    }

    private static func normalizedIdentityKey(for candidate: MapKitNearbyCandidate) -> String {
        [
            normalizedName(candidate.name),
            normalizedName(candidate.formattedAddress ?? ""),
            String(format: "%.4f", candidate.coordinate.latitude),
            String(format: "%.4f", candidate.coordinate.longitude)
        ].joined(separator: "|")
    }

    private static func normalizedName(_ raw: String) -> String {
        raw
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func normalizedType(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
    }

    private static func fnv1a64(_ raw: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in raw.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}
