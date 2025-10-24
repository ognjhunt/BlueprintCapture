import Foundation
import CoreLocation

struct AutocompleteSuggestion: Identifiable, Equatable {
    let id = UUID()
    let placeId: String
    let primaryText: String
    let secondaryText: String
    let types: [String]
}

protocol PlacesAutocompleteServiceProtocol {
    func autocomplete(
        input: String,
        sessionToken: String,
        origin: CLLocationCoordinate2D?,
        radiusMeters: Int?
    ) async throws -> [AutocompleteSuggestion]
}

final class PlacesAutocompleteService: PlacesAutocompleteServiceProtocol {
    private let session: URLSession
    private let apiKeyProvider: () -> String?

    init(session: URLSession = .shared, apiKeyProvider: @escaping () -> String? = { AppConfig.placesAPIKey() }) {
        self.session = session
        self.apiKeyProvider = apiKeyProvider
    }

    enum ServiceError: Error { 
        case missingAPIKey
        case badResponse
        case noResults
    }

    // Google Places v1 Autocomplete (NEW API)
    // https://developers.google.com/maps/documentation/places/web-service/place-autocomplete
    func autocomplete(
        input: String,
        sessionToken: String,
        origin: CLLocationCoordinate2D?,
        radiusMeters: Int?
    ) async throws -> [AutocompleteSuggestion] {
        guard let apiKey = apiKeyProvider() else { throw ServiceError.missingAPIKey }
        let url = URL(string: "https://places.googleapis.com/v1/places:autocomplete")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        // Request fields we need - including types to differentiate establishments vs addresses
        request.addValue("suggestions.placePrediction.placeId,suggestions.placePrediction.text,suggestions.placePrediction.types,suggestions.placePrediction.structuredFormat", forHTTPHeaderField: "X-Goog-FieldMask")

        struct Circle: Encodable {
            let center: Center
            let radius: Double
            struct Center: Encodable {
                let latitude: Double
                let longitude: Double
            }
        }
        
        struct LocationBias: Encodable {
            let circle: Circle?
        }
        
        struct LatLng: Encodable {
            let latitude: Double
            let longitude: Double
        }
        
        struct Body: Encodable {
            let input: String
            let sessionToken: String
            let origin: LatLng?
            let locationBias: LocationBias?
            let locationRestriction: LocationBias?
            let includedPrimaryTypes: [String]?
            let includedRegionCodes: [String]?
            let languageCode: String?
            let includeQueryPredictions: Bool
            
            enum CodingKeys: String, CodingKey {
                case input, sessionToken, origin, locationBias, locationRestriction
                case includedPrimaryTypes, includedRegionCodes, languageCode, includeQueryPredictions
            }
        }

        // Build location bias - prioritize results within user's search radius
        let bias: LocationBias? = {
            guard let o = origin else { return nil }
            // Use a tighter bias radius for truly nearby results (don't go beyond 10 miles)
            let biasRadius = min(Double(radiusMeters ?? 5000), 16000.0) // Max 10 miles for bias
            return LocationBias(circle: Circle(
                center: Circle.Center(latitude: o.latitude, longitude: o.longitude),
                radius: biasRadius
            ))
        }()
        
        // Restrict to reasonable region around user (prevent results from other states/countries)
        let restriction: LocationBias? = {
            guard let o = origin else { return nil }
            // Restrict to 50 miles max to keep results relevant
            return LocationBias(circle: Circle(
                center: Circle.Center(latitude: o.latitude, longitude: o.longitude),
                radius: 80000.0 // ~50 miles
            ))
        }()
        
        // Include BOTH establishment types (stores/businesses) AND address types
        // See: https://developers.google.com/maps/documentation/places/web-service/place-types
        let includedTypes: [String] = [
            // Retail & commercial establishments
            "store",
            "supermarket",
            "shopping_mall",
            "convenience_store",
            "grocery_store",
            "department_store",
            "electronics_store",
            "clothing_store",
            "pharmacy",
            "gas_station",
            "restaurant",
            "cafe",
            "bar",
            "lodging",
            "establishment",
            // Address types for street addresses
            "street_address",
            "premise",
            "subpremise",
            "route",
            "geocode"
        ]

        let body = Body(
            input: input,
            sessionToken: sessionToken,
            origin: origin.map { LatLng(latitude: $0.latitude, longitude: $0.longitude) },
            locationBias: bias,
            locationRestriction: restriction,
            includedPrimaryTypes: nil, // Don't restrict primary types - we want both businesses and addresses
            includedRegionCodes: ["us"], // Assuming US-based - adjust if needed
            languageCode: "en",
            includeQueryPredictions: true
        )
        
        request.httpBody = try JSONEncoder().encode(body)

        print("🔍 [Places Autocomplete] Searching for '\(input)' near \(origin.map { "(\($0.latitude), \($0.longitude))" } ?? "unknown")")
        
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let bodyStr = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            print("❌ [Places Autocomplete] HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            print("   Response body: \(bodyStr.prefix(500))")
            throw ServiceError.badResponse
        }

        struct MainText: Decodable { let text: String? }
        struct SecondaryText: Decodable { let text: String? }
        struct StructuredFormat: Decodable { 
            let mainText: MainText?
            let secondaryText: SecondaryText?
        }
        struct TextFormat: Decodable { let text: String? }
        struct PlacePrediction: Decodable { 
            let placeId: String?
            let text: TextFormat?
            let structuredFormat: StructuredFormat?
            let types: [String]?
        }
        struct Suggestion: Decodable { let placePrediction: PlacePrediction? }
        struct Response: Decodable { let suggestions: [Suggestion]? }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let suggestions = decoded.suggestions ?? []
        
        let results = suggestions.compactMap { s -> AutocompleteSuggestion? in
            guard let p = s.placePrediction, let id = p.placeId else { return nil }
            
            // Extract primary and secondary text from structured format (preferred)
            var primary = p.structuredFormat?.mainText?.text ?? ""
            var secondary = p.structuredFormat?.secondaryText?.text ?? ""
            
            // Fallback to text if structured format is empty
            if primary.isEmpty {
                primary = p.text?.text ?? ""
                // If we only have combined text, try to split it
                if !primary.isEmpty && secondary.isEmpty {
                    let parts = primary.components(separatedBy: ", ")
                    if parts.count > 1 {
                        primary = parts[0]
                        secondary = parts.dropFirst().joined(separator: ", ")
                    }
                }
            }
            
            let types = p.types ?? []
            
            return AutocompleteSuggestion(
                placeId: id,
                primaryText: primary,
                secondaryText: secondary,
                types: types
            )
        }
        
        print("✅ [Places Autocomplete] Found \(results.count) suggestions")
        for (idx, result) in results.prefix(5).enumerated() {
            print("   \(idx+1). \(result.primaryText) - \(result.secondaryText) [types: \(result.types.prefix(3).joined(separator: ", "))]")
        }
        
        return results
    }
}
