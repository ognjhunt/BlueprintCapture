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
        case decodingError(Error)
        case networkError(Error)
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
        print("[Stripe] Creating onboarding link...")
        
        if let base = AppConfig.backendBaseURL() {
            print("[Stripe] Using backend URL: \(base)")
            do {
                var request = try makeRequest(base: base, path: "v1/stripe/account/onboarding_link", method: "POST")
                print("[Stripe] Request URL: \(request.url?.absoluteString ?? "N/A")")
                let data = try await perform(request: request)
                let links = try decoder.decode(StripeAccountLinks.self, from: data)
                print("[Stripe] ✓ Onboarding link created successfully")
                return links.onboardingURL
            } catch let error as StripeConnectError {
                print("[Stripe] ✗ Stripe error creating onboarding link: \(error)")
                throw error
            } catch {
                print("[Stripe] ✗ Error creating onboarding link: \(error)")
                throw StripeConnectError.networkError(error)
            }
        }

        if let url = AppConfig.stripeOnboardingURL() {
            print("[Stripe] Using fallback onboarding URL from config: \(url)")
            return url
        }

        print("[Stripe] ✗ Missing configuration: No backend URL or fallback onboarding URL")
        throw StripeConnectError.missingConfiguration
    }

    func fetchAccountState() async throws -> StripeAccountState {
        print("[Stripe] Fetching account state...")
        
        guard let base = AppConfig.backendBaseURL() else {
            print("[Stripe] ✗ Missing backend URL configuration")
            throw StripeConnectError.missingConfiguration
        }
        
        print("[Stripe] Using backend URL: \(base)")
        
        do {
            let request = try makeRequest(path: "v1/stripe/account")
            print("[Stripe] Request URL: \(request.url?.absoluteString ?? "N/A")")
            let data = try await perform(request: request)
            
            do {
                let state = try decoder.decode(StripeAccountState.self, from: data)
                print("[Stripe] ✓ Account state fetched successfully")
                print("[Stripe] Account ready: \(state.isReadyForTransfers), Payouts enabled: \(state.payoutsEnabled)")
                return state
            } catch let decodingError {
                print("[Stripe] ✗ Decoding error: \(decodingError)")
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("[Stripe] Response body: \(jsonString)")
                }
                throw StripeConnectError.decodingError(decodingError)
            }
        } catch let error as StripeConnectError {
            print("[Stripe] ✗ Stripe error: \(error)")
            throw error
        } catch {
            print("[Stripe] ✗ Network error: \(error)")
            throw StripeConnectError.networkError(error)
        }
    }

    func updatePayoutSchedule(_ schedule: PayoutSchedule) async throws {
        print("[Stripe] Updating payout schedule to: \(schedule.rawValue)")
        
        let payload = try encoder.encode(UpdateScheduleRequest(schedule: schedule.rawValue))

        if let base = AppConfig.backendBaseURL() {
            print("[Stripe] Using backend URL: \(base)")
            do {
                var request = try makeRequest(base: base, path: "v1/stripe/account/payout_schedule", method: "PUT")
                request.httpBody = payload
                print("[Stripe] Request URL: \(request.url?.absoluteString ?? "N/A")")
                _ = try await perform(request: request)
                print("[Stripe] ✓ Payout schedule updated successfully")
                return
            } catch {
                print("[Stripe] ✗ Error updating schedule: \(error)")
                throw error
            }
        }

        guard let url = AppConfig.stripePayoutScheduleURL() else {
            print("[Stripe] ✗ Missing configuration for payout schedule URL")
            throw StripeConnectError.missingConfiguration
        }

        print("[Stripe] Using fallback URL: \(url)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = payload
        
        do {
            _ = try await perform(request: request)
            print("[Stripe] ✓ Payout schedule updated successfully")
        } catch {
            print("[Stripe] ✗ Error updating schedule: \(error)")
            throw error
        }
    }

    func triggerInstantPayout(amountCents: Int) async throws {
        print("[Stripe] Triggering instant payout for: $\(amountCents / 100).\(String(format: "%02d", amountCents % 100))")
        
        let payload = try encoder.encode(InstantPayoutRequest(amountCents: amountCents))

        if let base = AppConfig.backendBaseURL() {
            print("[Stripe] Using backend URL: \(base)")
            do {
                var request = try makeRequest(base: base, path: "v1/stripe/account/instant_payout", method: "POST")
                request.httpBody = payload
                print("[Stripe] Request URL: \(request.url?.absoluteString ?? "N/A")")
                _ = try await perform(request: request)
                print("[Stripe] ✓ Instant payout triggered successfully")
                return
            } catch {
                print("[Stripe] ✗ Error triggering instant payout: \(error)")
                throw error
            }
        }

        guard let url = AppConfig.stripeInstantPayoutURL() else {
            print("[Stripe] ✗ Missing configuration for instant payout URL")
            throw StripeConnectError.missingConfiguration
        }

        print("[Stripe] Using fallback URL: \(url)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = payload
        
        do {
            _ = try await perform(request: request)
            print("[Stripe] ✓ Instant payout triggered successfully")
        } catch {
            print("[Stripe] ✗ Error triggering instant payout: \(error)")
            throw error
        }
    }

    // MARK: Helpers
    private func makeRequest(path: String, method: String = "GET") throws -> URLRequest {
        guard let base = AppConfig.backendBaseURL() else {
            print("[Stripe] ✗ Missing backend base URL")
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
        print("[Stripe] Created \(method) request to: \(url.absoluteString)")
        return request
    }

    @discardableResult
    private func perform(request: URLRequest) async throws -> Data {
        print("[Stripe] Performing request: \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "N/A")")
        
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                print("[Stripe] ✗ Invalid response type (not HTTP)")
                throw StripeConnectError.invalidResponse(status: -1)
            }
            
            print("[Stripe] Response status: \(http.statusCode)")
            
            guard (200..<300).contains(http.statusCode) else {
                if let responseString = String(data: data, encoding: .utf8) {
                    print("[Stripe] ✗ HTTP \(http.statusCode): \(responseString)")
                } else {
                    print("[Stripe] ✗ HTTP \(http.statusCode)")
                }
                throw StripeConnectError.invalidResponse(status: http.statusCode)
            }
            
            print("[Stripe] ✓ Request successful (status \(http.statusCode))")
            return data
        } catch let error as StripeConnectError {
            print("[Stripe] ✗ Stripe error in perform: \(error)")
            throw error
        } catch {
            print("[Stripe] ✗ Network error in perform: \(error.localizedDescription)")
            throw StripeConnectError.networkError(error)
        }
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


