import Foundation
import CoreGraphics

protocol StreetViewServiceProtocol {
    func hasStreetView(lat: Double, lng: Double) async throws -> Bool
    func imageURL(lat: Double, lng: Double, size: CGSize) -> URL?
}

final class StreetViewService: StreetViewServiceProtocol {
    private let apiKeyProvider: () -> String?
    private var availabilityCache: [String: Bool] = [:]
    private let session: URLSession

    init(session: URLSession = .shared, apiKeyProvider: @escaping () -> String?) {
        self.session = session
        self.apiKeyProvider = apiKeyProvider
    }

    func hasStreetView(lat: Double, lng: Double) async throws -> Bool {
        let key = cacheKey(lat: lat, lng: lng)
        if let cached = availabilityCache[key] { return cached }
        guard let apiKey = apiKeyProvider() else { return false }
        var components = URLComponents(string: "https://maps.googleapis.com/maps/api/streetview/metadata")!
        components.queryItems = [
            URLQueryItem(name: "location", value: "\(lat),\(lng)"),
            URLQueryItem(name: "key", value: apiKey)
        ]
        let url = components.url!
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        struct Metadata: Decodable { let status: String }
        let status = try JSONDecoder().decode(Metadata.self, from: data).status
        let ok = status == "OK"
        availabilityCache[key] = ok
        return ok
    }

    func imageURL(lat: Double, lng: Double, size: CGSize) -> URL? {
        guard let apiKey = apiKeyProvider() else { return nil }
        var components = URLComponents(string: "https://maps.googleapis.com/maps/api/streetview")!
        components.queryItems = [
            URLQueryItem(name: "size", value: "\(Int(size.width))x\(Int(size.height))"),
            URLQueryItem(name: "location", value: "\(lat),\(lng)"),
            URLQueryItem(name: "key", value: apiKey)
        ]
        return components.url
    }

    private func cacheKey(lat: Double, lng: Double) -> String { "\(lat.rounded(to: 5)),\(lng.rounded(to: 5))" }
}

private extension Double {
    func rounded(to places: Int) -> Double {
        let pow10 = pow(10.0, Double(places))
        return (self * pow10).rounded() / pow10
    }
}


