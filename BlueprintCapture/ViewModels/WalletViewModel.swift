import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class WalletViewModel: ObservableObject {
    @Published var totalEarnings: Decimal = 0
    @Published var pendingPayout: Decimal = 0
    @Published var scansCompleted: Int = 0

    /// Unpaid referral commissions earned by referring other users.
    /// Sourced directly from Firestore `users/{uid}/stats.referralEarningsCents`.
    @Published var referralEarningsCents: Int = 0

    /// One-time first-capture bonus the user earned by being referred.
    /// Sourced directly from Firestore `users/{uid}/stats.referralBonusCents`.
    @Published var referralBonusCents: Int = 0

    @Published var qcStatus: QualityControlStatus?
    @Published var captureHistory: [CaptureHistoryEntry] = []
    @Published var payoutLedger: [PayoutLedgerEntry] = []

    @Published var billingInfo: BillingInfo?
    @Published var stripeAccountState: StripeAccountState?

    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var isAuthenticated: Bool = false

    /// Combined pending amount = API pending payout + unpaid referral earnings + any first-capture bonus.
    var totalPending: Decimal {
        pendingPayout
            + Decimal(referralEarningsCents) / 100
            + Decimal(referralBonusCents) / 100
    }

    private let apiService = APIService.shared
    private let stripeService = StripeConnectService.shared
    private var referralListener: ListenerRegistration?

    init() {
        isAuthenticated = Auth.auth().currentUser != nil
        NotificationCenter.default.addObserver(forName: .AuthStateDidChange, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.isAuthenticated = Auth.auth().currentUser != nil
            if self.isAuthenticated {
                self.attachReferralListener()
            } else {
                self.detachReferralListener()
            }
            Task { await self.load() }
        }
        if isAuthenticated { attachReferralListener() }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        guard Auth.auth().currentUser != nil else {
            totalEarnings = 0
            pendingPayout = 0
            scansCompleted = 0
            referralEarningsCents = 0
            referralBonusCents = 0
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

            let earnings = try await earningsTask
            totalEarnings = earnings.total
            pendingPayout = earnings.pending
            scansCompleted = earnings.scansCompleted

            qcStatus = try await qcTask
            captureHistory = try await capturesTask
            payoutLedger = try await ledgerTask

            if RuntimeConfig.current.availability(for: .payouts).isEnabled {
                async let billingTask = apiService.fetchBillingInfo()
                async let stripeTask = stripeService.fetchAccountState()
                billingInfo = try await billingTask
                stripeAccountState = try await stripeTask
            } else {
                billingInfo = nil
                stripeAccountState = nil
            }
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

    // MARK: - Referral earnings listener

    private func attachReferralListener() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        detachReferralListener()
        referralListener = Firestore.firestore()
            .collection("users")
            .document(uid)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let data = snapshot?.data() else { return }
                let stats = data["stats"] as? [String: Any] ?? [:]
                self.referralEarningsCents = stats["referralEarningsCents"] as? Int ?? 0
                self.referralBonusCents    = stats["referralBonusCents"]    as? Int ?? 0
            }
    }

    private func detachReferralListener() {
        referralListener?.remove()
        referralListener = nil
    }
}
