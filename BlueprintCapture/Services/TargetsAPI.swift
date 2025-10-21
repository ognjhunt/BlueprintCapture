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

final class MockTargetsAPI: TargetsAPIProtocol {
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
            let address: String? = Bool.random() ? nil : "123 Market St"
            let t = Target(
                id: "tgt_\(i)",
                displayName: "Target #\(i)",
                sku: sku,
                lat: coordinateLat,
                lng: coordinateLng,
                address: address,
                demandScore: demand,
                sizeSqFt: [1000, 2000, 5000, 12000, 38000].randomElement(),
                category: ["Grocery", "Office", "Retail", "Flagship Retail", "Warehouse"].randomElement(),
                computedDistanceMeters: nil
            )
            results.append(t)
        }
        return results
    }
}


