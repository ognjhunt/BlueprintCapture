import Foundation

enum PlaidFlow: String, Codable {
    case instantAuth
    case instantMicroDeposits
    case automatedMicroDeposits
}

struct PlaidLinkTokenResponse: Codable {
    let linkToken: String
}

final class PlaidLinkService {
    static let shared = PlaidLinkService()
    private init() {}

    func fetchLinkToken(preferredFlow: PlaidFlow? = nil) async throws -> String {
        // In production, call your backend which calls Plaid /link/token/create
        if let _ = AppConfig.plaidLinkTokenURL() {
            return "link-sandbox-123"
        }
        throw URLError(.badURL)
    }

    func exchangePublicToken(_ publicToken: String) async throws -> String {
        // Normally done on the server; here we simulate
        try await Task.sleep(nanoseconds: 500_000_000)
        return "access-\(UUID().uuidString)"
    }
}


