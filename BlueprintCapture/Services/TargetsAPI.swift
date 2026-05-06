import Foundation
import CoreLocation

protocol TargetsAPIProtocol {
    func fetchTargets(lat: Double, lng: Double, radiusMeters: Int, limit: Int) async throws -> [Target]
}

final class TargetsAPI: TargetsAPIProtocol {
    private let baseURLProvider: () -> URL?
    private let session: URLSession

    init(
        baseURLProvider: @escaping () -> URL? = { AppConfig.backendBaseURL() },
        session: URLSession = .shared
    ) {
        self.baseURLProvider = baseURLProvider
        self.session = session
    }

    convenience init(baseURL: URL?, session: URLSession = .shared) {
        self.init(baseURLProvider: { baseURL }, session: session)
    }

    func fetchTargets(lat: Double, lng: Double, radiusMeters: Int, limit: Int) async throws -> [Target] {
        guard let baseURL = baseURLProvider() else {
            throw APIService.APIError.missingBaseURL
        }
        var components = URLComponents(url: baseURL.appendingPathComponent("/v1/targets"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "lat", value: String(lat)),
            URLQueryItem(name: "lng", value: String(lng)),
            URLQueryItem(name: "radius_m", value: String(radiusMeters)),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        let url = components.url!
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        struct Response: Decodable { let targets: [Target] }
        return try JSONDecoder().decode(Response.self, from: data).targets
    }
}

// Google Places Nearby Search fallback for when Gemini discovery is not available
protocol PlacesNearbyProtocol {
    func nearby(lat: Double, lng: Double, radiusMeters: Int, limit: Int, types: [String]) async throws -> [PlaceDetailsLite]
}

final class GooglePlacesNearby: PlacesNearbyProtocol {
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

        func nearby(lat: Double, lng: Double, radiusMeters: Int, limit: Int, types: [String]) async throws -> [PlaceDetailsLite] {
        guard RuntimeConfig.current.availability(for: .nearbyDiscovery).isEnabled else {
            throw ServiceError.featureDisabled
        }
        let response = try await backend.discover(
            userLocation: CLLocationCoordinate2D(latitude: lat, longitude: lng),
            radiusMeters: radiusMeters,
            limit: limit,
            includedTypes: types,
            providerHint: .placesNearby,
            allowFallback: false
        )
        print("✅ [Places Nearby] Decoded \(response.places.count) places via nearby proxy")
        return response.places.map(\.placeDetailsLite)
    }
}

#if DEBUG
final class MockTargetsAPI: TargetsAPIProtocol {
    private let sampleAddresses = [
        "1123 Market St, Suite 100",
        "456 Main Street",
        "789 Oak Avenue, Building A",
        "234 Pine Road",
        "567 Elm Street, Floor 2",
        "890 Cedar Lane",
        "321 Maple Drive",
        "654 Birch Court",
        "987 Spruce Way",
        "135 Walnut Place",
        "246 Ash Boulevard",
        "369 Chestnut Square",
        "147 Willow Circle",
        "258 Poplar Street",
        "741 Sycamore Avenue",
        "852 Juniper Road",
        "963 Hawthorn Lane",
        "159 Laurel Drive",
        "357 Dogwood Path",
        "753 Magnolia Street"
    ]
    
    private let sampleNames = [
        "Metro Market",
        "Center Plaza",
        "Grand Retail",
        "Valley Store",
        "Premium Shopping",
        "Main Street Market",
        "Downtown Hub",
        "Community Center",
        "Town Square",
        "Shopping Central"
    ]
    
    func fetchTargets(lat: Double, lng: Double, radiusMeters: Int, limit: Int) async throws -> [Target] {
        // Generate 12-40 synthetic targets around the user's location
        let count = max(12, min(40, limit))
        var results: [Target] = []
        for i in 0..<count {
            let dx = Double.random(in: -0.01...0.01)
            let dy = Double.random(in: -0.01...0.01)
            let coordinateLat = lat + dx
            let coordinateLng = lng + dy
            let sku: SKU = [SKU.A, .B, .C].randomElement()!
            let demand = Double.random(in: 0.2...0.95)
            // Always provide realistic addresses (no more nil!)
            let address = sampleAddresses.randomElement()!
            let t = Target(
                id: "tgt_\(i)",
                displayName: sampleNames.randomElement()!,
                sku: sku,
                lat: coordinateLat,
                lng: coordinateLng,
                address: address,
                demandScore: demand,
                sizeSqFt: [5000, 8000, 10000, 12000, 15000, 20000, 25000, 38000].randomElement(),
                category: ["Grocery", "Office", "Retail", "Flagship Retail", "Warehouse"].randomElement(),
                computedDistanceMeters: nil
            )
            results.append(t)
        }
        return results
    }
}
#endif
