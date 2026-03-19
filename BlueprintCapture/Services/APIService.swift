import Foundation

// MARK: - API Service

final class APIService {
    enum APIError: Error, Equatable, LocalizedError {
        case missingBaseURL
        case invalidResponse(statusCode: Int)

        var errorDescription: String? {
            switch self {
            case .missingBaseURL:
                return "BLUEPRINT_BACKEND_BASE_URL is not configured for this build."
            case .invalidResponse(let statusCode) where statusCode == -1:
                return "The backend returned an invalid non-HTTP response."
            case .invalidResponse(let statusCode):
                return "The backend returned HTTP \(statusCode)."
            }
        }
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

    func registerCaptureSubmission(
        id: UUID,
        targetAddress: String,
        capturedAt: Date,
        quotedPayoutCents: Int?,
        captureJobId: String?,
        buyerRequestId: String?,
        siteSubmissionId: String?,
        rightsProfile: String?,
        requestedOutputs: [String]
    ) async throws {
        var request = try makeRequest(path: "v1/creator/captures", method: "POST")
        let payload = CreatorCaptureRegistrationPayload(
            id: id.uuidString.lowercased(),
            creatorId: UserDeviceService.resolvedUserId(),
            targetAddress: targetAddress,
            capturedAt: capturedAt,
            status: "submitted",
            estimatedPayoutCents: quotedPayoutCents,
            captureJobId: captureJobId,
            buyerRequestId: buyerRequestId,
            siteSubmissionId: siteSubmissionId,
            rightsProfile: rightsProfile,
            requestedOutputs: requestedOutputs
        )
        request.httpBody = try encoder.encode(payload)
        _ = try await perform(request: request, expecting: 201)
    }

    func fetchCaptureDetail(id: UUID) async throws -> CaptureDetailResponse? {
        let request = try makeRequest(path: "v1/creator/captures/\(id.uuidString.lowercased())")
        let (data, status) = try await performWithStatus(request: request)

        switch status {
        case 200:
            guard !data.isEmpty else { return nil }
            return try decoder.decode(CaptureDetailResponse.self, from: data)
        case 204, 404:
            return nil
        default:
            throw APIError.invalidResponse(statusCode: status)
        }
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

    func registerNotificationDevice(_ registration: NotificationDeviceRegistration) async throws {
        var request = try makeRequest(path: "v1/creator/devices/current", method: "PUT")
        request.httpBody = try encoder.encode(registration)
        _ = try await perform(request: request, expecting: 200)
    }

    func fetchNotificationPreferences() async throws -> NotificationPreferences? {
        let request = try makeRequest(path: "v1/creator/notifications/preferences")
        let (data, status) = try await performWithStatus(request: request)

        switch status {
        case 200:
            guard !data.isEmpty else { return nil }
            return try decoder.decode(NotificationPreferences.self, from: data)
        case 204, 404:
            return nil
        default:
            throw APIError.invalidResponse(statusCode: status)
        }
    }

    func updateNotificationPreferences(_ preferences: NotificationPreferences) async throws {
        var request = try makeRequest(path: "v1/creator/notifications/preferences", method: "PUT")
        request.httpBody = try encoder.encode(preferences)
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
        request.setValue(UserDeviceService.resolvedUserId(), forHTTPHeaderField: "X-Blueprint-Creator-Id")
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

private struct CreatorCaptureRegistrationPayload: Codable {
    let id: String
    let creatorId: String
    let targetAddress: String
    let capturedAt: Date
    let status: String
    let estimatedPayoutCents: Int?
    let captureJobId: String?
    let buyerRequestId: String?
    let siteSubmissionId: String?
    let rightsProfile: String?
    let requestedOutputs: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case creatorId = "creator_id"
        case targetAddress = "target_address"
        case capturedAt = "captured_at"
        case status
        case estimatedPayoutCents = "estimated_payout_cents"
        case captureJobId = "capture_job_id"
        case buyerRequestId = "buyer_request_id"
        case siteSubmissionId = "site_submission_id"
        case rightsProfile = "rights_profile"
        case requestedOutputs = "requested_outputs"
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
    case draft
    case readyToSubmit
    case submitted
    case underReview
    case processing
    case qc
    case approved
    case needsRecapture
    case needsFix
    case rejected
    case paid
}

extension CaptureStatus: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self).lowercased()
        switch raw {
        case "draft": self = .draft
        case "ready_to_submit", "ready-to-submit": self = .readyToSubmit
        case "submitted": self = .submitted
        case "under_review", "under-review": self = .underReview
        case "qc", "quality_control": self = .qc
        case "approved": self = .approved
        case "needs_recapture", "needs-recapture": self = .needsRecapture
        case "needs_fix", "needs-fix": self = .needsFix
        case "rejected": self = .rejected
        case "paid", "completed": self = .paid
        case "processing": self = .processing
        default: self = .processing
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .draft: try container.encode("draft")
        case .readyToSubmit: try container.encode("ready_to_submit")
        case .submitted: try container.encode("submitted")
        case .underReview: try container.encode("under_review")
        case .processing: try container.encode("processing")
        case .qc: try container.encode("qc")
        case .approved: try container.encode("approved")
        case .needsRecapture: try container.encode("needs_recapture")
        case .needsFix: try container.encode("needs_fix")
        case .rejected: try container.encode("rejected")
        case .paid: try container.encode("paid")
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

struct CaptureDetailResponse: Codable, Equatable {
    let id: UUID?
    let targetAddress: String?
    let capturedAt: Date?
    let status: CaptureStatus?
    let quality: CaptureQualityBreakdown?
    let earnings: CaptureEarningsBreakdown?
    let rejectionReason: String?
    let timeline: [CaptureTimelineEvent]

    enum CodingKeys: String, CodingKey {
        case id
        case targetAddress = "target_address"
        case capturedAt = "captured_at"
        case status
        case quality
        case earnings
        case rejectionReason = "rejection_reason"
        case timeline
    }

    init(
        id: UUID? = nil,
        targetAddress: String? = nil,
        capturedAt: Date? = nil,
        status: CaptureStatus? = nil,
        quality: CaptureQualityBreakdown? = nil,
        earnings: CaptureEarningsBreakdown? = nil,
        rejectionReason: String? = nil,
        timeline: [CaptureTimelineEvent] = []
    ) {
        self.id = id
        self.targetAddress = targetAddress
        self.capturedAt = capturedAt
        self.status = status
        self.quality = quality
        self.earnings = earnings
        self.rejectionReason = rejectionReason
        self.timeline = timeline
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let uuid = try? container.decode(UUID.self, forKey: .id) {
            self.id = uuid
        } else if let string = try? container.decode(String.self, forKey: .id), let uuid = UUID(uuidString: string) {
            self.id = uuid
        } else {
            self.id = nil
        }
        self.targetAddress = try container.decodeIfPresent(String.self, forKey: .targetAddress)
        self.capturedAt = try container.decodeIfPresent(Date.self, forKey: .capturedAt)
        self.status = try container.decodeIfPresent(CaptureStatus.self, forKey: .status)
        self.quality = try container.decodeIfPresent(CaptureQualityBreakdown.self, forKey: .quality)
        self.earnings = try container.decodeIfPresent(CaptureEarningsBreakdown.self, forKey: .earnings)
        self.rejectionReason = try container.decodeIfPresent(String.self, forKey: .rejectionReason)
        self.timeline = try container.decodeIfPresent([CaptureTimelineEvent].self, forKey: .timeline) ?? []
    }

    var hasRenderableDetail: Bool {
        quality != nil || earnings != nil || rejectionReason != nil || !timeline.isEmpty
    }
}

struct CaptureQualityBreakdown: Codable, Equatable {
    let overall: Int?
    let coverage: Int?
    let steadiness: Int?
    let completeness: Int?
    let depthQuality: Int?
    let blurScore: Int?

    enum CodingKeys: String, CodingKey {
        case overall
        case coverage
        case steadiness
        case completeness
        case depthQuality = "depth_quality"
        case blurScore = "blur_score"
    }
}

struct CaptureEarningsBreakdown: Codable, Equatable {
    let quotedPayoutCents: Int?
    let basePayoutCents: Int?
    let deviceMultiplier: Double?
    let qualityBonusCents: Int?
    let specialTaskBonusCents: Int?
    let referralBonusCents: Int?
    let bonuses: [CaptureEarningsBonus]
    let finalApprovedPayoutCents: Int?
    let totalPayoutCents: Int?

    enum CodingKeys: String, CodingKey {
        case quotedPayoutCents = "quoted_payout_cents"
        case basePayoutCents = "base_payout_cents"
        case deviceMultiplier = "device_multiplier"
        case qualityBonusCents = "quality_bonus_cents"
        case specialTaskBonusCents = "special_task_bonus_cents"
        case referralBonusCents = "referral_bonus_cents"
        case bonuses
        case finalApprovedPayoutCents = "final_approved_payout_cents"
        case totalPayoutCents = "total_payout_cents"
    }

    init(
        quotedPayoutCents: Int? = nil,
        basePayoutCents: Int? = nil,
        deviceMultiplier: Double? = nil,
        qualityBonusCents: Int? = nil,
        specialTaskBonusCents: Int? = nil,
        referralBonusCents: Int? = nil,
        bonuses: [CaptureEarningsBonus] = [],
        finalApprovedPayoutCents: Int? = nil,
        totalPayoutCents: Int? = nil
    ) {
        self.quotedPayoutCents = quotedPayoutCents
        self.basePayoutCents = basePayoutCents
        self.deviceMultiplier = deviceMultiplier
        self.qualityBonusCents = qualityBonusCents
        self.specialTaskBonusCents = specialTaskBonusCents
        self.referralBonusCents = referralBonusCents
        self.bonuses = bonuses
        self.finalApprovedPayoutCents = finalApprovedPayoutCents
        self.totalPayoutCents = totalPayoutCents
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.quotedPayoutCents = try container.decodeIfPresent(Int.self, forKey: .quotedPayoutCents)
        self.basePayoutCents = try container.decodeIfPresent(Int.self, forKey: .basePayoutCents)
        self.deviceMultiplier = try container.decodeIfPresent(Double.self, forKey: .deviceMultiplier)
        self.qualityBonusCents = try container.decodeIfPresent(Int.self, forKey: .qualityBonusCents)
        self.specialTaskBonusCents = try container.decodeIfPresent(Int.self, forKey: .specialTaskBonusCents)
        self.referralBonusCents = try container.decodeIfPresent(Int.self, forKey: .referralBonusCents)
        self.bonuses = try container.decodeIfPresent([CaptureEarningsBonus].self, forKey: .bonuses) ?? []
        self.finalApprovedPayoutCents = try container.decodeIfPresent(Int.self, forKey: .finalApprovedPayoutCents)
        self.totalPayoutCents = try container.decodeIfPresent(Int.self, forKey: .totalPayoutCents)
    }
}

struct CaptureEarningsBonus: Codable, Equatable, Identifiable {
    let label: String
    let amountCents: Int?
    let percentage: Double?

    var id: String { label }

    enum CodingKeys: String, CodingKey {
        case label
        case amountCents = "amount_cents"
        case percentage
    }
}

struct CaptureTimelineEvent: Codable, Equatable, Identifiable {
    let label: String
    let completedAt: Date?
    let state: String?

    var id: String { [label, completedAt?.ISO8601Format() ?? "pending"].joined(separator: "-") }

    enum CodingKeys: String, CodingKey {
        case label
        case completedAt = "completed_at"
        case state
    }

    var isCompleted: Bool {
        completedAt != nil || state?.lowercased() == "completed"
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
