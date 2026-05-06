import Foundation

protocol PricingAPIProtocol {
    func fetchPricing() async throws -> [SKU: SkuPricing]
}

final class PricingAPI: PricingAPIProtocol {
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

    func fetchPricing() async throws -> [SKU: SkuPricing] {
        guard let baseURL = baseURLProvider() else {
            throw APIService.APIError.missingBaseURL
        }
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

#if DEBUG
final class MockPricingAPI: PricingAPIProtocol {
    func fetchPricing() async throws -> [SKU: SkuPricing] { defaultPricing }
}
#endif

