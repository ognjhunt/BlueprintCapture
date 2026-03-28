import Foundation
import SwiftUI
import Combine
import FirebaseAuth

enum SettingsError: LocalizedError {
    case networkError
    case invalidData
    case bankConnectionFailed
    case accountDeletionFailed
    
    var errorDescription: String? {
        switch self {
        case .networkError:
            return "Network connection failed. Please try again."
        case .invalidData:
            return "Invalid data received from server."
        case .bankConnectionFailed:
            return "Failed to connect bank account. Please try again."
        case .accountDeletionFailed:
            return "We couldn't delete this account automatically. Sign in again or use the support link for manual deletion."
        }
    }
}

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var profile: UserProfile = .placeholder
    @Published var totalEarnings: Decimal = 0.0
    @Published var pendingPayout: Decimal = 0.0
    @Published var scansCompleted: Int = 0
    @Published var billingInfo: BillingInfo?
    @Published var captureHistory: [CaptureHistoryEntry] = []
    @Published var qcStatus: QualityControlStatus?
    @Published var payoutLedger: [PayoutLedgerEntry] = []
    @Published var stripeAccountState: StripeAccountState?
    
    @Published var isEditing = false
    @Published var editingProfile: UserProfile = .placeholder
    @Published var isLoading = false
    @Published var error: SettingsError?
    @Published var showError = false
    @Published var isAuthenticated: Bool = false
    
    private let apiService = APIService.shared
    private let stripeService = StripeConnectService.shared
    
    init() {
        isAuthenticated = UserDeviceService.hasRegisteredAccount()
        NotificationCenter.default.addObserver(forName: .AuthStateDidChange, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            self.isAuthenticated = UserDeviceService.hasRegisteredAccount()
            Task { await self.loadUserData() }
        }
    }
    
    func loadUserData() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // If not authenticated, load only public-safe defaults and return
            guard UserDeviceService.hasRegisteredAccount() else {
                self.profile = .placeholder
                self.totalEarnings = 0
                self.pendingPayout = 0
                self.scansCompleted = 0
                self.billingInfo = nil
                self.captureHistory = []
                self.qcStatus = nil
                self.payoutLedger = []
                self.stripeAccountState = nil
                return
            }
            guard AppConfig.hasBackendBaseURL() else {
                let currentUser = Auth.auth().currentUser
                let fallbackProfile = UserProfile(
                    fullName: currentUser?.displayName ?? "",
                    email: currentUser?.email ?? "",
                    phoneNumber: currentUser?.phoneNumber ?? "",
                    company: ""
                )
                self.profile = fallbackProfile
                self.editingProfile = fallbackProfile
                self.totalEarnings = 0
                self.pendingPayout = 0
                self.scansCompleted = 0
                self.billingInfo = nil
                self.captureHistory = []
                self.qcStatus = nil
                self.payoutLedger = []
                self.stripeAccountState = nil
                return
            }
            async let profileTask = apiService.fetchUserProfile()
            async let earningsTask = apiService.fetchEarnings()
            async let capturesTask = apiService.fetchCaptureHistory()
            async let qcTask = apiService.fetchQualityControlStatus()
            async let ledgerTask = apiService.fetchPayoutLedger()

            let fetchedProfile = try await profileTask
            self.profile = fetchedProfile
            self.editingProfile = fetchedProfile

            let earnings = try await earningsTask
            self.totalEarnings = earnings.total
            self.pendingPayout = earnings.pending
            self.scansCompleted = earnings.scansCompleted

            if RuntimeConfig.current.availability(for: .payouts).isEnabled {
                async let billingTask = apiService.fetchBillingInfo()
                async let stripeTask = stripeService.fetchAccountState()
                if let billing = try await billingTask {
                    self.billingInfo = billing
                } else {
                    self.billingInfo = nil
                }
                self.stripeAccountState = try await stripeTask
            } else {
                self.billingInfo = nil
                self.stripeAccountState = nil
            }

            self.captureHistory = try await capturesTask
            self.qcStatus = try await qcTask
            self.payoutLedger = try await ledgerTask
        } catch {
            self.error = error as? SettingsError ?? .networkError
            self.showError = true
        }
    }
    
    func signOut() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try Auth.auth().signOut()
            UserDeviceService.ensureAnonymousFirebaseUserIfNeeded()
            NotificationCenter.default.post(name: .AuthStateDidChange, object: nil)
            await loadUserData()
        } catch {
            self.error = .networkError
            self.showError = true
        }
    }

    func deleteAccount() async -> Bool {
        guard UserDeviceService.hasRegisteredAccount() else {
            return false
        }

        isLoading = true
        defer { isLoading = false }

        let deleted = await withCheckedContinuation { continuation in
            FirestoreManager.deleteAccount { success in
                continuation.resume(returning: success)
            }
        }

        guard deleted else {
            self.error = .accountDeletionFailed
            self.showError = true
            return false
        }

        UserDeviceService.ensureAnonymousFirebaseUserIfNeeded()
        NotificationCenter.default.post(name: .AuthStateDidChange, object: nil)
        await loadUserData()
        return true
    }
    
    func startEditingProfile() {
        editingProfile = profile
        isEditing = true
    }
    
    func cancelEditingProfile() {
        isEditing = false
        editingProfile = .placeholder
    }
    
    func saveProfile() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let updated = try await apiService.updateUserProfile(editingProfile)
            self.profile = updated
            self.isEditing = false
        } catch {
            self.error = error as? SettingsError ?? .networkError
            self.showError = true
        }
    }
    
    // Bank connection is completed within Stripe Connect onboarding; no client-side Plaid flow.
    
    func disconnectBankAccount() async {
        guard let billingInfo = billingInfo else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            try await apiService.disconnectBankAccount(stripeAccountId: billingInfo.stripeAccountId)
            self.billingInfo = nil
            if RuntimeConfig.current.availability(for: .payouts).isEnabled,
               let state = try? await stripeService.fetchAccountState() {
                self.stripeAccountState = state
            } else {
                self.stripeAccountState = nil
            }
        } catch {
            self.error = .networkError
            self.showError = true
        }
    }
}
