import Foundation
import SwiftUI
import Combine

enum SettingsError: LocalizedError {
    case networkError
    case invalidData
    case bankConnectionFailed
    
    var errorDescription: String? {
        switch self {
        case .networkError:
            return "Network connection failed. Please try again."
        case .invalidData:
            return "Invalid data received from server."
        case .bankConnectionFailed:
            return "Failed to connect bank account. Please try again."
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
    
    @Published var isEditing = false
    @Published var editingProfile: UserProfile = .placeholder
    @Published var isLoading = false
    @Published var error: SettingsError?
    @Published var showError = false
    
    private let apiService = APIService.shared
    
    func loadUserData() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Fetch profile
            let fetchedProfile = try await apiService.fetchUserProfile()
            self.profile = fetchedProfile
            self.editingProfile = fetchedProfile
            
            // Fetch earnings
            let earnings = try await apiService.fetchEarnings()
            self.totalEarnings = earnings.total
            self.pendingPayout = earnings.pending
            self.scansCompleted = earnings.scansCompleted
            
            // Fetch billing info
            if let billing = try await apiService.fetchBillingInfo() {
                self.billingInfo = billing
            }
        } catch {
            self.error = error as? SettingsError ?? .networkError
            self.showError = true
        }
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
    
    func connectPlaidBank(publicToken: String, accountId: String, bankName: String) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Exchange public token for access token (would happen on backend in production)
            let accessToken = try await apiService.exchangePlaidToken(publicToken)
            
            // Create Stripe account and link bank
            let billingInfo = try await apiService.createStripeAccount(
                accessToken: accessToken,
                accountId: accountId,
                bankName: bankName
            )
            
            self.billingInfo = billingInfo
        } catch {
            self.error = .bankConnectionFailed
            self.showError = true
        }
    }
    
    func disconnectBankAccount() async {
        guard let billingInfo = billingInfo else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            try await apiService.disconnectBankAccount(stripeAccountId: billingInfo.stripeAccountId)
            self.billingInfo = nil
        } catch {
            self.error = .networkError
            self.showError = true
        }
    }
}

// MARK: - API Service (Mock implementation)
class APIService {
    static let shared = APIService()
    private init() {}
    
    // MARK: User Profile
    func fetchUserProfile() async throws -> UserProfile {
        try await Task.sleep(nanoseconds: 500_000_000)
        return UserProfile.sample
    }
    
    func updateUserProfile(_ profile: UserProfile) async throws -> UserProfile {
        try await Task.sleep(nanoseconds: 800_000_000)
        // In production, this would send to your backend
        return profile
    }
    
    // MARK: Earnings
    func fetchEarnings() async throws -> (total: Decimal, pending: Decimal, scansCompleted: Int) {
        try await Task.sleep(nanoseconds: 500_000_000)
        return (total: 1250.50, pending: 325.00, scansCompleted: 42)
    }
    
    // MARK: Billing/Bank Connection
    func fetchBillingInfo() async throws -> BillingInfo? {
        try await Task.sleep(nanoseconds: 500_000_000)
        // Return nil on first load (no bank connected yet)
        // In production, this would fetch from your backend
        return BillingInfo(
            bankName: "Chase Bank",
            lastFour: "4242",
            accountHolderName: "Jordan Smith",
            stripeAccountId: "acct_sample123"
        )
    }
    
    func exchangePlaidToken(_ publicToken: String) async throws -> String {
        try await Task.sleep(nanoseconds: 1_000_000_000)
        // In production, this would call your backend which exchanges with Plaid
        // and returns an access token
        return "access_token_from_plaid_\(UUID().uuidString.prefix(8))"
    }
    
    func createStripeAccount(accessToken: String, accountId: String, bankName: String) async throws -> BillingInfo {
        try await Task.sleep(nanoseconds: 1_500_000_000)
        // In production, this would:
        // 1. Create a Stripe Connect account
        // 2. Link the Plaid bank account
        // 3. Set up transfers
        return BillingInfo(
            bankName: bankName,
            lastFour: "4242",
            accountHolderName: "Jordan Smith",
            stripeAccountId: "acct_\(UUID().uuidString.prefix(16))"
        )
    }
    
    func disconnectBankAccount(stripeAccountId: String) async throws {
        try await Task.sleep(nanoseconds: 800_000_000)
        // In production, this would deactivate the Stripe account
    }
}

struct BillingInfo: Codable, Identifiable {
    let id = UUID()
    let bankName: String
    let lastFour: String
    let accountHolderName: String
    let stripeAccountId: String
    
    enum CodingKeys: String, CodingKey {
        case bankName, lastFour, accountHolderName, stripeAccountId
    }
}

