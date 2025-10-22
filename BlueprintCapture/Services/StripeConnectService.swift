import Foundation

struct StripeAccountLinks: Codable {
    let onboardingURL: URL

    enum CodingKeys: String, CodingKey {
        case onboardingURL = "onboarding_url"
    }
}

enum PayoutSchedule: String, CaseIterable, Codable {
    case daily, weekly, monthly, manual
}

struct StripeAccountState: Codable {
    struct NextPayout: Codable {
        let estimatedArrival: Date
        let amountCents: Int

        enum CodingKeys: String, CodingKey {
            case estimatedArrival = "estimated_arrival"
            case amountCents = "amount_cents"
        }

        var amount: Decimal { Decimal(amountCents) / Decimal(100) }
    }

    let onboardingComplete: Bool
    let payoutsEnabled: Bool
    let payoutSchedule: PayoutSchedule
    let instantPayoutEligible: Bool
    let nextPayout: NextPayout?
    let requirementsDue: [String]?

    enum CodingKeys: String, CodingKey {
        case onboardingComplete = "onboarding_complete"
        case payoutsEnabled = "payouts_enabled"
        case payoutSchedule = "payout_schedule"
        case instantPayoutEligible = "instant_payout_eligible"
        case nextPayout = "next_payout"
        case requirementsDue = "requirements_due"
    }

    var isReadyForTransfers: Bool { onboardingComplete && payoutsEnabled }
}

final class StripeConnectService {
    enum StripeConnectError: Error {
        case missingConfiguration
        case invalidResponse(status: Int)
    }

    static let shared = StripeConnectService()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
    }

    func createOnboardingLink() async throws -> URL {
        if let base = AppConfig.backendBaseURL() {
            let request = try makeRequest(base: base, path: "v1/stripe/account/onboarding_link")
            let data = try await perform(request: request)
            let links = try decoder.decode(StripeAccountLinks.self, from: data)
            return links.onboardingURL
        }

        if let url = AppConfig.stripeOnboardingURL() {
            return url
        }

        throw StripeConnectError.missingConfiguration
    }

    func fetchAccountState() async throws -> StripeAccountState {
        let request = try makeRequest(path: "v1/stripe/account")
        let data = try await perform(request: request)
        return try decoder.decode(StripeAccountState.self, from: data)
    }

    func updatePayoutSchedule(_ schedule: PayoutSchedule) async throws {
        let payload = try encoder.encode(UpdateScheduleRequest(schedule: schedule.rawValue))

        if let base = AppConfig.backendBaseURL() {
            var request = try makeRequest(base: base, path: "v1/stripe/account/payout_schedule", method: "PUT")
            request.httpBody = payload
            _ = try await perform(request: request)
            return
        }

        guard let url = AppConfig.stripePayoutScheduleURL() else {
            throw StripeConnectError.missingConfiguration
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = payload
        _ = try await perform(request: request)
    }

    func triggerInstantPayout(amountCents: Int) async throws {
        let payload = try encoder.encode(InstantPayoutRequest(amountCents: amountCents))

        if let base = AppConfig.backendBaseURL() {
            var request = try makeRequest(base: base, path: "v1/stripe/account/instant_payout", method: "POST")
            request.httpBody = payload
            _ = try await perform(request: request)
            return
        }

        guard let url = AppConfig.stripeInstantPayoutURL() else {
            throw StripeConnectError.missingConfiguration
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = payload
        _ = try await perform(request: request)
    }

    // MARK: Helpers
    private func makeRequest(path: String, method: String = "GET") throws -> URLRequest {
        guard let base = AppConfig.backendBaseURL() else {
            throw StripeConnectError.missingConfiguration
        }
        return try makeRequest(base: base, path: path, method: method)
    }

    private func makeRequest(base: URL, path: String, method: String = "GET") throws -> URLRequest {
        let url = base.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if method == "POST" || method == "PUT" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    @discardableResult
    private func perform(request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw StripeConnectError.invalidResponse(status: -1)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw StripeConnectError.invalidResponse(status: http.statusCode)
        }
        return data
    }
}

private struct UpdateScheduleRequest: Codable {
    let schedule: String
}

private struct InstantPayoutRequest: Codable {
    let amountCents: Int

    enum CodingKeys: String, CodingKey {
        case amountCents = "amount_cents"
    }
}

extension PayoutSchedule {
    var displayName: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .manual: return "Manual"
        }
    }
}


