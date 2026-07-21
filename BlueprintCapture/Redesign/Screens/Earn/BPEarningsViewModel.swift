import Foundation
import Combine

// MARK: - BPEarningsViewModel
//
// Real wallet state for the Earnings tab: creator earnings totals, the payout
// ledger, and the Stripe Connect account/verification state. Everything is
// backend-derived; when the backend or the payout provider isn't available the
// published state says so honestly instead of showing sample numbers.

@MainActor
final class BPEarningsViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle

    @Published private(set) var totalEarned: Decimal?
    @Published private(set) var pending: Decimal?
    @Published private(set) var capturesCompleted: Int?
    @Published private(set) var ledger: [PayoutLedgerEntry] = []
    @Published private(set) var accountState: StripeAccountState?
    @Published private(set) var billingInfo: BillingInfo?
    @Published private(set) var verification: PayoutVerificationSummary?

    let payoutReady = RuntimeConfig.current.payoutProviderReady

    private var loadTask: Task<Void, Never>?

    func load() async {
        guard phase != .loading else { return }
        phase = .loading

        var sawBackend = false
        var firstError: String?

        if let earnings = try? await APIService.shared.fetchEarnings() {
            totalEarned = earnings.total
            pending = earnings.pending
            capturesCompleted = earnings.scansCompleted
            sawBackend = true
        } else {
            firstError = "Earnings sync is unavailable right now."
        }

        if let entries = try? await APIService.shared.fetchPayoutLedger() {
            ledger = entries.sorted { $0.scheduledFor > $1.scheduledFor }
            sawBackend = true
        }

        // Stripe account + verification only matter once the provider is live.
        if payoutReady {
            let state = try? await StripeConnectService.shared.fetchAccountState()
            accountState = state
            billingInfo = try? await APIService.shared.fetchBillingInfo()
            verification = PayoutVerificationSummary(
                isAuthenticated: UserDeviceService.hasRegisteredAccount(),
                accountState: state,
                billingInfo: billingInfo,
                payoutAvailability: RuntimeConfig.current.availability(for: .payouts)
            )
        }

        if sawBackend {
            phase = .loaded
        } else {
            phase = .failed(firstError ?? "Earnings sync is unavailable right now.")
        }
    }

    // MARK: Presentation helpers

    var totalEarnedLabel: String {
        Self.money(totalEarned)
    }

    var pendingLabel: String {
        Self.money(pending)
    }

    static func money(_ value: Decimal?) -> String {
        guard let value else { return "—" }
        return BPFormat.currency(NSDecimalNumber(decimal: value).doubleValue)
    }
}
