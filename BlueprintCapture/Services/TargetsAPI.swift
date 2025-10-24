import Foundation

protocol TargetsAPIProtocol {
    func fetchTargets(lat: Double, lng: Double, radiusMeters: Int, limit: Int) async throws -> [Target]
}

final class TargetsAPI: TargetsAPIProtocol {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = URL(string: "https://api.example.com")!, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func fetchTargets(lat: Double, lng: Double, radiusMeters: Int, limit: Int) async throws -> [Target] {
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
    private let session: URLSession
    private let apiKeyProvider: () -> String?

    init(session: URLSession = .shared, apiKeyProvider: @escaping () -> String? = { AppConfig.placesAPIKey() }) {
        self.session = session
        self.apiKeyProvider = apiKeyProvider
    }

    enum ServiceError: Error { case missingAPIKey, badResponse }

        func nearby(lat: Double, lng: Double, radiusMeters: Int, limit: Int, types: [String]) async throws -> [PlaceDetailsLite] {
        guard let apiKey = apiKeyProvider() else { throw ServiceError.missingAPIKey }
            let url = URL(string: "https://places.googleapis.com/v1/places:searchNearby")!
            var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            // New Places API (v1) requires a field mask header for POST methods
            request.addValue("places.id,places.displayName,places.formattedAddress,places.location,places.types", forHTTPHeaderField: "X-Goog-FieldMask")
            // Provide the API key in header (supported and recommended)
            request.addValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        // Use includedTypes filter; prefer grocery/electronics if provided
        struct Circle: Encodable { let center: Center; let radius: Int }
        struct Center: Encodable { let latitude: Double; let longitude: Double }
        struct LocationRestriction: Encodable { let circle: Circle }
        struct Body: Encodable { let includedTypes: [String]?; let maxResultCount: Int; let locationRestriction: LocationRestriction; let rankPreference: String }
        let body = Body(
            includedTypes: types.isEmpty ? nil : types,
            maxResultCount: limit,
            locationRestriction: LocationRestriction(circle: Circle(center: Center(latitude: lat, longitude: lng), radius: radiusMeters)),
            rankPreference: "DISTANCE"
        )
        request.httpBody = try JSONEncoder().encode(body)

            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                let body = String(data: data, encoding: .utf8) ?? "<non-utf8>"
                print("❌ [Places Nearby] HTTP \(http.statusCode) — \(body.prefix(400))")
                throw ServiceError.badResponse
            }
        // Minimal parse of Places search results
        struct DisplayName: Decodable { let text: String? }
        struct LocationLatLng: Decodable { let latitude: Double?; let longitude: Double? }
        struct Place: Decodable { let id: String?; let displayName: DisplayName?; let formattedAddress: String?; let location: LocationLatLng?; let types: [String]?; let placeId: String? }
        struct Response: Decodable { let places: [Place]? }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let places = decoded.places ?? []
        print("✅ [Places Nearby] Decoded \(places.count) places")
        return places.compactMap { p in
            // id or placeId may be present depending on endpoint
            guard let id = p.id ?? p.placeId,
                  let name = p.displayName?.text,
                  let lat = p.location?.latitude,
                  let lng = p.location?.longitude else { return nil }
            return PlaceDetailsLite(placeId: id, displayName: name, formattedAddress: p.formattedAddress, lat: lat, lng: lng, types: p.types)
        }
    }
}

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


