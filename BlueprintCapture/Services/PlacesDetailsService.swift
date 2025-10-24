import Foundation
import CoreLocation

struct PlaceDetailsLite: Codable, Equatable {
    let placeId: String
    let displayName: String
    let formattedAddress: String?
    let lat: Double
    let lng: Double
    let types: [String]?
}

protocol PlacesDetailsServiceProtocol {
    func fetchDetails(placeIds: [String]) async throws -> [PlaceDetailsLite]
}

final class PlacesDetailsService: PlacesDetailsServiceProtocol {
    private let session: URLSession
    private let apiKeyProvider: () -> String?

    init(session: URLSession = .shared, apiKeyProvider: @escaping () -> String? = { AppConfig.placesAPIKey() }) {
        self.session = session
        self.apiKeyProvider = apiKeyProvider
    }

    enum ServiceError: Error { case missingAPIKey, badResponse }

    /// Batch Place Details (New) with minimal field mask
    func fetchDetails(placeIds: [String]) async throws -> [PlaceDetailsLite] {
        guard !placeIds.isEmpty else { return [] }
        guard let apiKey = apiKeyProvider() else { throw ServiceError.missingAPIKey }

        // Places API (New) Place Details: GET per place, but we can parallelize on client.
        // FieldMask: id,displayName,formattedAddress,location,types
        let fieldMask = "id,displayName,formattedAddress,location,types"
        // Use header-based API key + field mask per new Places API practices
        let urls: [URL] = placeIds.compactMap { id in
            URL(string: "https://places.googleapis.com/v1/places/\(id)")
        }

        return try await withThrowingTaskGroup(of: PlaceDetailsLite?.self) { group in
            for url in urls { group.addTask { try? await Self.fetchOne(url: url, session: self.session, apiKey: apiKey, fieldMask: fieldMask) } }
            var out: [PlaceDetailsLite] = []
            for try await item in group { if let item = item { out.append(item) } }
            return out
        }
    }

    private static func fetchOne(url: URL, session: URLSession, apiKey: String, fieldMask: String) async throws -> PlaceDetailsLite? {
        var req = URLRequest(url: url)
        req.addValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        req.addValue(fieldMask, forHTTPHeaderField: "X-Goog-FieldMask")
        if let bundleId = Bundle.main.bundleIdentifier, !bundleId.isEmpty {
            req.addValue(bundleId, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        }
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            print("❌ [Places Details] HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1) — \(body.prefix(400))")
            return nil
        }
        // Minimal decode of the Place object
        struct DisplayName: Decodable { let text: String? }
        struct LocationLatLng: Decodable { let latitude: Double?; let longitude: Double? }
        struct Place: Decodable { let id: String?; let displayName: DisplayName?; let formattedAddress: String?; let location: LocationLatLng?; let types: [String]? }
        if let p = try? JSONDecoder().decode(Place.self, from: data),
           let id = p.id, let lat = p.location?.latitude, let lng = p.location?.longitude, let name = p.displayName?.text {
            return PlaceDetailsLite(placeId: id, displayName: name, formattedAddress: p.formattedAddress, lat: lat, lng: lng, types: p.types)
        }
        return nil
    }
}

final class MockPlacesDetailsService: PlacesDetailsServiceProtocol {
    func fetchDetails(placeIds: [String]) async throws -> [PlaceDetailsLite] {
        return placeIds.map { id in
            PlaceDetailsLite(
                placeId: id,
                displayName: ["Center Plaza", "Community Center", "Premium Shopping", "Metro Market", "Town Square"].randomElement()!,
                formattedAddress: [
                    "258 Poplar Street",
                    "321 Maple Drive",
                    "987 Spruce Way",
                    "1123 Market St, Suite 100"
                ].randomElement(),
                lat: 37.3317 + Double.random(in: -0.01...0.01),
                lng: -122.0301 + Double.random(in: -0.01...0.01),
                types: ["shopping_mall", "grocery_or_supermarket", "electronics_store"]
            )
        }
    }
}


