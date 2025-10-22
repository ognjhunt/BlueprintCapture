import Foundation

struct StripeAccountLinks: Codable {
    let onboardingURL: URL
}

enum PayoutSchedule: String, CaseIterable, Codable {
    case daily, weekly, monthly, manual
}

final class StripeConnectService {
    static let shared = StripeConnectService()
    private init() {}

    func createOnboardingLink() async throws -> URL {
        if let url = AppConfig.stripeOnboardingURL() {
            return url
        }
        throw URLError(.badURL)
    }

    func updatePayoutSchedule(_ schedule: PayoutSchedule) async throws {
        // In production, call backend to update Stripe payout schedule
        try await Task.sleep(nanoseconds: 400_000_000)
    }

    func triggerInstantPayout(amountCents: Int) async throws {
        // In production, create an Instant Payout via backend
        try await Task.sleep(nanoseconds: 800_000_000)
    }
}


