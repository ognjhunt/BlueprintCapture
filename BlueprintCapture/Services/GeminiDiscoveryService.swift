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

        // Use Gemini 2.5 with Grounding with Google Maps enabled
        // Reference: https://ai.google.dev/gemini-api/docs/maps-grounding?utm_source=chatgpt.com
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let joinedCats = categories.joined(separator: " OR ")
        let miles = max(0, Int(round(Double(radiusMeters) / 1609.34)))
        // Structured prompt tailored for Maps grounding
        var prompt = "Return the top \(limit) targets within \(miles) mi matching \(joinedCats) that would be SKU \(sku.rawValue). Respond ONLY as strict JSON array of objects with keys: placeId, types, name."
        if let geohashHint = geohashHint { prompt += " Geohash hint: \(geohashHint)." }

        struct Part: Encodable { let text: String }
        struct Content: Encodable { let parts: [Part] }
        struct LatLng: Encodable { let latitude: Double; let longitude: Double }
        struct RetrievalConfig: Encodable { let latLng: LatLng }
        struct GoogleMapsTool: Encodable {}
        struct Tool: Encodable { let googleMaps: GoogleMapsTool }
        struct ToolConfig: Encodable { let retrievalConfig: RetrievalConfig }
        struct Body: Encodable {
            let contents: [Content]
            let tools: [Tool]
            let toolConfig: ToolConfig
        }

        let body = Body(
            contents: [Content(parts: [Part(text: prompt)])],
            tools: [Tool(googleMaps: GoogleMapsTool())],
            toolConfig: ToolConfig(retrievalConfig: RetrievalConfig(latLng: LatLng(latitude: userLocation.latitude, longitude: userLocation.longitude)))
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ServiceError.badResponse
        }
        // Response: either grounded text with JSON in the first candidate, or structured grounding metadata.
        struct GLMPart: Decodable { let text: String? }
        struct GLMContent: Decodable { let parts: [GLMPart]? }
        struct GLMGroundingChunkMaps: Decodable { let title: String?; let uri: String? }
        struct GLMGroundingChunk: Decodable { let maps: GLMGroundingChunkMaps? }
        struct GLMGroundingMetadata: Decodable { let groundingChunks: [GLMGroundingChunk]? }
        struct GLMCandidate: Decodable { let content: GLMContent?; let groundingMetadata: GLMGroundingMetadata? }
        struct GLMResponse: Decodable { let candidates: [GLMCandidate]? }
        let glm = try JSONDecoder().decode(GLMResponse.self, from: data)

        // Prefer JSON in model text; otherwise fail
        if let text = glm.candidates?.first?.content?.parts?.first?.text, !text.isEmpty {
            if let arrData = GeminiDiscoveryService.extractFirstJSONArray(from: text)?.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([GeminiPlaceCandidate].self, from: arrData) {
                print("✅ [Gemini] Raw JSON: \(String(data: arrData, encoding: .utf8) ?? "<utf8-error>")")
                return Array(decoded.prefix(limit))
            } else {
                print("⚠️ [Gemini] Non-JSON response: \(text.prefix(400))")
            }
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


