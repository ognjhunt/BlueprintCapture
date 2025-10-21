import Foundation

protocol PricingAPIProtocol {
    func fetchPricing() async throws -> [SKU: SkuPricing]
}

final class PricingAPI: PricingAPIProtocol {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = URL(string: "https://api.example.com")!, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func fetchPricing() async throws -> [SKU: SkuPricing] {
        let url = baseURL.appendingPathComponent("/v1/pricing/skus")
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode([String: SkuPricing].self, from: data)
        var map: [SKU: SkuPricing] = [:]
        for (k, v) in decoded {
            if let sku = SKU(rawValue: k) { map[sku] = v }
        }
        return map
    }
}

final class MockPricingAPI: PricingAPIProtocol {
    func fetchPricing() async throws -> [SKU: SkuPricing] { defaultPricing }
}


