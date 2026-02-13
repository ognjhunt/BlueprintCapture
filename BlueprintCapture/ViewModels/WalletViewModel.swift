import Foundation
import Combine
import FirebaseAuth

@MainActor
final class WalletViewModel: ObservableObject {
    @Published var totalEarnings: Decimal = 0
    @Published var pendingPayout: Decimal = 0
    @Published var scansCompleted: Int = 0

    @Published var qcStatus: QualityControlStatus?
    @Published var captureHistory: [CaptureHistoryEntry] = []
    @Published var payoutLedger: [PayoutLedgerEntry] = []

    @Published var billingInfo: BillingInfo?
    @Published var stripeAccountState: StripeAccountState?

    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var isAuthenticated: Bool = false

    private let apiService = APIService.shared
    private let stripeService = StripeConnectService.shared

    init() {
        isAuthenticated = Auth.auth().currentUser != nil
        NotificationCenter.default.addObserver(forName: .AuthStateDidChange, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.isAuthenticated = Auth.auth().currentUser != nil
            Task { await self.load() }
        }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        guard Auth.auth().currentUser != nil else {
            totalEarnings = 0
            pendingPayout = 0
            scansCompleted = 0
            qcStatus = nil
            captureHistory = []
            payoutLedger = []
            billingInfo = nil
            stripeAccountState = nil
            return
        }

        do {
            async let earningsTask = apiService.fetchEarnings()
            async let qcTask = apiService.fetchQualityControlStatus()
            async let capturesTask = apiService.fetchCaptureHistory()
            async let ledgerTask = apiService.fetchPayoutLedger()
            async let billingTask = apiService.fetchBillingInfo()
            async let stripeTask = stripeService.fetchAccountState()

            let earnings = try await earningsTask
            totalEarnings = earnings.total
            pendingPayout = earnings.pending
            scansCompleted = earnings.scansCompleted

            qcStatus = try await qcTask
            captureHistory = try await capturesTask
            payoutLedger = try await ledgerTask
            billingInfo = try await billingTask
            stripeAccountState = try await stripeTask
        } catch {
            errorMessage = "Unable to load wallet."
        }
    }

    func signOut() async {
        do {
            try Auth.auth().signOut()
            NotificationCenter.default.post(name: .AuthStateDidChange, object: nil)
        } catch {
            errorMessage = "Sign out failed."
        }
    }
}
