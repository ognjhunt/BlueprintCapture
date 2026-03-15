import Foundation
import CoreLocation

/// A curated scan opportunity defined by the backend (Firestore: `capture_jobs`).
struct ScanJob: Identifiable, Equatable {
    enum JobType: String, Equatable {
        case curatedNearby = "curated_nearby"
        case buyerRequestedSpecialTask = "buyer_requested_special_task"
        case operatorApprovedOnDemand = "operator_approved_on_demand"
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

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    var payoutDollars: Int {
        max(0, payoutCents / 100)
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
