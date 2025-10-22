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
    @Published var captureHistory: [CaptureHistoryEntry] = []
    @Published var qcStatus: QualityControlStatus?
    @Published var payoutLedger: [PayoutLedgerEntry] = []
    @Published var stripeAccountState: StripeAccountState?
    
    @Published var isEditing = false
    @Published var editingProfile: UserProfile = .placeholder
    @Published var isLoading = false
    @Published var error: SettingsError?
    @Published var showError = false
    
    private let apiService = APIService.shared
    private let stripeService = StripeConnectService.shared
    
    func loadUserData() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            async let profileTask = apiService.fetchUserProfile()
            async let earningsTask = apiService.fetchEarnings()
            async let billingTask = apiService.fetchBillingInfo()
            async let capturesTask = apiService.fetchCaptureHistory()
            async let qcTask = apiService.fetchQualityControlStatus()
            async let ledgerTask = apiService.fetchPayoutLedger()
            async let stripeTask = stripeService.fetchAccountState()

            let fetchedProfile = try await profileTask
            self.profile = fetchedProfile
            self.editingProfile = fetchedProfile

            let earnings = try await earningsTask
            self.totalEarnings = earnings.total
            self.pendingPayout = earnings.pending
            self.scansCompleted = earnings.scansCompleted

            if let billing = try await billingTask {
                self.billingInfo = billing
            } else {
                self.billingInfo = nil
            }

            self.captureHistory = try await capturesTask
            self.qcStatus = try await qcTask
            self.payoutLedger = try await ledgerTask
            self.stripeAccountState = try await stripeTask
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
            self.stripeAccountState = try? await stripeService.fetchAccountState()
            self.payoutLedger = (try? await apiService.fetchPayoutLedger()) ?? self.payoutLedger
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
            if let state = try? await stripeService.fetchAccountState() {
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

// MARK: - API Service
class APIService {
    enum APIError: Error {
        case missingBaseURL
        case invalidResponse(statusCode: Int)
    }

    static let shared = APIService()

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

    // MARK: Public API
    func fetchUserProfile() async throws -> UserProfile {
        let request = try makeRequest(path: "v1/creator/profile")
        let data = try await perform(request: request, expecting: 200)
        return try decoder.decode(UserProfile.self, from: data)
    }

    func updateUserProfile(_ profile: UserProfile) async throws -> UserProfile {
        var request = try makeRequest(path: "v1/creator/profile", method: "PUT")
        request.httpBody = try encoder.encode(profile)
        let data = try await perform(request: request, expecting: 200)
        return try decoder.decode(UserProfile.self, from: data)
    }

    func fetchEarnings() async throws -> (total: Decimal, pending: Decimal, scansCompleted: Int) {
        let request = try makeRequest(path: "v1/creator/earnings")
        let data = try await perform(request: request, expecting: 200)
        let response = try decoder.decode(EarningsResponse.self, from: data)
        return (
            total: Decimal(response.totalEarnedCents) / Decimal(100),
            pending: Decimal(response.pendingPayoutCents) / Decimal(100),
            scansCompleted: response.scansCompleted
        )
    }

    func fetchBillingInfo() async throws -> BillingInfo? {
        let request = try makeRequest(path: "v1/stripe/accounts/current")
        let (data, status) = try await performWithStatus(request: request)

        switch status {
        case 200:
            return try decoder.decode(BillingInfo.self, from: data)
        case 204, 404:
            return nil
        default:
            throw APIError.invalidResponse(statusCode: status)
        }
    }

    func fetchCaptureHistory() async throws -> [CaptureHistoryEntry] {
        let request = try makeRequest(path: "v1/creator/captures")
        let data = try await perform(request: request, expecting: 200)
        return try decoder.decode([CaptureHistoryEntry].self, from: data)
    }

    func fetchQualityControlStatus() async throws -> QualityControlStatus? {
        let request = try makeRequest(path: "v1/creator/qc")
        let data = try await perform(request: request, expecting: 200)
        guard !data.isEmpty else { return nil }
        return try decoder.decode(QualityControlStatus.self, from: data)
    }

    func fetchPayoutLedger() async throws -> [PayoutLedgerEntry] {
        let request = try makeRequest(path: "v1/creator/payouts/ledger")
        let data = try await perform(request: request, expecting: 200)
        guard !data.isEmpty else { return [] }
        return try decoder.decode([PayoutLedgerEntry].self, from: data)
    }

    func exchangePlaidToken(_ publicToken: String) async throws -> String {
        var request = try makeRequest(path: "v1/plaid/exchange", method: "POST")
        let payload = PlaidExchangeRequest(publicToken: publicToken)
        request.httpBody = try encoder.encode(payload)
        let data = try await perform(request: request, expecting: 200)
        let response = try decoder.decode(PlaidExchangeResponse.self, from: data)
        return response.accessToken
    }

    func createStripeAccount(accessToken: String, accountId: String, bankName: String) async throws -> BillingInfo {
        var request = try makeRequest(path: "v1/stripe/accounts", method: "POST")
        let payload = StripeAccountCreateRequest(
            plaidAccessToken: accessToken,
            accountId: accountId,
            bankName: bankName
        )
        request.httpBody = try encoder.encode(payload)
        let data = try await perform(request: request, expecting: 200)
        return try decoder.decode(BillingInfo.self, from: data)
    }

    func disconnectBankAccount(stripeAccountId: String) async throws {
        let path = "v1/stripe/accounts/\(stripeAccountId)"
        let request = try makeRequest(path: path, method: "DELETE")
        _ = try await perform(request: request, expecting: 200)
    }

    // MARK: Helpers
    private func baseURL() throws -> URL {
        guard let url = AppConfig.backendBaseURL() else {
            throw APIError.missingBaseURL
        }
        return url
    }

    private func makeRequest(path: String, method: String = "GET") throws -> URLRequest {
        let url = try baseURL().appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if method == "POST" || method == "PUT" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func perform(request: URLRequest, expecting successCode: Int) async throws -> Data {
        let (data, status) = try await performWithStatus(request: request)
        guard status == successCode || (successCode == 200 && (200..<300).contains(status)) else {
            throw APIError.invalidResponse(statusCode: status)
        }
        return data
    }

    private func performWithStatus(request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse(statusCode: -1)
        }
        return (data, http.statusCode)
    }
}

// MARK: - DTOs & Models
private struct EarningsResponse: Codable {
    let totalEarnedCents: Int
    let pendingPayoutCents: Int
    let scansCompleted: Int

    enum CodingKeys: String, CodingKey {
        case totalEarnedCents = "total_earned_cents"
        case pendingPayoutCents = "pending_payout_cents"
        case scansCompleted = "scans_completed"
    }
}

private struct PlaidExchangeRequest: Codable {
    let publicToken: String

    enum CodingKeys: String, CodingKey {
        case publicToken = "public_token"
    }
}

private struct PlaidExchangeResponse: Codable {
    let accessToken: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
    }
}

private struct StripeAccountCreateRequest: Codable {
    let plaidAccessToken: String
    let accountId: String
    let bankName: String

    enum CodingKeys: String, CodingKey {
        case plaidAccessToken = "plaid_access_token"
        case accountId = "account_id"
        case bankName = "bank_name"
    }
}

struct BillingInfo: Codable, Identifiable {
    let id = UUID()
    let bankName: String
    let lastFour: String
    let accountHolderName: String
    let stripeAccountId: String

    enum CodingKeys: String, CodingKey {
        case bankName = "bank_name"
        case lastFour = "last4"
        case accountHolderName = "account_holder_name"
        case stripeAccountId = "stripe_account_id"
    }
}

enum CaptureStatus: CaseIterable {
    case processing
    case qc
    case approved
    case needsFix
}

extension CaptureStatus: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self).lowercased()
        switch raw {
        case "qc", "quality_control": self = .qc
        case "approved": self = .approved
        case "needs_fix", "needs-fix": self = .needsFix
        case "processing": self = .processing
        default: self = .processing
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .processing: try container.encode("processing")
        case .qc: try container.encode("qc")
        case .approved: try container.encode("approved")
        case .needsFix: try container.encode("needs_fix")
        }
    }
}

struct CaptureHistoryEntry: Codable, Identifiable {
    let id: UUID
    let targetAddress: String
    let capturedAt: Date
    let status: CaptureStatus
    let estimatedPayoutCents: Int?
    let thumbnailURL: URL?

    enum CodingKeys: String, CodingKey {
        case id
        case targetAddress = "target_address"
        case capturedAt = "captured_at"
        case status
        case estimatedPayoutCents = "estimated_payout_cents"
        case thumbnailURL = "thumbnail_url"
    }

    init(id: UUID, targetAddress: String, capturedAt: Date, status: CaptureStatus, estimatedPayoutCents: Int?, thumbnailURL: URL?) {
        self.id = id
        self.targetAddress = targetAddress
        self.capturedAt = capturedAt
        self.status = status
        self.estimatedPayoutCents = estimatedPayoutCents
        self.thumbnailURL = thumbnailURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let uuid = try? container.decode(UUID.self, forKey: .id) {
            self.id = uuid
        } else if let string = try? container.decode(String.self, forKey: .id), let uuid = UUID(uuidString: string) {
            self.id = uuid
        } else {
            self.id = UUID()
        }
        self.targetAddress = try container.decode(String.self, forKey: .targetAddress)
        self.capturedAt = try container.decode(Date.self, forKey: .capturedAt)
        self.status = try container.decode(CaptureStatus.self, forKey: .status)
        self.estimatedPayoutCents = try container.decodeIfPresent(Int.self, forKey: .estimatedPayoutCents)
        self.thumbnailURL = try container.decodeIfPresent(URL.self, forKey: .thumbnailURL)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id.uuidString, forKey: .id)
        try container.encode(targetAddress, forKey: .targetAddress)
        try container.encode(capturedAt, forKey: .capturedAt)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(estimatedPayoutCents, forKey: .estimatedPayoutCents)
        try container.encodeIfPresent(thumbnailURL, forKey: .thumbnailURL)
    }

    var estimatedPayout: Decimal? {
        guard let cents = estimatedPayoutCents else { return nil }
        return Decimal(cents) / Decimal(100)
    }
}

struct QualityControlStatus: Codable {
    let pendingCount: Int
    let needsFixCount: Int
    let approvedCount: Int
    let averageTurnaroundHours: Double
    let lastUpdated: Date

    enum CodingKeys: String, CodingKey {
        case pendingCount = "pending_count"
        case needsFixCount = "needs_fix_count"
        case approvedCount = "approved_count"
        case averageTurnaroundHours = "average_turnaround_hours"
        case lastUpdated = "last_updated"
    }

    var approvalRate: Double {
        let total = Double(pendingCount + needsFixCount + approvedCount)
        guard total > 0 else { return 0 }
        return Double(approvedCount) / total
    }
}

enum PayoutLedgerStatus: Codable {
    case pending
    case inTransit
    case paid
    case failed

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self).lowercased()
        switch raw {
        case "pending": self = .pending
        case "in_transit", "in-transit": self = .inTransit
        case "paid", "completed": self = .paid
        case "failed", "canceled": self = .failed
        default: self = .pending
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .pending: try container.encode("pending")
        case .inTransit: try container.encode("in_transit")
        case .paid: try container.encode("paid")
        case .failed: try container.encode("failed")
        }
    }
}

struct PayoutLedgerEntry: Codable, Identifiable {
    let id: UUID
    let scheduledFor: Date
    let amountCents: Int
    let status: PayoutLedgerStatus
    let description: String?

    enum CodingKeys: String, CodingKey {
        case id
        case scheduledFor = "scheduled_for"
        case amountCents = "amount_cents"
        case status
        case description
    }

    init(id: UUID, scheduledFor: Date, amountCents: Int, status: PayoutLedgerStatus, description: String?) {
        self.id = id
        self.scheduledFor = scheduledFor
        self.amountCents = amountCents
        self.status = status
        self.description = description
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let uuid = try? container.decode(UUID.self, forKey: .id) {
            self.id = uuid
        } else if let string = try? container.decode(String.self, forKey: .id), let uuid = UUID(uuidString: string) {
            self.id = uuid
        } else {
            self.id = UUID()
        }
        self.scheduledFor = try container.decode(Date.self, forKey: .scheduledFor)
        self.amountCents = try container.decode(Int.self, forKey: .amountCents)
        self.status = try container.decode(PayoutLedgerStatus.self, forKey: .status)
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id.uuidString, forKey: .id)
        try container.encode(scheduledFor, forKey: .scheduledFor)
        try container.encode(amountCents, forKey: .amountCents)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(description, forKey: .description)
    }

    var amount: Decimal {
        Decimal(amountCents) / Decimal(100)
    }

    var isUpcoming: Bool {
        switch status {
        case .pending, .inTransit:
            return true
        case .paid, .failed:
            return false
        }
    }
}

