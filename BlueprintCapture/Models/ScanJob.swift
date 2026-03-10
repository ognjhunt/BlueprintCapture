import Foundation
import CoreLocation

/// A curated scan opportunity defined by the backend (Firestore: `capture_jobs`).
struct ScanJob: Identifiable, Equatable {
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
    let workflowName: String?
    let workflowSteps: [String]
    let targetKPI: String?
    let zone: String?
    let shift: String?
    let owner: String?
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
            adjacentSystems: adjacentSystems,
            privacySecurityLimits: privacySecurityLimits,
            knownBlockers: knownBlockers,
            nonRoutineModes: nonRoutineModes,
            peopleTrafficNotes: peopleTrafficNotes,
            captureRestrictions: captureRestrictions.isEmpty ? restrictedAreas : captureRestrictions
        )
    }

    var defaultScaffoldingPacket: CaptureScaffoldingPacket {
        let capturePlan = [
            "Start with entry and egress routes.",
            "Pause at each workcell boundary for 2-3 seconds.",
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
