import Foundation
import CoreLocation

/// A curated scan opportunity defined by the backend (Firestore: `capture_jobs`).
struct ScanJob: Identifiable, Codable, Equatable {
    enum JobType: String, Codable, Equatable {
        case curatedNearby = "curated_nearby"
        case buyerRequestedSpecialTask = "buyer_requested_special_task"
        case operatorApprovedOnDemand = "operator_approved_on_demand"
    }

    enum MarketplaceState: String, Codable, Equatable {
        case draft
        case approvedForMarketplace = "approved_for_marketplace"
        case claimable
        case reserved
        case inProgress = "in_progress"
        case uploaded
        case underReview = "under_review"
        case approved
        case paid
        case needsRecapture = "needs_recapture"
        case cancelled

        var isDiscoverable: Bool {
            switch self {
            case .approvedForMarketplace, .claimable, .reserved, .inProgress, .needsRecapture:
                return true
            case .draft, .uploaded, .underReview, .approved, .paid, .cancelled:
                return false
            }
        }
    }

    let id: String // Firestore doc id (jobId) and pipeline `scene_id`

    // Required fields
    let title: String
    let address: String
    let lat: Double
    let lng: Double
    let payoutCents: Int
    let estMinutes: Int
    let active: Bool
    let updatedAt: Date

    // Optional fields
    let thumbnailURL: URL?
    let heroImageURL: URL?
    let category: String?
    let instructions: [String]
    let allowedAreas: [String]
    let restrictedAreas: [String]
    let permissionDocURL: URL?
    let checkinRadiusM: Int
    let alertRadiusM: Int
    let priority: Int
    let priorityWeight: Double
    let regionId: String?
    let jobType: JobType
    let marketplaceState: MarketplaceState?
    let buyerRequestId: String?
    let siteSubmissionId: String?
    let quotedPayoutCents: Int?
    let dueWindow: String?
    let approvalRequirements: [String]
    let recaptureReason: String?
    let rightsChecklist: [String]
    let rightsProfile: String?
    let requestedOutputs: [String]
    let workflowName: String?
    let workflowSteps: [String]
    let targetKPI: String?
    let zone: String?
    let shift: String?
    let owner: String?
    let facilityTemplate: String?
    let benchmarkStations: [String]
    let lightingWindows: [String]
    let movableObstacles: [String]
    let floorConditionNotes: [String]
    let reflectiveSurfaceNotes: [String]
    let accessRules: [String]
    let adjacentSystems: [String]
    let privacyRestrictions: [String]
    let securityRestrictions: [String]
    let knownBlockers: [String]
    let nonRoutineModes: [String]
    let peopleTrafficNotes: [String]
    let captureRestrictions: [String]
    let siteType: String?
    let demandScore: Double?
    let opportunityScore: Double?
    let demandSummary: String?
    let rankingExplanation: String?
    let demandSourceKinds: [String]
    let suggestedWorkflows: [String]

    init(
        id: String,
        title: String,
        address: String,
        lat: Double,
        lng: Double,
        payoutCents: Int,
        estMinutes: Int,
        active: Bool,
        updatedAt: Date,
        thumbnailURL: URL?,
        heroImageURL: URL?,
        category: String?,
        instructions: [String],
        allowedAreas: [String],
        restrictedAreas: [String],
        permissionDocURL: URL?,
        checkinRadiusM: Int,
        alertRadiusM: Int,
        priority: Int,
        priorityWeight: Double,
        regionId: String?,
        jobType: JobType,
        marketplaceState: MarketplaceState? = nil,
        buyerRequestId: String?,
        siteSubmissionId: String?,
        quotedPayoutCents: Int?,
        dueWindow: String?,
        approvalRequirements: [String],
        recaptureReason: String?,
        rightsChecklist: [String],
        rightsProfile: String?,
        requestedOutputs: [String],
        workflowName: String?,
        workflowSteps: [String],
        targetKPI: String?,
        zone: String?,
        shift: String?,
        owner: String?,
        facilityTemplate: String?,
        benchmarkStations: [String],
        lightingWindows: [String],
        movableObstacles: [String],
        floorConditionNotes: [String],
        reflectiveSurfaceNotes: [String],
        accessRules: [String],
        adjacentSystems: [String],
        privacyRestrictions: [String],
        securityRestrictions: [String],
        knownBlockers: [String],
        nonRoutineModes: [String],
        peopleTrafficNotes: [String],
        captureRestrictions: [String],
        siteType: String? = nil,
        demandScore: Double? = nil,
        opportunityScore: Double? = nil,
        demandSummary: String? = nil,
        rankingExplanation: String? = nil,
        demandSourceKinds: [String] = [],
        suggestedWorkflows: [String] = []
    ) {
        self.id = id
        self.title = title
        self.address = address
        self.lat = lat
        self.lng = lng
        self.payoutCents = payoutCents
        self.estMinutes = estMinutes
        self.active = active
        self.updatedAt = updatedAt
        self.thumbnailURL = thumbnailURL
        self.heroImageURL = heroImageURL
        self.category = category
        self.instructions = instructions
        self.allowedAreas = allowedAreas
        self.restrictedAreas = restrictedAreas
        self.permissionDocURL = permissionDocURL
        self.checkinRadiusM = checkinRadiusM
        self.alertRadiusM = alertRadiusM
        self.priority = priority
        self.priorityWeight = priorityWeight
        self.regionId = regionId
        self.jobType = jobType
        self.marketplaceState = marketplaceState
        self.buyerRequestId = buyerRequestId
        self.siteSubmissionId = siteSubmissionId
        self.quotedPayoutCents = quotedPayoutCents
        self.dueWindow = dueWindow
        self.approvalRequirements = approvalRequirements
        self.recaptureReason = recaptureReason
        self.rightsChecklist = rightsChecklist
        self.rightsProfile = rightsProfile
        self.requestedOutputs = requestedOutputs
        self.workflowName = workflowName
        self.workflowSteps = workflowSteps
        self.targetKPI = targetKPI
        self.zone = zone
        self.shift = shift
        self.owner = owner
        self.facilityTemplate = facilityTemplate
        self.benchmarkStations = benchmarkStations
        self.lightingWindows = lightingWindows
        self.movableObstacles = movableObstacles
        self.floorConditionNotes = floorConditionNotes
        self.reflectiveSurfaceNotes = reflectiveSurfaceNotes
        self.accessRules = accessRules
        self.adjacentSystems = adjacentSystems
        self.privacyRestrictions = privacyRestrictions
        self.securityRestrictions = securityRestrictions
        self.knownBlockers = knownBlockers
        self.nonRoutineModes = nonRoutineModes
        self.peopleTrafficNotes = peopleTrafficNotes
        self.captureRestrictions = captureRestrictions
        self.siteType = siteType
        self.demandScore = demandScore
        self.opportunityScore = opportunityScore
        self.demandSummary = demandSummary
        self.rankingExplanation = rankingExplanation
        self.demandSourceKinds = demandSourceKinds
        self.suggestedWorkflows = suggestedWorkflows
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    var payoutDollars: Int {
        max(0, payoutCents / 100)
    }

    var isDiscoverableInMarketplace: Bool {
        marketplaceState?.isDiscoverable ?? true
    }

    var primaryImageURL: URL? {
        heroImageURL ?? thumbnailURL
    }

    func distanceMeters(from userLocation: CLLocation) -> Double {
        userLocation.distance(from: CLLocation(latitude: lat, longitude: lng))
    }

    var workflowStepsOrInstructions: [String] {
        if !workflowSteps.isEmpty {
            return workflowSteps
        }
        return instructions
    }

    var captureSpecialTaskType: CaptureUploadMetadata.SpecialTaskType {
        switch jobType {
        case .curatedNearby:
            return .curatedNearby
        case .buyerRequestedSpecialTask:
            return .buyerRequested
        case .operatorApprovedOnDemand:
            return .operatorApproved
        }
    }

    var inaccessibleAreasForCapture: [String] {
        if !captureRestrictions.isEmpty {
            return captureRestrictions
        }
        return restrictedAreas
    }

    var captureConsentStatus: CaptureConsentStatus {
        if permissionDocURL != nil {
            return .documented
        }
        if !allowedAreas.isEmpty || !restrictedAreas.isEmpty {
            return .policyOnly
        }
        return .unknown
    }

    var qualificationIntakePacket: QualificationIntakePacket {
        var privacySecurityLimits = privacyRestrictions
        for item in securityRestrictions where !privacySecurityLimits.contains(item) {
            privacySecurityLimits.append(item)
        }
        return QualificationIntakePacket(
            workflowName: workflowName ?? title,
            taskSteps: workflowStepsOrInstructions,
            targetKPI: targetKPI,
            zone: zone ?? allowedAreas.first,
            shift: shift,
            owner: owner,
            facilityTemplate: facilityTemplate ?? category,
            requiredCoverageAreas: [
                "Ingress and egress route",
                "Primary task zone",
                "Benchmark station or handoff point",
                "Restricted or failure-prone boundary",
                "Floor transition or dock turn"
            ],
            benchmarkStations: benchmarkStations,
            adjacentSystems: adjacentSystems,
            privacySecurityLimits: privacySecurityLimits,
            knownBlockers: knownBlockers,
            nonRoutineModes: nonRoutineModes,
            peopleTrafficNotes: peopleTrafficNotes,
            captureRestrictions: captureRestrictions.isEmpty ? restrictedAreas : captureRestrictions,
            lightingWindows: lightingWindows,
            shiftTrafficWindows: peopleTrafficNotes,
            movableObstacles: movableObstacles,
            floorConditionNotes: floorConditionNotes,
            reflectiveSurfaceNotes: reflectiveSurfaceNotes,
            accessRules: accessRules
        )
    }

    var defaultScaffoldingPacket: CaptureScaffoldingPacket {
        let capturePlan = [
            "Start with entry and egress routes.",
            "Pause at each workcell boundary for 2-3 seconds.",
            "Capture every benchmark station, dock turn, and narrow threshold.",
            "Record restricted-zone boundaries and handoff points from both approach directions.",
            "Capture at least one still photo for any critical handoff or scale reference."
        ]
        let priors: [String: Double] = [
            "occlusion_risk": restrictedAreas.isEmpty ? 0.25 : 0.45,
            "traffic_variability": peopleTrafficNotes.isEmpty ? 0.2 : 0.5
        ]
        return CaptureScaffoldingPacket(
            scaffoldingUsed: [],
            coveragePlan: capturePlan,
            calibrationAssets: [],
            scaleAnchorAssets: [],
            checkpointAssets: [],
            uncertaintyPriors: priors
        )
    }
}
