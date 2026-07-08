// Extracted from CaptureUploadService.swift (behavior-preserving decomposition).
import Foundation

struct QualificationIntakePacket: Equatable, Codable {
    let schemaVersion: String
    let workflowName: String?
    let taskSteps: [String]
    let targetKPI: String?
    let zone: String?
    let shift: String?
    let owner: String?
    let facilityTemplate: String?
    let requiredCoverageAreas: [String]
    let benchmarkStations: [String]
    let adjacentSystems: [String]
    let privacySecurityLimits: [String]
    let knownBlockers: [String]
    let nonRoutineModes: [String]
    let peopleTrafficNotes: [String]
    let captureRestrictions: [String]
    let lightingWindows: [String]
    let shiftTrafficWindows: [String]
    let movableObstacles: [String]
    let floorConditionNotes: [String]
    let reflectiveSurfaceNotes: [String]
    let accessRules: [String]

    init(
        schemaVersion: String = "v1",
        workflowName: String? = nil,
        taskSteps: [String] = [],
        targetKPI: String? = nil,
        zone: String? = nil,
        shift: String? = nil,
        owner: String? = nil,
        facilityTemplate: String? = nil,
        requiredCoverageAreas: [String] = [],
        benchmarkStations: [String] = [],
        adjacentSystems: [String] = [],
        privacySecurityLimits: [String] = [],
        knownBlockers: [String] = [],
        nonRoutineModes: [String] = [],
        peopleTrafficNotes: [String] = [],
        captureRestrictions: [String] = [],
        lightingWindows: [String] = [],
        shiftTrafficWindows: [String] = [],
        movableObstacles: [String] = [],
        floorConditionNotes: [String] = [],
        reflectiveSurfaceNotes: [String] = [],
        accessRules: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.workflowName = workflowName
        self.taskSteps = taskSteps
        self.targetKPI = targetKPI
        self.zone = zone
        self.shift = shift
        self.owner = owner
        self.facilityTemplate = facilityTemplate
        self.requiredCoverageAreas = requiredCoverageAreas
        self.benchmarkStations = benchmarkStations
        self.adjacentSystems = adjacentSystems
        self.privacySecurityLimits = privacySecurityLimits
        self.knownBlockers = knownBlockers
        self.nonRoutineModes = nonRoutineModes
        self.peopleTrafficNotes = peopleTrafficNotes
        self.captureRestrictions = captureRestrictions
        self.lightingWindows = lightingWindows
        self.shiftTrafficWindows = shiftTrafficWindows
        self.movableObstacles = movableObstacles
        self.floorConditionNotes = floorConditionNotes
        self.reflectiveSurfaceNotes = reflectiveSurfaceNotes
        self.accessRules = accessRules
    }

    var isComplete: Bool {
        let hasWorkflow = !(workflowName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasSteps = !taskSteps.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.isEmpty
        let hasZoneOrOwner = !((zone?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) && (owner?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true))
        return hasWorkflow && hasSteps && hasZoneOrOwner
    }
}

struct CaptureScaffoldingPacket: Equatable, Codable {
    let schemaVersion: String
    let scaffoldingUsed: [String]
    let coveragePlan: [String]
    let calibrationAssets: [String]
    let scaleAnchorAssets: [String]
    let checkpointAssets: [String]
    let validatedScaleMeters: Double?
    let validatedPoseCoverage: Double?
    let hiddenZoneBound: Double?
    let uncertaintyPriors: [String: Double]

    init(
        schemaVersion: String = "v1",
        scaffoldingUsed: [String] = [],
        coveragePlan: [String] = [],
        calibrationAssets: [String] = [],
        scaleAnchorAssets: [String] = [],
        checkpointAssets: [String] = [],
        validatedScaleMeters: Double? = nil,
        validatedPoseCoverage: Double? = nil,
        hiddenZoneBound: Double? = nil,
        uncertaintyPriors: [String: Double] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.scaffoldingUsed = scaffoldingUsed
        self.coveragePlan = coveragePlan
        self.calibrationAssets = calibrationAssets
        self.scaleAnchorAssets = scaleAnchorAssets
        self.checkpointAssets = checkpointAssets
        self.validatedScaleMeters = validatedScaleMeters
        self.validatedPoseCoverage = validatedPoseCoverage
        self.hiddenZoneBound = hiddenZoneBound
        self.uncertaintyPriors = uncertaintyPriors
    }

    var hasValidatedMetricBundle: Bool {
        guard !calibrationAssets.isEmpty,
              !scaleAnchorAssets.isEmpty,
              !checkpointAssets.isEmpty,
              let validatedScaleMeters,
              validatedScaleMeters > 0,
              let validatedPoseCoverage,
              validatedPoseCoverage >= 0.7,
              let hiddenZoneBound,
              hiddenZoneBound <= 0.35 else {
            return false
        }
        return true
    }
}

struct SiteGeoPoint: Equatable, Codable {
    let latitude: Double
    let longitude: Double
    let accuracyM: Double
}

struct SiteIdentity: Equatable, Codable {
    let siteId: String
    let siteIdSource: String   // "buyer_request" | "site_submission" | "open_capture"
    let placeId: String?
    let siteName: String?
    let addressFull: String?
    let geo: SiteGeoPoint?
    let buildingId: String?
    let floorId: String?
    let roomId: String?
    let zoneId: String?
}

struct CaptureTopologyMetadata: Equatable, Codable {
    let captureSessionId: String
    let routeId: String
    let passId: String
    let passIndex: Int
    let intendedPassRole: String   // "primary" | "revisit" | "loop_closure" | "critical_zone_revisit"
    let entryAnchorId: String?
    let returnAnchorId: String?
    let entryAnchorTCaptureSec: Double?      // t_device_sec midpoint of detected entry hold
    let entryAnchorHoldDurationSec: Double?  // seconds held at entry anchor
    let siteVisitId: String?
    let coordinateFrameSessionId: String?
    let arkitSessionId: String?

    init(
        captureSessionId: String,
        routeId: String,
        passId: String,
        passIndex: Int,
        intendedPassRole: String,
        entryAnchorId: String?,
        returnAnchorId: String?,
        entryAnchorTCaptureSec: Double?,
        entryAnchorHoldDurationSec: Double?,
        siteVisitId: String? = nil,
        coordinateFrameSessionId: String? = nil,
        arkitSessionId: String? = nil
    ) {
        self.captureSessionId = captureSessionId
        self.routeId = routeId
        self.passId = passId
        self.passIndex = passIndex
        self.intendedPassRole = intendedPassRole
        self.entryAnchorId = entryAnchorId
        self.returnAnchorId = returnAnchorId
        self.entryAnchorTCaptureSec = entryAnchorTCaptureSec
        self.entryAnchorHoldDurationSec = entryAnchorHoldDurationSec
        self.siteVisitId = siteVisitId
        self.coordinateFrameSessionId = coordinateFrameSessionId
        self.arkitSessionId = arkitSessionId
    }
}

struct CaptureModeMetadata: Equatable, Codable {
    let requestedMode: String    // "qualification_only" | "site_world_candidate"
    let resolvedMode: String     // may be downgraded at finalization
    let downgradeReason: String?
}

enum CaptureSemanticAnchorType: String, Codable, CaseIterable {
    case entrance
    case doorway
    case corridorIntersection = "corridor_intersection"
    case dockTurn = "dock_turn"
    case handoffPoint = "handoff_point"
    case controlPanel = "control_panel"
    case floorTransition = "floor_transition"
    case restrictedBoundary = "restricted_boundary"
    case exitPoint = "exit_point"

    var displayLabel: String {
        switch self {
        case .entrance:
            return "Entrance"
        case .doorway:
            return "Doorway"
        case .corridorIntersection:
            return "Intersection"
        case .dockTurn:
            return "Dock Turn"
        case .handoffPoint:
            return "Handoff"
        case .controlPanel:
            return "Control Panel"
        case .floorTransition:
            return "Floor Transition"
        case .restrictedBoundary:
            return "Restricted Boundary"
        case .exitPoint:
            return "Exit"
        }
    }
}

struct CaptureSemanticAnchorEvent: Equatable, Codable, Identifiable {
    let id: String
    let anchorType: CaptureSemanticAnchorType
    let label: String?
    let frameId: String?
    let tCaptureSec: Double?
    let coordinateFrameSessionId: String?
    let notes: String?

    init(
        id: String = UUID().uuidString,
        anchorType: CaptureSemanticAnchorType,
        label: String? = nil,
        frameId: String? = nil,
        tCaptureSec: Double? = nil,
        coordinateFrameSessionId: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.anchorType = anchorType
        self.label = label
        self.frameId = frameId
        self.tCaptureSec = tCaptureSec
        self.coordinateFrameSessionId = coordinateFrameSessionId
        self.notes = notes
    }
}

struct SceneMemoryCaptureMetadata: Equatable, Codable {
    let continuityScore: Double?
    let lightingConsistency: String?
    let dynamicObjectDensity: String?
    let operatorNotes: [String]
    let inaccessibleAreas: [String]
    let semanticAnchorsObserved: [String]
    let relocalizationCount: Int?
    let overlapCheckpointCount: Int?

    init(
        continuityScore: Double? = nil,
        lightingConsistency: String? = nil,
        dynamicObjectDensity: String? = nil,
        operatorNotes: [String] = [],
        inaccessibleAreas: [String] = [],
        semanticAnchorsObserved: [String] = [],
        relocalizationCount: Int? = nil,
        overlapCheckpointCount: Int? = nil
    ) {
        self.continuityScore = continuityScore
        self.lightingConsistency = lightingConsistency
        self.dynamicObjectDensity = dynamicObjectDensity
        self.operatorNotes = operatorNotes
        self.inaccessibleAreas = inaccessibleAreas
        self.semanticAnchorsObserved = semanticAnchorsObserved
        self.relocalizationCount = relocalizationCount
        self.overlapCheckpointCount = overlapCheckpointCount
    }
}

enum CaptureConsentStatus: String, Codable {
    case documented
    case policyOnly = "policy_only"
    case unknown
}

struct CaptureRightsMetadata: Equatable, Codable {
    let derivedSceneGenerationAllowed: Bool
    let dataLicensingAllowed: Bool
    let payoutEligible: Bool
    let consentStatus: CaptureConsentStatus
    let permissionDocumentURI: String?
    let consentScope: [String]
    let consentNotes: [String]

    init(
        derivedSceneGenerationAllowed: Bool = false,
        dataLicensingAllowed: Bool = false,
        payoutEligible: Bool = false,
        consentStatus: CaptureConsentStatus = .unknown,
        permissionDocumentURI: String? = nil,
        consentScope: [String] = [],
        consentNotes: [String] = []
    ) {
        self.derivedSceneGenerationAllowed = derivedSceneGenerationAllowed
        self.dataLicensingAllowed = dataLicensingAllowed
        self.payoutEligible = payoutEligible
        self.consentStatus = consentStatus
        self.permissionDocumentURI = permissionDocumentURI
        self.consentScope = consentScope
        self.consentNotes = consentNotes
    }
}

enum CaptureAuthorityLevel: String, Codable {
    case authoritativeRaw = "authoritative_raw"
    case rawTrackingOnly = "raw_tracking_only"
    case diagnosticOnly = "diagnostic_only"
    case notAvailable = "not_available"
    case derivedLaterExpected = "derived_later_expected"
}

struct CaptureCapabilitiesMetadata: Equatable, Codable {
    let cameraPose: Bool
    let cameraIntrinsics: Bool
    let depth: Bool
    let depthConfidence: Bool
    let missingDepthReason: String?
    let mesh: Bool
    let pointCloud: Bool
    let planes: Bool
    let featurePoints: Bool
    let trackingState: Bool
    let relocalizationEvents: Bool
    let lightEstimate: Bool
    let motion: Bool
    let motionAuthoritative: Bool
    let companionPhonePose: Bool
    let companionPhoneIntrinsics: Bool
    let companionPhoneCalibration: Bool
    let poseRows: Int
    let intrinsicsValid: Bool
    let depthFrames: Int
    let confidenceFrames: Int
    let meshFiles: Int
    let pointCloudSamples: Int
    let planeRows: Int
    let featurePointRows: Int
    let trackingStateRows: Int
    let relocalizationEventRows: Int
    let lightEstimateRows: Int
    let motionSamples: Int
    let poseAuthority: CaptureAuthorityLevel
    let intrinsicsAuthority: CaptureAuthorityLevel
    let depthAuthority: CaptureAuthorityLevel
    let motionAuthority: CaptureAuthorityLevel
    let motionProvenance: String?
    let geometrySource: String?
    let geometryExpectedDownstream: Bool
}

enum CaptureRequestedOutputs {
    static let scaniverseAssistedCapture = "scaniverse_assisted_capture"
    static let reviewIntake = ["qualification", "review_intake"]
    static let robotEvaluation = ["qualification", "robot_eval_dataset", "task_evaluation_run"]
    static let scaniverseAssistedRobotEvaluation = [
        "qualification",
        "robot_eval_dataset",
        scaniverseAssistedCapture,
    ]

    static func normalized(_ outputs: [String]) -> [String] {
        var normalized: [String] = []
        for output in outputs {
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !normalized.contains(trimmed) else { continue }
            normalized.append(trimmed)
        }

        let asksForLegacyEvaluation =
            normalized.contains("preview_simulation") ||
            normalized.contains("deeper_evaluation")
        let asksForRobotEvaluation =
            normalized.contains("robot_eval_dataset") ||
            normalized.contains("task_evaluation_run")

        if asksForLegacyEvaluation || asksForRobotEvaluation {
            append("robot_eval_dataset", to: &normalized)
        }
        if normalized.contains("deeper_evaluation") || normalized.contains("task_evaluation_run") {
            append("task_evaluation_run", to: &normalized)
        }
        if normalized.contains("preview_simulation") && !normalized.contains("deeper_evaluation") {
            append("deeper_evaluation", to: &normalized)
        }
        if normalized.contains(scaniverseAssistedCapture) {
            append("robot_eval_dataset", to: &normalized)
        }
        return normalized
    }

    private static func append(_ output: String, to values: inout [String]) {
        if !values.contains(output) {
            values.append(output)
        }
    }
}

enum ScaniverseAssistedCaptureContract {
    static let requestedOutput = CaptureRequestedOutputs.scaniverseAssistedCapture
    static let workflowMarker = "scaniverse_external_asset_expected"
    static let recommendedCaptureHardware = ["Insta360 X5", "Insta360 X4"]

    static let acceptedExportExtensions = [
        "usdz",
        "ply",
        "spz",
        "glb",
        "gltf",
        "fbx",
        "obj",
        "usd",
        "usda",
        "usdc",
    ]

    static let captureChecklist = [
        "Record the normal Blueprint raw evidence bundle for assignment, rights, and provenance.",
        "Capture 360 video with supported hardware, preferably Insta360 X5 or X4 when available.",
        "Upload and process the 360 video in Scaniverse Web from a desktop browser.",
        "Export USDZ plus available PLY, SPZ, GLB/GLTF, FBX, OBJ, or USD assets for Pipeline import.",
        "Keep Scaniverse exports labeled as derived support assets until Pipeline review accepts them.",
    ]

    static let proofBoundaryNotes = [
        "Scaniverse exports do not replace raw Blueprint capture truth.",
        "USDZ or mesh export does not prove Isaac import, physics contact, policy success, or deployment readiness.",
        "Free or Plus Scaniverse access is not enough evidence for commercial rights or API support.",
        "Pipeline must preserve checksums and run local preflight before any simulator handoff claim.",
    ]
}

struct CaptureUploadMetadata: Identifiable, Equatable, Codable {
    enum CaptureSource: String, Codable {
        case iphoneVideo
        case metaGlasses
    }

    enum SpecialTaskType: String, Codable {
        case curatedNearby = "curated_nearby"
        case buyerRequested = "buyer_requested_special_task"
        case operatorApproved = "operator_approved_on_demand"
        case openCapture = "open_capture"
    }

    let id: UUID
    let targetId: String?
    let reservationId: String?
    let jobId: String
    let captureJobId: String?
    let buyerRequestId: String?
    let siteSubmissionId: String?
    let regionId: String?
    let creatorId: String
    let capturedAt: Date
    var uploadedAt: Date?
    let captureSource: CaptureSource
    let specialTaskType: SpecialTaskType?
    let priorityWeight: Double?
    let quotedPayoutCents: Int?
    let rightsProfile: String?
    let requestedOutputs: [String]
    var intakePacket: QualificationIntakePacket?
    var intakeMetadata: CaptureIntakeMetadata?
    var taskHypothesis: CaptureTaskHypothesis?
    let scaffoldingPacket: CaptureScaffoldingPacket?
    let captureModality: String?
    let evidenceTier: String?
    let captureContextHint: String?
    let sceneMemory: SceneMemoryCaptureMetadata?
    let captureRights: CaptureRightsMetadata?
    let siteIdentity: SiteIdentity?
    let captureTopology: CaptureTopologyMetadata?
    let captureMode: CaptureModeMetadata?
    let semanticAnchors: [CaptureSemanticAnchorEvent]

    init(
        id: UUID,
        targetId: String?,
        reservationId: String?,
        jobId: String,
        captureJobId: String?,
        buyerRequestId: String?,
        siteSubmissionId: String?,
        regionId: String?,
        creatorId: String,
        capturedAt: Date,
        uploadedAt: Date?,
        captureSource: CaptureSource,
        specialTaskType: SpecialTaskType?,
        priorityWeight: Double?,
        quotedPayoutCents: Int?,
        rightsProfile: String?,
        requestedOutputs: [String],
        intakePacket: QualificationIntakePacket?,
        intakeMetadata: CaptureIntakeMetadata?,
        taskHypothesis: CaptureTaskHypothesis?,
        scaffoldingPacket: CaptureScaffoldingPacket?,
        captureModality: String?,
        evidenceTier: String?,
        captureContextHint: String?,
        sceneMemory: SceneMemoryCaptureMetadata?,
        captureRights: CaptureRightsMetadata?,
        siteIdentity: SiteIdentity?,
        captureTopology: CaptureTopologyMetadata?,
        captureMode: CaptureModeMetadata?,
        semanticAnchors: [CaptureSemanticAnchorEvent] = []
    ) {
        self.id = id
        self.targetId = targetId
        self.reservationId = reservationId
        self.jobId = jobId
        self.captureJobId = captureJobId
        self.buyerRequestId = buyerRequestId
        self.siteSubmissionId = siteSubmissionId
        self.regionId = regionId
        self.creatorId = creatorId
        self.capturedAt = capturedAt
        self.uploadedAt = uploadedAt
        self.captureSource = captureSource
        self.specialTaskType = specialTaskType
        self.priorityWeight = priorityWeight
        self.quotedPayoutCents = quotedPayoutCents
        self.rightsProfile = rightsProfile
        self.requestedOutputs = requestedOutputs
        self.intakePacket = intakePacket
        self.intakeMetadata = intakeMetadata
        self.taskHypothesis = taskHypothesis
        self.scaffoldingPacket = scaffoldingPacket
        self.captureModality = captureModality
        self.evidenceTier = evidenceTier
        self.captureContextHint = captureContextHint
        self.sceneMemory = sceneMemory
        self.captureRights = captureRights
        self.siteIdentity = siteIdentity
        self.captureTopology = captureTopology
        self.captureMode = captureMode
        self.semanticAnchors = semanticAnchors
    }
}

struct CaptureUploadRequest: Equatable, Codable {
    let packageURL: URL
    var metadata: CaptureUploadMetadata
}
