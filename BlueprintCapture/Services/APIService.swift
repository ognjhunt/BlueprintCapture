import Foundation

// MARK: - API Service

final class APIService {
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
}

