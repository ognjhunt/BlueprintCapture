// Extracted from CaptureFlowViewModel.swift (behavior-preserving decomposition).
import Foundation

struct SpaceReviewSeed: Identifiable, Equatable {
    let id: String
    let title: String
    let address: String?
    let payoutRange: ClosedRange<Int>?
    let captureJobId: String?
    let buyerRequestId: String?
    let siteSubmissionId: String?
    let regionId: String?
    let rightsProfile: String?
    let requestedOutputs: [String]
    let suggestedContext: String?
    let intakePacket: QualificationIntakePacket?
    let captureRights: CaptureRightsMetadata?
    let requestedCaptureMode: String?

    init(
        id: String = UUID().uuidString,
        title: String,
        address: String? = nil,
        payoutRange: ClosedRange<Int>? = nil,
        captureJobId: String? = nil,
        buyerRequestId: String? = nil,
        siteSubmissionId: String? = nil,
        regionId: String? = nil,
        rightsProfile: String? = nil,
        requestedOutputs: [String] = CaptureRequestedOutputs.reviewIntake,
        suggestedContext: String? = nil,
        intakePacket: QualificationIntakePacket? = nil,
        captureRights: CaptureRightsMetadata? = nil,
        requestedCaptureMode: String? = nil
    ) {
        self.id = id
        self.title = title
        self.address = address
        self.payoutRange = payoutRange
        self.captureJobId = captureJobId
        self.buyerRequestId = buyerRequestId
        self.siteSubmissionId = siteSubmissionId
        self.regionId = regionId
        self.rightsProfile = rightsProfile
        self.requestedOutputs = requestedOutputs
        self.suggestedContext = suggestedContext
        self.intakePacket = intakePacket
        self.captureRights = captureRights
        self.requestedCaptureMode = requestedCaptureMode
    }
}

enum SiteWorldSiteScale: String, CaseIterable, Identifiable {
    case smallSimple = "small_simple"
    case medium
    case multiZone = "multi_zone"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smallSimple:
            return "Small / Simple"
        case .medium:
            return "Medium"
        case .multiZone:
            return "Multi-zone"
        }
    }

    var subtitle: String {
        switch self {
        case .smallSimple:
            return "Single route with one clean return"
        case .medium:
            return "Main spine with shared checkpoints"
        case .multiZone:
            return "Hub-and-spoke zones with returns"
        }
    }
}

/// Capture-declared site type, mirroring the pipeline's canonical site-type taxonomy
/// (`blueprint_pipeline.site_taxonomy` / `scene_semantics`). Each `rawValue` is the
/// exact `site_type` token the pipeline recognizes; the selected case's `rawValue` is
/// written into the raw manifest's `intended_space_type` field as capture truth.
/// `.unknown` is the explicit, non-blocking fallback when the capturer has not
/// declared a site type (it resolves to the pipeline's `UNKNOWN_SITE_CATEGORY`).
enum SiteType: String, CaseIterable, Identifiable {
    case warehouse
    case manufacturing
    case fulfillment
    case coldStorage = "cold_storage"
    case stockroom
    case kitchen
    case lab
    case hospital
    case retail
    case office
    case residential
    case unknown

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .warehouse:
            return "Warehouse"
        case .manufacturing:
            return "Manufacturing"
        case .fulfillment:
            return "Fulfillment"
        case .coldStorage:
            return "Cold Storage"
        case .stockroom:
            return "Stockroom"
        case .kitchen:
            return "Kitchen"
        case .lab:
            return "Lab"
        case .hospital:
            return "Hospital"
        case .retail:
            return "Retail"
        case .office:
            return "Office"
        case .residential:
            return "Residential"
        case .unknown:
            return "Not sure / Other"
        }
    }
}

enum SiteWorldReviewTone: String, Equatable {
    case ready
    case caution
    case actionRequired

    var title: String {
        switch self {
        case .ready:
            return "Ready"
        case .caution:
            return "Needs Next Pass"
        case .actionRequired:
            return "Needs Recapture"
        }
    }
}

struct SiteWorldPassBrief: Equatable {
    let role: String
    let title: String
    let summary: String
    let requiredCheckpointTarget: Int
    let requiredPrompt: String
    let exactPrompts: [String]
}

struct SiteWorldPassReview: Equatable {
    let passAttemptIndex: Int
    let passRole: String
    let title: String
    let tone: SiteWorldReviewTone
    let score: Int
    let summary: String
    let completedItems: [String]
    let missingItems: [String]
    let weakSignalSummary: String?
    let nextActionLabel: String?
    let canFinishWorkflow: Bool
    let shouldAdvanceWorkflow: Bool
    let completedRequiredPasses: Int
    let totalRequiredPasses: Int
    let exactPrompts: [String]
}
