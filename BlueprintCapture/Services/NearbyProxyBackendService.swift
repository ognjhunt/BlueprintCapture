import Foundation
import CoreLocation

struct NearbyProxyPlace: Codable, Equatable {
    let placeId: String
    let displayName: String
    let formattedAddress: String?
    let lat: Double
    let lng: Double
    let placeTypes: [String]

    enum CodingKeys: String, CodingKey {
        case placeId = "place_id"
        case displayName = "display_name"
        case formattedAddress = "formatted_address"
        case lat
        case lng
        case placeTypes = "place_types"
    }

    var placeDetailsLite: PlaceDetailsLite {
        PlaceDetailsLite(
            placeId: placeId,
            displayName: displayName,
            formattedAddress: formattedAddress,
            lat: lat,
            lng: lng,
            types: placeTypes
        )
    }
}

struct NearbyProxyAutocompleteSuggestion: Codable, Equatable {
    let placeId: String
    let primaryText: String
    let secondaryText: String
    let placeTypes: [String]

    enum CodingKeys: String, CodingKey {
        case placeId = "place_id"
        case primaryText = "primary_text"
        case secondaryText = "secondary_text"
        case placeTypes = "place_types"
    }

    var autocompleteSuggestion: AutocompleteSuggestion {
        AutocompleteSuggestion(
            placeId: placeId,
            primaryText: primaryText,
            secondaryText: secondaryText,
            types: placeTypes
        )
    }
}

struct NearbyProxyDiscoveryResponse: Codable, Equatable {
    let providerUsed: String
    let fallbackUsed: Bool
    let places: [NearbyProxyPlace]

    enum CodingKeys: String, CodingKey {
        case providerUsed = "provider_used"
        case fallbackUsed = "fallback_used"
        case places
    }
}

struct NearbyProxyAutocompleteResponse: Codable, Equatable {
    let providerUsed: String
    let fallbackUsed: Bool
    let suggestions: [NearbyProxyAutocompleteSuggestion]

    enum CodingKeys: String, CodingKey {
        case providerUsed = "provider_used"
        case fallbackUsed = "fallback_used"
        case suggestions
    }
}

struct NearbyProxyDetailsResponse: Codable, Equatable {
    let providerUsed: String
    let fallbackUsed: Bool
    let places: [NearbyProxyPlace]

    enum CodingKeys: String, CodingKey {
        case providerUsed = "provider_used"
        case fallbackUsed = "fallback_used"
        case places
    }
}

final class NearbyProxyBackendService {
    static let shared = NearbyProxyBackendService()

    enum ProxyError: LocalizedError, Equatable {
        case missingDemandBackendBaseURL
        case invalidResponse(statusCode: Int)

        var errorDescription: String? {
            switch self {
            case .missingDemandBackendBaseURL:
                return "BLUEPRINT_DEMAND_BACKEND_BASE_URL is not configured for this build."
            case .invalidResponse(let statusCode):
                return "Nearby proxy returned HTTP \(statusCode)."
            }
        }
    }

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    func discover(
        userLocation: CLLocationCoordinate2D,
        radiusMeters: Int,
        limit: Int,
        includedTypes: [String],
        providerHint: NearbyDiscoveryProvider,
        allowFallback: Bool
    ) async throws -> NearbyProxyDiscoveryResponse {
        let body = NearbyProxyDiscoveryRequestBody(
            lat: userLocation.latitude,
            lng: userLocation.longitude,
            radiusMeters: radiusMeters,
            limit: limit,
            includedTypes: includedTypes,
            providerHint: providerHint.rawValue,
            allowFallback: allowFallback
        )
        return try await perform(path: "v1/nearby/discovery", body: body, responseType: NearbyProxyDiscoveryResponse.self)
    }

    func autocomplete(
        query: String,
        sessionToken: String,
        origin: CLLocationCoordinate2D?,
        radiusMeters: Int?
    ) async throws -> NearbyProxyAutocompleteResponse {
        let body = NearbyProxyAutocompleteRequestBody(
            query: query,
            sessionToken: sessionToken,
            origin: origin.map { NearbyProxyCoordinate(lat: $0.latitude, lng: $0.longitude) },
            radiusMeters: radiusMeters,
            providerHint: NearbyDiscoveryProvider.placesNearby.rawValue,
            allowFallback: false
        )
        return try await perform(path: "v1/places/autocomplete", body: body, responseType: NearbyProxyAutocompleteResponse.self)
    }

    func fetchDetails(placeIds: [String]) async throws -> NearbyProxyDetailsResponse {
        let body = NearbyProxyDetailsRequestBody(
            placeIds: placeIds,
            providerHint: NearbyDiscoveryProvider.placesNearby.rawValue,
            allowFallback: false
        )
        return try await perform(path: "v1/places/details", body: body, responseType: NearbyProxyDetailsResponse.self)
    }

    private func perform<RequestBody: Encodable, ResponseBody: Decodable>(
        path: String,
        body: RequestBody,
        responseType: ResponseBody.Type
    ) async throws -> ResponseBody {
        guard let baseURL = AppConfig.demandBackendBaseURL() else {
            throw ProxyError.missingDemandBackendBaseURL
        }

        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProxyError.invalidResponse(statusCode: -1)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ProxyError.invalidResponse(statusCode: http.statusCode)
        }
        return try decoder.decode(responseType, from: data)
    }
}

private struct NearbyProxyCoordinate: Codable, Equatable {
    let lat: Double
    let lng: Double
}

private struct NearbyProxyDiscoveryRequestBody: Codable, Equatable {
    let lat: Double
    let lng: Double
    let radiusMeters: Int
    let limit: Int
    let includedTypes: [String]
    let providerHint: String
    let allowFallback: Bool

    enum CodingKeys: String, CodingKey {
        case lat
        case lng
        case radiusMeters = "radius_m"
        case limit
        case includedTypes = "included_types"
        case providerHint = "provider_hint"
        case allowFallback = "allow_fallback"
    }
}

private struct NearbyProxyAutocompleteRequestBody: Codable, Equatable {
    let query: String
    let sessionToken: String
    let origin: NearbyProxyCoordinate?
    let radiusMeters: Int?
    let providerHint: String
    let allowFallback: Bool

    enum CodingKeys: String, CodingKey {
        case query
        case sessionToken = "session_token"
        case origin
        case radiusMeters = "radius_m"
        case providerHint = "provider_hint"
        case allowFallback = "allow_fallback"
    }
}

private struct NearbyProxyDetailsRequestBody: Codable, Equatable {
    let placeIds: [String]
    let providerHint: String
    let allowFallback: Bool

    enum CodingKeys: String, CodingKey {
        case placeIds = "place_ids"
        case providerHint = "provider_hint"
        case allowFallback = "allow_fallback"
    }
}
