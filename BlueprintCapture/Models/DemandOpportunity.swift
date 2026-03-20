import Foundation

enum DemandSourceKind: String, Codable, CaseIterable, Equatable {
    case explicitRequest = "explicit_request"
    case operatorOffer = "operator_offer"
    case citedWebSignal = "cited_web_signal"
    case inferredSignal = "inferred_signal"
    case internalBehavioralSignal = "internal_behavioral_signal"
}

enum DemandEvidenceStrength: String, Codable, CaseIterable, Equatable {
    case low
    case medium
    case high
    case critical
}

struct DemandSignalRecord: Codable, Equatable, Identifiable {
    let id: String
    let sourceType: String
    let sourceRef: String?
    let siteType: String
    let workflow: String?
    let companyId: String?
    let geoScope: String?
    let strength: DemandEvidenceStrength
    let confidence: Double
    let freshnessExpiresAt: Date?
    let citations: [URL]
    let demandSourceKinds: [DemandSourceKind]
    let summary: String?

    enum CodingKeys: String, CodingKey {
        case id
        case sourceType = "source_type"
        case sourceRef = "source_ref"
        case siteType = "site_type"
        case workflow
        case companyId = "company_id"
        case geoScope = "geo_scope"
        case strength
        case confidence
        case freshnessExpiresAt = "freshness_expires_at"
        case citations
        case demandSourceKinds = "demand_source_kinds"
        case summary
    }
}

struct RobotTeamDemandIntakePayload: Codable, Equatable {
    let requesterName: String?
    let requesterEmail: String?
    let companyName: String
    let companyDomain: String?
    let companyId: String?
    let targetGeography: String?
    let targetMetros: [String]
    let siteTypes: [String]
    let workflows: [String]
    let constraints: [String]
    let targetKPIs: [String]
    let urgency: DemandEvidenceStrength
    let notes: String?
    let citations: [URL]

    enum CodingKeys: String, CodingKey {
        case requesterName = "requester_name"
        case requesterEmail = "requester_email"
        case companyName = "company_name"
        case companyDomain = "company_domain"
        case companyId = "company_id"
        case targetGeography = "target_geography"
        case targetMetros = "target_metros"
        case siteTypes = "site_types"
        case workflows
        case constraints
        case targetKPIs = "target_kpis"
        case urgency
        case notes
        case citations
    }
}

struct SiteOperatorDemandIntakePayload: Codable, Equatable {
    let operatorName: String
    let operatorEmail: String?
    let companyName: String?
    let siteName: String
    let siteAddress: String
    let latitude: Double?
    let longitude: Double?
    let siteTypes: [String]
    let workflows: [String]
    let accessReadiness: DemandEvidenceStrength
    let consentReadiness: DemandEvidenceStrength
    let allowedCaptureWindows: [String]
    let restrictions: [String]
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case operatorName = "operator_name"
        case operatorEmail = "operator_email"
        case companyName = "company_name"
        case siteName = "site_name"
        case siteAddress = "site_address"
        case latitude
        case longitude
        case siteTypes = "site_types"
        case workflows
        case accessReadiness = "access_readiness"
        case consentReadiness = "consent_readiness"
        case allowedCaptureWindows = "allowed_capture_windows"
        case restrictions
        case notes
    }
}

struct DemandSignalSubmissionReceipt: Codable, Equatable {
    let submissionId: String
    let demandSignalIds: [String]
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case submissionId = "submission_id"
        case demandSignalIds = "demand_signal_ids"
        case createdAt = "created_at"
    }
}

struct OpportunityCandidatePlace: Codable, Equatable {
    let placeId: String
    let displayName: String
    let formattedAddress: String?
    let lat: Double
    let lng: Double
    let placeTypes: [String]

    enum CodingKeys: String, CodingKey {
        case placeId = "place_id"
        case displayName = "display_name"
        case formattedAddress = "formatted_address"
        case lat
        case lng
        case placeTypes = "place_types"
    }
}

struct DemandOpportunityFeedRequest: Codable, Equatable {
    let lat: Double
    let lng: Double
    let radiusMeters: Int
    let limit: Int
    let candidatePlaces: [OpportunityCandidatePlace]

    enum CodingKeys: String, CodingKey {
        case lat
        case lng
        case radiusMeters = "radius_m"
        case limit
        case candidatePlaces = "candidate_places"
    }
}

struct RankedNearbyOpportunity: Codable, Equatable, Identifiable {
    let placeId: String
    let displayName: String
    let formattedAddress: String?
    let lat: Double
    let lng: Double
    let placeTypes: [String]
    let siteType: String?
    let siteTypeConfidence: Double?
    let demandScore: Double
    let opportunityScore: Double
    let demandSummary: String?
    let rankingExplanation: String?
    let suggestedWorkflows: [String]
    let demandSourceKinds: [DemandSourceKind]
    let topSignalIds: [String]

    var id: String { placeId }

    enum CodingKeys: String, CodingKey {
        case placeId = "place_id"
        case displayName = "display_name"
        case formattedAddress = "formatted_address"
        case lat
        case lng
        case placeTypes = "place_types"
        case siteType = "site_type"
        case siteTypeConfidence = "site_type_confidence"
        case demandScore = "demand_score"
        case opportunityScore = "opportunity_score"
        case demandSummary = "demand_summary"
        case rankingExplanation = "ranking_explanation"
        case suggestedWorkflows = "suggested_workflows"
        case demandSourceKinds = "demand_source_kinds"
        case topSignalIds = "top_signal_ids"
    }
}

struct DemandOpportunityFeedResponse: Codable, Equatable {
    let generatedAt: Date?
    let nearbyOpportunities: [RankedNearbyOpportunity]
    let captureJobs: [ScanJob]

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case nearbyOpportunities = "nearby_opportunities"
        case captureJobs = "capture_jobs"
    }
}

protocol DemandIntelligenceServiceProtocol {
    func submitRobotTeamDemand(_ payload: RobotTeamDemandIntakePayload) async throws -> DemandSignalSubmissionReceipt
    func submitSiteOperatorDemand(_ payload: SiteOperatorDemandIntakePayload) async throws -> DemandSignalSubmissionReceipt
    func fetchDemandOpportunityFeed(_ request: DemandOpportunityFeedRequest) async throws -> DemandOpportunityFeedResponse
}
