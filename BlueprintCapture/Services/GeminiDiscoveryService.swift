import Foundation
import CoreLocation

struct GeminiPlaceCandidate: Codable, Equatable {
    let placeId: String
    let name: String
    let types: [String]
    let score: Double?
}

protocol GeminiDiscoveryServiceProtocol {
    func discoverCandidates(
        userLocation: CLLocationCoordinate2D,
        radiusMeters: Int,
        limit: Int,
        categories: [String],
        sku: SKU,
        geohashHint: String?
    ) async throws -> [GeminiPlaceCandidate]
}

final class GeminiDiscoveryService: GeminiDiscoveryServiceProtocol {
    private let session: URLSession
    private let apiKeyProvider: () -> String?

    init(session: URLSession = .shared, apiKeyProvider: @escaping () -> String? = { AppConfig.geminiAPIKey() }) {
        self.session = session
        self.apiKeyProvider = apiKeyProvider
    }

    enum ServiceError: Error { case missingAPIKey, badResponse, parseFailed }

    func discoverCandidates(
        userLocation: CLLocationCoordinate2D,
        radiusMeters: Int,
        limit: Int,
        categories: [String],
        sku: SKU,
        geohashHint: String?
    ) async throws -> [GeminiPlaceCandidate] {
        guard let apiKey = apiKeyProvider() else { throw ServiceError.missingAPIKey }

        // Google AI for Developers - Gemini generateContent
        // We request a strict JSON array of { placeId, types, name } objects.
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let joinedCats = categories.joined(separator: " OR ")
        let miles = max(0, Int(round(Double(radiusMeters) / 1609.34)))
        var prompt = "You are grounded to Google Maps. Return ONLY strict JSON array with objects {placeId, types, name}. No prose. Lat=\(userLocation.latitude), Lng=\(userLocation.longitude), within \(miles) mi, categories: \(joinedCats), SKU \(sku.rawValue)."
        if let geohashHint = geohashHint { prompt += " Geohash hint: \(geohashHint)." }

        struct Part: Encodable { let text: String }
        struct Content: Encodable { let parts: [Part] }
        struct Body: Encodable { let contents: [Content] }
        let body = Body(contents: [Content(parts: [Part(text: prompt)])])
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ServiceError.badResponse
        }
        // Response: { candidates: [ { content: { parts: [ { text: "...json..." } ] } } ] }
        struct GLMPart: Decodable { let text: String? }
        struct GLMContent: Decodable { let parts: [GLMPart]? }
        struct GLMCandidate: Decodable { let content: GLMContent? }
        struct GLMResponse: Decodable { let candidates: [GLMCandidate]? }
        let glm = try JSONDecoder().decode(GLMResponse.self, from: data)
        guard let text = glm.candidates?.first?.content?.parts?.first?.text, !text.isEmpty else {
            throw ServiceError.parseFailed
        }
        // Extract first JSON array from text robustly
        if let arrData = GeminiDiscoveryService.extractFirstJSONArray(from: text)?.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([GeminiPlaceCandidate].self, from: arrData) {
            return Array(decoded.prefix(limit))
        }
        throw ServiceError.parseFailed
    }
}

final class MockGeminiDiscoveryService: GeminiDiscoveryServiceProtocol {
    func discoverCandidates(
        userLocation: CLLocationCoordinate2D,
        radiusMeters: Int,
        limit: Int,
        categories: [String],
        sku: SKU,
        geohashHint: String?
    ) async throws -> [GeminiPlaceCandidate] {
        return (0..<limit).map { i in
            GeminiPlaceCandidate(
                placeId: "ChIJ_mock_\(i)",
                name: ["Center Plaza", "Community Center", "Premium Shopping", "Metro Market", "Town Square"].randomElement()!,
                types: ["shopping_mall", "grocery_or_supermarket", "electronics_store"],
                score: Double.random(in: 0.5...0.99)
            )
        }
    }
}

private extension GeminiDiscoveryService {
    static func extractFirstJSONArray(from text: String) -> String? {
        // Find the first '[' and its matching ']'
        guard let start = text.firstIndex(of: "[") else { return nil }
        var depth = 0
        for i in text[start...].indices {
            let ch = text[i]
            if ch == "[" { depth += 1 }
            if ch == "]" {
                depth -= 1
                if depth == 0 { return String(text[start...i]) }
            }
        }
        return nil
    }
}


