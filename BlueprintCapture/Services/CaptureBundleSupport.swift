import Foundation
import AVFoundation
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(ZIPFoundation)
import ZIPFoundation
#endif

enum CaptureIntakeSource: String, Codable {
    case authoritative
    case humanManual = "human_manual"
    case aiInferred = "ai_inferred"
}

enum CaptureTaskHypothesisStatus: String, Codable {
    case accepted
    case needsConfirmation = "needs_confirmation"
    case rejected
}

struct CaptureIntakeMetadata: Equatable, Codable {
    let source: CaptureIntakeSource
    let model: String?
    let fps: Int?
    let confidence: Double?
    let warnings: [String]

    init(
        source: CaptureIntakeSource,
        model: String? = nil,
        fps: Int? = nil,
        confidence: Double? = nil,
        warnings: [String] = []
    ) {
        self.source = source
        self.model = model
        self.fps = fps
        self.confidence = confidence
        self.warnings = warnings
    }
}

struct CaptureTaskHypothesis: Equatable, Codable {
    let schemaVersion: String
    let workflowName: String?
    let taskSteps: [String]
    let targetKPI: String?
    let zone: String?
    let owner: String?
    let confidence: Double?
    let source: CaptureIntakeSource
    let model: String?
    let fps: Int?
    let warnings: [String]
    let status: CaptureTaskHypothesisStatus

    init(
        schemaVersion: String = "v1",
        workflowName: String? = nil,
        taskSteps: [String] = [],
        targetKPI: String? = nil,
        zone: String? = nil,
        owner: String? = nil,
        confidence: Double? = nil,
        source: CaptureIntakeSource = .aiInferred,
        model: String? = nil,
        fps: Int? = nil,
        warnings: [String] = [],
        status: CaptureTaskHypothesisStatus = .accepted
    ) {
        self.schemaVersion = schemaVersion
        self.workflowName = workflowName
        self.taskSteps = taskSteps
        self.targetKPI = targetKPI
        self.zone = zone
        self.owner = owner
        self.confidence = confidence
        self.source = source
        self.model = model
        self.fps = fps
        self.warnings = warnings
        self.status = status
    }

    init(packet: QualificationIntakePacket, metadata: CaptureIntakeMetadata, status: CaptureTaskHypothesisStatus) {
        self.init(
            workflowName: packet.workflowName,
            taskSteps: packet.taskSteps,
            targetKPI: packet.targetKPI,
            zone: packet.zone,
            owner: packet.owner,
            confidence: metadata.confidence,
            source: metadata.source,
            model: metadata.model,
            fps: metadata.fps,
            warnings: metadata.warnings,
            status: status
        )
    }

    func with(status: CaptureTaskHypothesisStatus) -> CaptureTaskHypothesis {
        CaptureTaskHypothesis(
            schemaVersion: schemaVersion,
            workflowName: workflowName,
            taskSteps: taskSteps,
            targetKPI: targetKPI,
            zone: zone,
            owner: owner,
            confidence: confidence,
            source: source,
            model: model,
            fps: fps,
            warnings: warnings,
            status: status
        )
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case workflowName = "workflow_name"
        case taskSteps = "task_steps"
        case targetKPI = "target_kpi"
        case zone
        case owner
        case confidence
        case source
        case model
        case fps
        case warnings
        case status
    }
}

struct FinalizedCaptureBundle: Equatable {
    let sceneId: String
    let captureId: String
    let rawDirectoryURL: URL
    let captureRootURL: URL
    let shareURL: URL?
}

enum CaptureBundleFinalizationMode: Equatable {
    case upload(remoteRawPrefix: String, videoURI: String)
    case localExport(localRawPrefix: String = "raw", videoURI: String = "raw/walkthrough.mov")

    var rawPrefix: String {
        switch self {
        case .upload(let rawPrefix, _):
            return rawPrefix
        case .localExport(let rawPrefix, _):
            return rawPrefix
        }
    }

    var videoURI: String {
        switch self {
        case .upload(_, let videoURI):
            return videoURI
        case .localExport(_, let videoURI):
            return videoURI
        }
    }
}

struct CaptureManualIntakeDraft: Equatable, Identifiable {
    let id: UUID
    var workflowName: String
    var taskStepsText: String
    var zone: String
    var owner: String
    var helperText: String
    var reviewTitle: String

    init(
        id: UUID = UUID(),
        workflowName: String = "",
        taskStepsText: String = "",
        zone: String = "",
        owner: String = "",
        helperText: String = "Add a workflow name, at least one task step, and either a zone or owner.",
        reviewTitle: String = "Complete Intake"
    ) {
        self.id = id
        self.workflowName = workflowName
        self.taskStepsText = taskStepsText
        self.zone = zone
        self.owner = owner
        self.helperText = helperText
        self.reviewTitle = reviewTitle
    }

    init(packet: QualificationIntakePacket?, helperText: String) {
        self.init(
            workflowName: packet?.workflowName ?? "",
            taskStepsText: (packet?.taskSteps ?? []).joined(separator: "\n"),
            zone: packet?.zone ?? "",
            owner: packet?.owner ?? "",
            helperText: helperText,
            reviewTitle: "Complete Intake"
        )
    }

    var taskSteps: [String] {
        taskStepsText
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func makePacket() -> QualificationIntakePacket {
        QualificationIntakePacket(
            workflowName: workflowName.trimmingCharacters(in: .whitespacesAndNewlines),
            taskSteps: taskSteps,
            zone: zone.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            owner: owner.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
    }
}

enum IntakeResolutionOutcome {
    case resolved(CaptureUploadRequest)
    case needsManualEntry(request: CaptureUploadRequest, draft: CaptureManualIntakeDraft)
}

struct CaptureEvidenceSummary: Equatable, Codable {
    let arkitFrameRows: Int
    let arkitPoseRows: Int
    let arkitIntrinsicsValid: Bool
    let arkitDepthFrames: Int
    let arkitConfidenceFrames: Int
    let arkitMeshFiles: Int
    let arkitFeaturePointRows: Int
    let arkitPlaneRows: Int
    let arkitTrackingStateRows: Int
    let arkitRelocalizationEventRows: Int
    let arkitLightEstimateRows: Int
    let arcoreFrameRows: Int
    let arcorePoseRows: Int
    let arcoreIntrinsicsValid: Bool
    let arcoreDepthFrames: Int
    let arcoreConfidenceFrames: Int
    let arcorePointCloudSamples: Int
    let arcorePlaneRows: Int
    let arcoreTrackingStateRows: Int
    let arcoreLightEstimateRows: Int
    let glassesFrameTimestampRows: Int
    let glassesDeviceStateRows: Int
    let glassesHealthEventRows: Int
    let companionPhonePoseRows: Int
    let companionPhoneIntrinsicsValid: Bool
    let companionPhoneCalibrationPresent: Bool
    let poseMatchRate: Double?
    let p95PoseDeltaSec: Double?
    let motionSamples: Int
    let motionProvenance: String?
    let motionTimestampsCaptureRelative: Bool

    var sensorAvailability: [String: Bool] {
        [
            "arkit_poses": arkitPoseRows > 0,
            "arkit_intrinsics": arkitIntrinsicsValid,
            "arkit_depth": arkitDepthFrames > 0,
            "arkit_confidence": arkitConfidenceFrames > 0,
            "arkit_meshes": arkitMeshFiles > 0,
            "motion": motionSamples > 0,
        ]
    }

    var captureCapabilities: CaptureCapabilitiesMetadata {
        let phoneMotionAuthoritative = motionProvenance == "iphone_device_imu"
        let glassesDiagnosticMotion = motionProvenance == "phone_imu_diagnostic_only"
        let hasARKitPose = arkitPoseRows > 0
        let hasARCorePose = arcorePoseRows > 0
        let hasARKitIntrinsics = arkitIntrinsicsValid
        let hasARCoreIntrinsics = arcoreIntrinsicsValid
        let hasPose = hasARKitPose || hasARCorePose
        let hasIntrinsics = hasARKitIntrinsics || hasARCoreIntrinsics
        let hasDepth = arkitDepthFrames > 0 || arcoreDepthFrames > 0
        let hasDepthConfidence = arkitConfidenceFrames > 0 || arcoreConfidenceFrames > 0
        let hasPointCloud = arcorePointCloudSamples > 0 || arkitFeaturePointRows > 0
        let hasPlanes = arkitPlaneRows > 0 || arcorePlaneRows > 0
        let hasLightEstimate = arkitLightEstimateRows > 0 || arcoreLightEstimateRows > 0
        let hasTrackingState = arkitTrackingStateRows > 0 || arcoreTrackingStateRows > 0
        let hasRelocalization = arkitRelocalizationEventRows > 0
        let poseAuthority: CaptureAuthorityLevel = hasARKitPose
            ? .authoritativeRaw
            : hasARCorePose
            ? .rawTrackingOnly
            : .notAvailable
        let intrinsicsAuthority: CaptureAuthorityLevel = hasARKitIntrinsics
            ? .authoritativeRaw
            : hasARCoreIntrinsics
            ? .rawTrackingOnly
            : .notAvailable
        let depthAuthority: CaptureAuthorityLevel = arkitDepthFrames > 0
            ? .authoritativeRaw
            : arcoreDepthFrames > 0
            ? .rawTrackingOnly
            : .notAvailable
        let motionAuthority: CaptureAuthorityLevel = phoneMotionAuthoritative
            ? .authoritativeRaw
            : glassesDiagnosticMotion
            ? .diagnosticOnly
            : motionSamples > 0
            ? .rawTrackingOnly
            : .notAvailable
        return CaptureCapabilitiesMetadata(
            cameraPose: hasPose,
            cameraIntrinsics: hasIntrinsics,
            depth: hasDepth,
            depthConfidence: hasDepthConfidence,
            mesh: arkitMeshFiles > 0,
            pointCloud: hasPointCloud,
            planes: hasPlanes,
            featurePoints: arkitFeaturePointRows > 0,
            trackingState: hasTrackingState,
            relocalizationEvents: hasRelocalization,
            lightEstimate: hasLightEstimate,
            motion: motionSamples > 0,
            motionAuthoritative: motionAuthority == .authoritativeRaw,
            companionPhonePose: companionPhonePoseRows > 0,
            companionPhoneIntrinsics: companionPhoneIntrinsicsValid,
            companionPhoneCalibration: companionPhoneCalibrationPresent,
            poseRows: max(arkitPoseRows, arcorePoseRows),
            intrinsicsValid: hasIntrinsics,
            depthFrames: max(arkitDepthFrames, arcoreDepthFrames),
            confidenceFrames: max(arkitConfidenceFrames, arcoreConfidenceFrames),
            meshFiles: arkitMeshFiles,
            pointCloudSamples: max(arcorePointCloudSamples, arkitFeaturePointRows),
            planeRows: max(arkitPlaneRows, arcorePlaneRows),
            featurePointRows: arkitFeaturePointRows,
            trackingStateRows: max(arkitTrackingStateRows, arcoreTrackingStateRows),
            relocalizationEventRows: arkitRelocalizationEventRows,
            lightEstimateRows: max(arkitLightEstimateRows, arcoreLightEstimateRows),
            motionSamples: motionSamples,
            poseAuthority: poseAuthority,
            intrinsicsAuthority: intrinsicsAuthority,
            depthAuthority: depthAuthority,
            motionAuthority: motionAuthority,
            motionProvenance: motionProvenance,
            geometrySource: hasARKitPose ? "arkit" : hasARCorePose ? "arcore" : nil,
            geometryExpectedDownstream: !hasDepth && (hasPose || companionPhonePoseRows > 0 || glassesFrameTimestampRows > 0)
        )
    }

    var hasUsableARKitBundle: Bool {
        arkitPoseRows > 0 && arkitIntrinsicsValid
    }

    var hasUsableARCoreBundle: Bool {
        arcorePoseRows > 0 && arcoreIntrinsicsValid
    }

    var poseAlignmentOK: Bool {
        guard let poseMatchRate,
              let p95PoseDeltaSec else {
            return false
        }
        return poseMatchRate >= 0.65 && p95PoseDeltaSec <= 0.2
    }

    var hasLiDAREvidence: Bool {
        arkitDepthFrames > 0 || arkitConfidenceFrames > 0
    }

    var derivedScaffoldingUsed: [String] {
        var scaffolding: [String] = []
        if arkitPoseRows > 0 {
            scaffolding.append("arkit_pose_log")
        }
        if arkitDepthFrames > 0 {
            scaffolding.append("arkit_depth")
        }
        if arkitMeshFiles > 0 {
            scaffolding.append("arkit_meshes")
        }
        if arcorePoseRows > 0 {
            scaffolding.append("arcore_pose_log")
        }
        if arcoreDepthFrames > 0 {
            scaffolding.append("arcore_depth")
        }
        if companionPhonePoseRows > 0 {
            scaffolding.append("companion_phone_pose")
        }
        return scaffolding
    }
}

enum CaptureBundleContext {
    static func sceneIdentifier(for request: CaptureUploadRequest) -> String {
        if let trimmed = request.metadata.targetId?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
            return trimmed
        }
        if let reservation = request.metadata.reservationId?.trimmingCharacters(in: .whitespacesAndNewlines), !reservation.isEmpty {
            return reservation
        }
        return request.metadata.jobId
    }

    static func captureIdentifier(for request: CaptureUploadRequest) -> String {
        let trimmed = request.metadata.id.uuidString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return UUID().uuidString
    }

    static func sceneBasePath(for request: CaptureUploadRequest) -> String {
        "scenes/\(sceneIdentifier(for: request))/captures/\(captureIdentifier(for: request))/"
    }

    static func rawBasePath(for request: CaptureUploadRequest) -> String {
        sceneBasePath(for: request) + "raw/"
    }

    static func captureModality(for request: CaptureUploadRequest, evidence: CaptureEvidenceSummary) -> String {
        if request.metadata.captureSource == .iphoneVideo {
            return evidence.hasUsableARKitBundle ? "iphone_arkit_lidar" : "iphone_video_only"
        }
        if evidence.companionPhonePoseRows > 0 || !(request.metadata.scaffoldingPacket?.scaffoldingUsed ?? []).isEmpty {
            return "glasses_plus_scaffolding"
        }
        return "glasses_video_only"
    }

    static func captureProfileId(for request: CaptureUploadRequest, evidence: CaptureEvidenceSummary) -> String {
        if request.metadata.captureSource == .iphoneVideo {
            return evidence.hasLiDAREvidence ? "iphone_arkit_lidar" : "iphone_arkit_non_lidar"
        }
        if evidence.companionPhonePoseRows > 0 || evidence.companionPhoneIntrinsicsValid {
            return "glasses_pov_companion_phone"
        }
        return "glasses_pov"
    }

    static func evidenceTier(for request: CaptureUploadRequest, evidence: CaptureEvidenceSummary) -> String {
        let intakeComplete = request.metadata.intakePacket?.isComplete == true
        if request.metadata.captureSource == .iphoneVideo && intakeComplete && evidence.hasUsableARKitBundle && evidence.hasLiDAREvidence {
            return "qualified_metric_capture"
        }
        if request.metadata.captureSource == .metaGlasses,
           request.metadata.scaffoldingPacket?.hasValidatedMetricBundle == true,
           intakeComplete {
            return "video_with_validated_scaffolding"
        }
        return "pre_screen_video"
    }

    /// Deterministic world-model candidacy computed from actual evidence, not from a nullable
    /// operator-entered continuity score. This is the canonical rule used by iOS finalization.
    /// The cloud bridge enforces the same rule using actual artifact presence from GCS.
    static func worldModelCandidate(
        for request: CaptureUploadRequest,
        evidence: CaptureEvidenceSummary
    ) -> Bool {
        let captureMode = request.metadata.captureMode
        return captureMode?.resolvedMode == "site_world_candidate"
            && evidence.arkitPoseRows > 0
            && evidence.arkitIntrinsicsValid
            && evidence.arkitDepthFrames > 0
            && evidence.poseAlignmentOK
            && (request.metadata.intakePacket?.isComplete == true)
            && (request.metadata.captureRights?.derivedSceneGenerationAllowed == true)
    }

    /// Returns a list of gate results for world_model_candidate, useful for debugging and
    /// downstream reasoning fields.
    static func worldModelCandidateReasoning(
        for request: CaptureUploadRequest,
        evidence: CaptureEvidenceSummary
    ) -> [String] {
        let captureMode = request.metadata.captureMode
        let capabilities = evidence.captureCapabilities
        var gates: [String] = []
        gates.append("capture_mode_site_world_candidate:\(captureMode?.resolvedMode == "site_world_candidate")")
        gates.append("arkit_poses_valid:\(evidence.arkitPoseRows > 0)")
        gates.append("arkit_intrinsics_valid:\(evidence.arkitIntrinsicsValid)")
        gates.append("depth_coverage_ok:\(evidence.arkitDepthFrames > 0)")
        gates.append("pose_alignment_ok:\(evidence.poseAlignmentOK)")
        gates.append("pose_authority:\(capabilities.poseAuthority.rawValue)")
        gates.append("intrinsics_authority:\(capabilities.intrinsicsAuthority.rawValue)")
        gates.append("depth_authority:\(capabilities.depthAuthority.rawValue)")
        gates.append("geometry_source:\(capabilities.geometrySource ?? "none")")
        gates.append("geometry_expected_downstream:\(capabilities.geometryExpectedDownstream)")
        if let poseMatchRate = evidence.poseMatchRate {
            gates.append("pose_match_rate:\(String(format: "%.4f", poseMatchRate))")
        } else {
            gates.append("pose_match_rate:missing")
        }
        if let p95PoseDeltaSec = evidence.p95PoseDeltaSec {
            gates.append("p95_pose_delta_sec:\(String(format: "%.4f", p95PoseDeltaSec))")
        } else {
            gates.append("p95_pose_delta_sec:missing")
        }
        gates.append("intake_complete:\(request.metadata.intakePacket?.isComplete == true)")
        gates.append("derived_scene_generation_allowed:\(request.metadata.captureRights?.derivedSceneGenerationAllowed == true)")
        return gates
    }

    static func rawDirectoryURL(for request: CaptureUploadRequest) -> URL {
        request.packageURL
    }
}

protocol CaptureBundleFinalizerProtocol {
    func finalize(request: CaptureUploadRequest, mode: CaptureBundleFinalizationMode) throws -> FinalizedCaptureBundle
}

final class CaptureBundleFinalizer: CaptureBundleFinalizerProtocol {
    enum FinalizationError: LocalizedError, Equatable {
        case missingStructuredIntake
        case packageMissing

        var errorDescription: String? {
            switch self {
            case .missingStructuredIntake:
                return "Structured intake is required before finalization."
            case .packageMissing:
                return "The recorded capture directory could not be found."
            }
        }
    }

    private struct CaptureContextFile: Codable {
        let schemaVersion: String
        let sceneId: String
        let captureId: String
        let siteSubmissionId: String
        let buyerRequestId: String?
        let captureJobId: String?
        let regionId: String?
        let captureSource: String
        let specialTaskType: String?
        let priorityWeight: Double?
        let quotedPayoutCents: Int?
        let rightsProfile: String?
        let requestedOutputs: [String]
        let captureModality: String
        let captureProfileId: String
        let evidenceTier: String
        let scaffoldingUsed: [String]
        let coveragePlan: [String]
        let calibrationAssets: [String]
        let scaleAnchorAssets: [String]
        let checkpointAssets: [String]
        let validatedScaleMeters: Double?
        let validatedPoseCoverage: Double?
        let hiddenZoneBound: Double?
        let validatedMetricBundle: Bool
        let uncertaintyPriors: [String: Double]
        let intakePresent: Bool
        let intakeSource: String?
        let intakeInferenceModel: String?
        let intakeInferenceFPS: Int?
        let intakeInferenceConfidence: Double?
        let intakeWarnings: [String]
        let taskHypothesisStatus: String?
        let taskTextHint: String?
        let taskSteps: [String]
        let facilityTemplate: String?
        let requiredCoverageAreas: [String]
        let benchmarkStations: [String]
        let lightingWindows: [String]
        let shiftTrafficWindows: [String]
        let movableObstacles: [String]
        let floorConditionNotes: [String]
        let reflectiveSurfaceNotes: [String]
        let accessRules: [String]
        let sceneMemory: SceneMemoryCaptureMetadata
        let captureRights: CaptureRightsMetadata
        let captureEvidence: CaptureEvidenceSummary
        let captureCapabilities: CaptureCapabilitiesMetadata
        let worldModelCandidate: Bool
        let worldModelCandidateReasoning: [String]
        let siteIdentity: SiteIdentity?
        let captureTopology: CaptureTopologyMetadata?
        let captureMode: CaptureModeMetadata?
        let semanticAnchors: [CaptureSemanticAnchorEvent]
        let capturedAt: String
    }

    private struct UploadCompletionFile: Codable {
        let schemaVersion: String
        let sceneId: String
        let captureId: String
        let rawPrefix: String
        let completedAt: String
    }

    // Route anchor definitions — fixed v1 schema (entry anchor only for now).
    private struct RouteAnchorsFile: Codable {
        struct RouteAnchor: Codable {
            let anchorId: String
            let anchorType: String
            let label: String
            let expectedObservation: String
            let requiredInPrimaryPass: Bool
            let requiredInRevisitPass: Bool
        }
        let schemaVersion: String
        let routeAnchors: [RouteAnchor]
    }

    // Checkpoint events — one event per detected anchor hold in this pass.
    private struct CheckpointEventsFile: Codable {
        struct CheckpointEvent: Codable {
            let anchorId: String
            let passId: String
            let tCaptureSec: Double
            let holdDurationSec: Double
            let completed: Bool
        }
        let schemaVersion: String
        let checkpointEvents: [CheckpointEvent]
    }

    private struct RelocalizationEventsFile: Codable {
        struct RelocalizationEvent: Codable {
            let startFrameId: String?
            let endFrameId: String?
            let startTCaptureSec: Double?
            let endTCaptureSec: Double?
            let frameCount: Int
        }
        let schemaVersion: String
        let relocalizationEvents: [RelocalizationEvent]
    }

    private struct RecordingSessionFile: Codable {
        let schemaVersion: String
        let sceneId: String
        let captureId: String
        let siteVisitId: String?
        let routeId: String?
        let passId: String?
        let passIndex: Int?
        let passRole: String?
        let coordinateFrameSessionId: String?
        let arkitSessionId: String?
        let worldFrameDefinition: String
        let units: String
        let handedness: String
        let gravityAligned: Bool
        let sessionResetCount: Int
        let capturedAt: String
    }

    private struct RecordingWorldFrame {
        let worldFrameDefinition: String
        let units: String
        let handedness: String
        let gravityAligned: Bool
        let sessionResetCount: Int
    }

    private struct OverlapGraphFile: Codable {
        let schemaVersion: String
        let siteVisitId: String?
        let routeId: String?
        let passId: String?
        let passRole: String?
        let coordinateFrameSessionId: String?
        let observedAnchorIds: [String]
        let semanticAnchorIds: [String]
        let relocalizationEventCount: Int
    }

    private let completionMarkerFilename = "capture_upload_complete.json"
    private let taskHypothesisFilename = "task_hypothesis.json"
    private let captureModeFilename = "capture_mode.json"
    private let fileManager = FileManager.default

    func finalize(request: CaptureUploadRequest, mode: CaptureBundleFinalizationMode) throws -> FinalizedCaptureBundle {
        // Alpha: intake gate removed — finalize regardless of intake completeness
        let directory = CaptureBundleContext.rawDirectoryURL(for: request)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw FinalizationError.packageMissing
        }

        try patchManifest(in: directory, request: request, mode: mode)
        try materializeSupplementalFiles(in: directory, request: request, mode: mode)

        let sceneId = CaptureBundleContext.sceneIdentifier(for: request)
        let captureId = CaptureBundleContext.captureIdentifier(for: request)
        return FinalizedCaptureBundle(
            sceneId: sceneId,
            captureId: captureId,
            rawDirectoryURL: directory,
            captureRootURL: directory.deletingLastPathComponent(),
            shareURL: nil
        )
    }

    private func normalizedSceneMemory(for request: CaptureUploadRequest, directory: URL) -> SceneMemoryCaptureMetadata {
        let metadata = request.metadata.sceneMemory
        return SceneMemoryCaptureMetadata(
            continuityScore: metadata?.continuityScore,
            lightingConsistency: normalizedSceneValue(metadata?.lightingConsistency),
            dynamicObjectDensity: normalizedSceneValue(metadata?.dynamicObjectDensity),
            operatorNotes: metadata?.operatorNotes ?? [],
            inaccessibleAreas: metadata?.inaccessibleAreas ?? [],
            semanticAnchorsObserved: metadata?.semanticAnchorsObserved ?? [],
            relocalizationCount: metadata?.relocalizationCount,
            overlapCheckpointCount: metadata?.overlapCheckpointCount
        )
    }

    private func normalizedCaptureRights(for request: CaptureUploadRequest) -> CaptureRightsMetadata {
        let metadata = request.metadata.captureRights
        return CaptureRightsMetadata(
            derivedSceneGenerationAllowed: metadata?.derivedSceneGenerationAllowed ?? false,
            dataLicensingAllowed: metadata?.dataLicensingAllowed ?? false,
            payoutEligible: metadata?.payoutEligible ?? false,
            consentStatus: metadata?.consentStatus ?? .unknown,
            permissionDocumentURI: metadata?.permissionDocumentURI,
            consentScope: metadata?.consentScope ?? [],
            consentNotes: metadata?.consentNotes ?? []
        )
    }

    private func normalizedSceneValue(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false ? trimmed : nil) ?? "unknown"
    }

    private func countJSONLines(in url: URL, requireJSONObject: Bool = true) -> Int {
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else {
            return 0
        }
        return content.split(whereSeparator: \.isNewline).reduce(into: 0) { count, line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            if !requireJSONObject {
                count += 1
                return
            }
            guard let lineData = trimmed.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData),
                  object is [String: Any] else {
                return
            }
            count += 1
        }
    }

    private func readJSONObjectLines(from url: URL) -> [[String: Any]] {
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else {
            return []
        }
        return content.split(whereSeparator: \.isNewline).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let lineData = trimmed.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                return nil
            }
            return object
        }
    }

    private func frameIdentifier(from object: [String: Any]) -> String? {
        if let frameId = object["frame_id"] as? String, !frameId.isEmpty {
            return frameId
        }
        if let frameIndex = object["frame_index"] as? Int {
            return String(format: "%06d", max(0, frameIndex) + 1)
        }
        if let frameIndex = object["frameIndex"] as? Int {
            return String(format: "%06d", max(0, frameIndex) + 1)
        }
        return nil
    }

    private func timeValue(from object: [String: Any]) -> Double? {
        for key in ["t_device_sec", "tCaptureSec", "timestamp"] {
            if let value = object[key] as? Double {
                return value
            }
            if let value = object[key] as? NSNumber {
                return value.doubleValue
            }
        }
        return nil
    }

    private func percentile(_ values: [Double], percentile: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        if percentile <= 0 { return values.min() }
        if percentile >= 100 { return values.max() }
        let ordered = values.sorted()
        let rank = (percentile / 100.0) * Double(ordered.count - 1)
        let low = Int(floor(rank))
        let high = min(ordered.count - 1, low + 1)
        guard low != high else { return ordered[low] }
        let weight = rank - Double(low)
        return ordered[low] * (1.0 - weight) + ordered[high] * weight
    }

    private func nearestPoseTime(to frameTime: Double, poseTimes: [Double]) -> Double? {
        guard !poseTimes.isEmpty else { return nil }
        if poseTimes.count == 1 { return poseTimes[0] }
        var low = 0
        var high = poseTimes.count - 1
        while low < high {
            let mid = (low + high) / 2
            if poseTimes[mid] < frameTime {
                low = mid + 1
            } else {
                high = mid
            }
        }
        var best = poseTimes[low]
        if low > 0 {
            let previous = poseTimes[low - 1]
            if abs(previous - frameTime) <= abs(best - frameTime) {
                best = previous
            }
        }
        return best
    }

    private func inspectPoseAlignment(
        framesURL: URL,
        posesURL: URL
    ) -> (poseMatchRate: Double?, p95PoseDeltaSec: Double?) {
        let frameRows = readJSONObjectLines(from: framesURL)
        let poseRows = readJSONObjectLines(from: posesURL)
        guard !frameRows.isEmpty, !poseRows.isEmpty else {
            return (nil, nil)
        }

        var posesByFrameId: [String: Double] = [:]
        var poseTimes: [Double] = []
        for row in poseRows {
            guard let poseTime = timeValue(from: row) else { continue }
            poseTimes.append(poseTime)
            if let frameId = frameIdentifier(from: row) {
                posesByFrameId[frameId] = poseTime
            }
        }
        poseTimes.sort()

        var matched = 0
        var deltas: [Double] = []
        for row in frameRows {
            let frameTime = timeValue(from: row)
            let frameId = frameIdentifier(from: row)
            var matchedPoseTime: Double?
            if let frameId, let poseTime = posesByFrameId[frameId] {
                matchedPoseTime = poseTime
            } else if let frameTime {
                matchedPoseTime = nearestPoseTime(to: frameTime, poseTimes: poseTimes)
            }
            guard let matchedPoseTime else { continue }
            matched += 1
            if let frameTime {
                deltas.append(abs(frameTime - matchedPoseTime))
            }
        }

        let poseMatchRate = frameRows.isEmpty ? nil : Double(matched) / Double(frameRows.count)
        return (poseMatchRate, percentile(deltas, percentile: 95.0))
    }

    private func isValidIntrinsicsFile(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        let requiredPositiveFields = ["fx", "fy"]
        for key in requiredPositiveFields {
            guard let value = object[key] as? Double, value > 0 else {
                return false
            }
        }
        let requiredFiniteFields = ["cx", "cy"]
        for key in requiredFiniteFields {
            guard let value = object[key] as? Double, value.isFinite else {
                return false
            }
        }
        guard let width = object["width"] as? Int, width > 0,
              let height = object["height"] as? Int, height > 0 else {
            return false
        }
        return true
    }

    private func countFiles(in directory: URL, extensions: Set<String>) -> Int {
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles]) else {
            return 0
        }

        var count = 0
        for case let fileURL as URL in enumerator {
            let ext = fileURL.pathExtension.lowercased()
            guard extensions.contains(ext) else { continue }
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true, (values?.fileSize ?? 0) > 0 else { continue }
            count += 1
        }
        return count
    }

    private func inspectMotionMetadata(at url: URL, captureSource: CaptureUploadMetadata.CaptureSource) -> (samples: Int, provenance: String?, captureRelative: Bool) {
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else {
            return (0, nil, false)
        }

        var samples = 0
        var provenance: String?
        var captureRelative = false

        for line in content.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let lineData = trimmed.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }
            samples += 1
            if provenance == nil {
                provenance = object["motion_provenance"] as? String
            }
            if !captureRelative, object["t_capture_sec"] is Double {
                captureRelative = true
            }
        }

        if samples > 0, provenance == nil {
            provenance = captureSource == .metaGlasses ? "phone_imu_diagnostic_only" : "iphone_device_imu"
        }

        return (samples, provenance, captureRelative)
    }

    private func inspectEvidence(in directory: URL, request: CaptureUploadRequest) -> CaptureEvidenceSummary {
        let arkitDirectory = directory.appendingPathComponent("arkit", isDirectory: true)
        let arcoreDirectory = directory.appendingPathComponent("arcore", isDirectory: true)
        let glassesDirectory = directory.appendingPathComponent("glasses", isDirectory: true)
        let companionPhoneDirectory = directory.appendingPathComponent("companion_phone", isDirectory: true)
        let posesURL = arkitDirectory.appendingPathComponent("poses.jsonl")
        let framesURL = arkitDirectory.appendingPathComponent("frames.jsonl")
        let intrinsicsURL = arkitDirectory.appendingPathComponent("intrinsics.json")
        let motionURL = directory.appendingPathComponent("motion.jsonl")
        let arcorePosesURL = arcoreDirectory.appendingPathComponent("poses.jsonl")
        let arcoreFramesURL = arcoreDirectory.appendingPathComponent("frames.jsonl")
        let arcoreIntrinsicsURL = arcoreDirectory.appendingPathComponent("session_intrinsics.json")
        let featurePointsURL = arkitDirectory.appendingPathComponent("feature_points.jsonl")
        let planeObservationsURL = arkitDirectory.appendingPathComponent("plane_observations.jsonl")
        let lightEstimatesURL = arkitDirectory.appendingPathComponent("light_estimates.jsonl")
        let arcorePointCloudURL = arcoreDirectory.appendingPathComponent("point_cloud.jsonl")
        let arcorePlanesURL = arcoreDirectory.appendingPathComponent("planes.jsonl")
        let arcoreTrackingStatesURL = arcoreDirectory.appendingPathComponent("tracking_state.jsonl")
        let arcoreLightEstimatesURL = arcoreDirectory.appendingPathComponent("light_estimates.jsonl")
        let glassesFrameTimestampsURL = glassesDirectory.appendingPathComponent("frame_timestamps.jsonl")
        let glassesDeviceStateURL = glassesDirectory.appendingPathComponent("device_state.jsonl")
        let glassesHealthEventsURL = glassesDirectory.appendingPathComponent("health_events.jsonl")
        let companionPhonePosesURL = companionPhoneDirectory.appendingPathComponent("poses.jsonl")
        let companionPhoneIntrinsicsURL = companionPhoneDirectory.appendingPathComponent("session_intrinsics.json")
        let companionPhoneCalibrationURL = companionPhoneDirectory.appendingPathComponent("calibration.json")

        let motion = inspectMotionMetadata(at: motionURL, captureSource: request.metadata.captureSource)
        let poseAlignment = inspectPoseAlignment(framesURL: framesURL, posesURL: posesURL)
        let arkitFrameRows = readJSONObjectLines(from: framesURL)
        let arcoreFrameRows = readJSONObjectLines(from: arcoreFramesURL)
        return CaptureEvidenceSummary(
            arkitFrameRows: arkitFrameRows.count,
            arkitPoseRows: countJSONLines(in: posesURL),
            arkitIntrinsicsValid: isValidIntrinsicsFile(at: intrinsicsURL),
            arkitDepthFrames: countFiles(in: arkitDirectory.appendingPathComponent("depth", isDirectory: true), extensions: ["png"]),
            arkitConfidenceFrames: countFiles(in: arkitDirectory.appendingPathComponent("confidence", isDirectory: true), extensions: ["png"]),
            arkitMeshFiles: countFiles(in: arkitDirectory.appendingPathComponent("meshes", isDirectory: true), extensions: ["obj"]),
            arkitFeaturePointRows: countJSONLines(in: featurePointsURL),
            arkitPlaneRows: countJSONLines(in: planeObservationsURL),
            arkitTrackingStateRows: arkitFrameRows.filter { ($0["trackingState"] as? String) != nil || ($0["tracking_state"] as? String) != nil }.count,
            arkitRelocalizationEventRows: arkitFrameRows.filter { ($0["relocalizationEvent"] as? Bool) == true || ($0["relocalization_event"] as? Bool) == true }.count,
            arkitLightEstimateRows: countJSONLines(in: lightEstimatesURL),
            arcoreFrameRows: arcoreFrameRows.count,
            arcorePoseRows: countJSONLines(in: arcorePosesURL),
            arcoreIntrinsicsValid: isValidIntrinsicsFile(at: arcoreIntrinsicsURL),
            arcoreDepthFrames: countFiles(in: arcoreDirectory.appendingPathComponent("depth", isDirectory: true), extensions: ["png"]),
            arcoreConfidenceFrames: countFiles(in: arcoreDirectory.appendingPathComponent("confidence", isDirectory: true), extensions: ["png"]),
            arcorePointCloudSamples: countJSONLines(in: arcorePointCloudURL),
            arcorePlaneRows: countJSONLines(in: arcorePlanesURL),
            arcoreTrackingStateRows: countJSONLines(in: arcoreTrackingStatesURL),
            arcoreLightEstimateRows: countJSONLines(in: arcoreLightEstimatesURL),
            glassesFrameTimestampRows: countJSONLines(in: glassesFrameTimestampsURL),
            glassesDeviceStateRows: countJSONLines(in: glassesDeviceStateURL),
            glassesHealthEventRows: countJSONLines(in: glassesHealthEventsURL),
            companionPhonePoseRows: countJSONLines(in: companionPhonePosesURL),
            companionPhoneIntrinsicsValid: isValidIntrinsicsFile(at: companionPhoneIntrinsicsURL),
            companionPhoneCalibrationPresent: fileManager.fileExists(atPath: companionPhoneCalibrationURL.path),
            poseMatchRate: poseAlignment.poseMatchRate,
            p95PoseDeltaSec: poseAlignment.p95PoseDeltaSec,
            motionSamples: motion.samples,
            motionProvenance: motion.provenance,
            motionTimestampsCaptureRelative: motion.captureRelative
        )
    }

    private func manifestSceneMemory(
        for request: CaptureUploadRequest,
        evidence: CaptureEvidenceSummary,
        normalized: SceneMemoryCaptureMetadata
    ) -> [String: Any] {
        let capabilities = evidence.captureCapabilities
        return [
            "continuity_score": normalized.continuityScore as Any,
            "lighting_consistency": normalized.lightingConsistency ?? "unknown",
            "dynamic_object_density": normalized.dynamicObjectDensity ?? "unknown",
            "sensor_availability": evidence.sensorAvailability,
            "operator_notes": normalized.operatorNotes,
            "inaccessible_areas": normalized.inaccessibleAreas,
            "semantic_anchors_observed": normalized.semanticAnchorsObserved,
            "relocalization_count": normalized.relocalizationCount as Any,
            "overlap_checkpoint_count": normalized.overlapCheckpointCount as Any,
            "world_model_candidate": CaptureBundleContext.worldModelCandidate(for: request, evidence: evidence),
            "world_model_candidate_reasoning": CaptureBundleContext.worldModelCandidateReasoning(for: request, evidence: evidence),
            "pose_match_rate": evidence.poseMatchRate as Any,
            "p95_pose_delta_sec": evidence.p95PoseDeltaSec as Any,
            "motion_provenance": evidence.motionProvenance as Any,
            "motion_timestamps_capture_relative": evidence.motionTimestampsCaptureRelative,
            "geometry_source": capabilities.geometrySource as Any,
            "geometry_expected_downstream": capabilities.geometryExpectedDownstream,
        ]
    }

    private func manifestCaptureRights(_ rights: CaptureRightsMetadata) -> [String: Any] {
        [
            "derived_scene_generation_allowed": rights.derivedSceneGenerationAllowed,
            "data_licensing_allowed": rights.dataLicensingAllowed,
            "capture_contributor_payout_eligible": rights.payoutEligible,
            "consent_status": rights.consentStatus.rawValue,
            "permission_document_uri": rights.permissionDocumentURI as Any,
            "consent_scope": rights.consentScope,
            "consent_notes": rights.consentNotes,
        ]
    }

    private func recordingWorldFrame(for evidence: CaptureEvidenceSummary) -> RecordingWorldFrame {
        if evidence.arkitPoseRows > 0 || evidence.companionPhonePoseRows > 0 {
            return RecordingWorldFrame(
                worldFrameDefinition: "arkit_world_origin_at_session_start",
                units: "meters",
                handedness: "right_handed",
                gravityAligned: true,
                sessionResetCount: 0
            )
        }
        if evidence.arcorePoseRows > 0 {
            return RecordingWorldFrame(
                worldFrameDefinition: "arcore_world_origin_at_session_start",
                units: "meters",
                handedness: "right_handed",
                gravityAligned: true,
                sessionResetCount: 0
            )
        }
        return RecordingWorldFrame(
            worldFrameDefinition: "unavailable_no_public_world_tracking",
            units: "meters",
            handedness: "unknown",
            gravityAligned: false,
            sessionResetCount: 0
        )
    }

    private func patchManifest(in directory: URL, request: CaptureUploadRequest, mode: CaptureBundleFinalizationMode) throws {
        let manifestURL = directory.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            return
        }

        let sceneId = CaptureBundleContext.sceneIdentifier(for: request)
        let captureId = CaptureBundleContext.captureIdentifier(for: request)
        let data = try Data(contentsOf: manifestURL)
        var json = (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let normalizedSceneMemory = normalizedSceneMemory(for: request, directory: directory)
        let normalizedRights = normalizedCaptureRights(for: request)
        let evidence = inspectEvidence(in: directory, request: request)
        let capabilities = evidence.captureCapabilities
        let topology = effectiveCaptureTopology(for: request, directory: directory)
        let derivedScaffolding = Array(Set((request.metadata.scaffoldingPacket?.scaffoldingUsed ?? []).filter { !$0.hasPrefix("arkit_") } + evidence.derivedScaffoldingUsed)).sorted()
        json["scene_id"] = sceneId
        json["capture_id"] = captureId
        json["site_submission_id"] = request.metadata.siteSubmissionId ?? request.metadata.jobId
        json["buyer_request_id"] = request.metadata.buyerRequestId as Any
        json["capture_job_id"] = request.metadata.captureJobId as Any
        json["region_id"] = request.metadata.regionId as Any
        json["special_task_type"] = request.metadata.specialTaskType?.rawValue as Any
        json["priority_weight"] = request.metadata.priorityWeight as Any
        json["quoted_payout_cents"] = request.metadata.quotedPayoutCents as Any
        json["rights_profile"] = request.metadata.rightsProfile as Any
        json["requested_outputs"] = request.metadata.requestedOutputs
        json["capture_modality"] = CaptureBundleContext.captureModality(for: request, evidence: evidence)
        json["capture_profile_id"] = CaptureBundleContext.captureProfileId(for: request, evidence: evidence)
        json["evidence_tier"] = CaptureBundleContext.evidenceTier(for: request, evidence: evidence)
        json["scaffolding_used"] = derivedScaffolding
        json["coverage_plan"] = request.metadata.scaffoldingPacket?.coveragePlan ?? []
        json["calibration_assets"] = request.metadata.scaffoldingPacket?.calibrationAssets ?? []
        json["scaffolding_validation"] = [
            "scale_anchor_count": request.metadata.scaffoldingPacket?.scaleAnchorAssets.count ?? 0,
            "checkpoint_count": request.metadata.scaffoldingPacket?.checkpointAssets.count ?? 0,
            "validated_scale_m": request.metadata.scaffoldingPacket?.validatedScaleMeters as Any,
            "validated_pose_coverage": request.metadata.scaffoldingPacket?.validatedPoseCoverage as Any,
            "hidden_zone_bound": request.metadata.scaffoldingPacket?.hiddenZoneBound as Any,
            "validated_metric_bundle": request.metadata.scaffoldingPacket?.hasValidatedMetricBundle ?? false,
        ]
        json["uncertainty_priors"] = request.metadata.scaffoldingPacket?.uncertaintyPriors ?? [:]
        json["scene_memory_capture"] = manifestSceneMemory(
            for: request,
            evidence: evidence,
            normalized: normalizedSceneMemory
        )
        json["capture_evidence"] = try JSONSerialization.jsonObject(with: JSONEncoder.snakeCase.encode(evidence))
        json["capture_capabilities"] = try JSONSerialization.jsonObject(with: JSONEncoder.snakeCase.encode(capabilities))

        // Site identity, topology, and capture mode blocks.
        if let siteIdentity = request.metadata.siteIdentity {
            json["site_identity"] = try JSONSerialization.jsonObject(with: JSONEncoder.snakeCase.encode(siteIdentity))
        }
        json["capture_topology"] = try JSONSerialization.jsonObject(with: JSONEncoder.snakeCase.encode(topology))
        if let captureMode = request.metadata.captureMode {
            // Resolve the mode based on actual evidence at finalization time.
            let resolvedMode = CaptureBundleContext.worldModelCandidate(for: request, evidence: evidence)
                ? "site_world_candidate"
                : "qualification_only"
            let downgradeReason: String? = (captureMode.requestedMode == "site_world_candidate" && resolvedMode == "qualification_only")
                ? "insufficient_arkit_evidence"
                : nil
            let resolvedCaptureMode = CaptureModeMetadata(
                requestedMode: captureMode.requestedMode,
                resolvedMode: resolvedMode,
                downgradeReason: downgradeReason
            )
            json["capture_mode"] = try JSONSerialization.jsonObject(with: JSONEncoder.snakeCase.encode(resolvedCaptureMode))
        }
        json["task_text_hint"] = request.metadata.taskHypothesis?.workflowName ?? request.metadata.intakePacket?.workflowName
        json["task_steps"] = request.metadata.taskHypothesis?.taskSteps ?? request.metadata.intakePacket?.taskSteps ?? []
        json["target_kpi"] = request.metadata.taskHypothesis?.targetKPI ?? request.metadata.intakePacket?.targetKPI
        json["zone"] = request.metadata.intakePacket?.zone as Any
        json["shift"] = request.metadata.intakePacket?.shift as Any
        json["owner"] = request.metadata.intakePacket?.owner as Any
        let captureProfile: [String: Any] = [
            "facility_template": request.metadata.intakePacket?.facilityTemplate as Any,
            "required_coverage_areas": request.metadata.intakePacket?.requiredCoverageAreas ?? [],
            "benchmark_stations": request.metadata.intakePacket?.benchmarkStations ?? [],
            "adjacent_systems": request.metadata.intakePacket?.adjacentSystems ?? [],
            "privacy_security_limits": request.metadata.intakePacket?.privacySecurityLimits ?? [],
            "known_blockers": request.metadata.intakePacket?.knownBlockers ?? [],
            "non_routine_modes": request.metadata.intakePacket?.nonRoutineModes ?? [],
            "people_traffic_notes": request.metadata.intakePacket?.peopleTrafficNotes ?? [],
            "capture_restrictions": request.metadata.intakePacket?.captureRestrictions ?? []
        ]
        json["capture_profile"] = captureProfile
        let environmentVariability: [String: Any] = [
            "lighting_windows": request.metadata.intakePacket?.lightingWindows ?? [],
            "shift_traffic_windows": request.metadata.intakePacket?.shiftTrafficWindows ?? [],
            "movable_obstacles": request.metadata.intakePacket?.movableObstacles ?? [],
            "floor_condition_notes": request.metadata.intakePacket?.floorConditionNotes ?? [],
            "reflective_surface_notes": request.metadata.intakePacket?.reflectiveSurfaceNotes ?? [],
            "access_rules": request.metadata.intakePacket?.accessRules ?? []
        ]
        json["environment_variability"] = environmentVariability
        json["capture_rights"] = manifestCaptureRights(normalizedRights)
        json["video_uri"] = mode.videoURI

        let patched = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .withoutEscapingSlashes])
        try patched.write(to: manifestURL, options: .atomic)
    }

    private func materializeSupplementalFiles(in directory: URL, request: CaptureUploadRequest, mode: CaptureBundleFinalizationMode) throws {
        let encoder = JSONEncoder.snakeCase
        let evidence = inspectEvidence(in: directory, request: request)
        let topology = effectiveCaptureTopology(for: request, directory: directory)
        let derivedScaffolding = Array(Set((request.metadata.scaffoldingPacket?.scaffoldingUsed ?? []).filter { !$0.hasPrefix("arkit_") } + evidence.derivedScaffoldingUsed)).sorted()

        let intakePacket = request.metadata.intakePacket ?? QualificationIntakePacket()
        let intakeURL = directory.appendingPathComponent("intake_packet.json")
        try encoder.encode(intakePacket).write(to: intakeURL, options: .atomic)

        let intakeMetadata = request.metadata.intakeMetadata
        let normalizedSceneMemory = normalizedSceneMemory(for: request, directory: directory)
        let normalizedRights = normalizedCaptureRights(for: request)
        let capabilities = evidence.captureCapabilities
        let taskHypothesis = request.metadata.taskHypothesis ?? synthesizedTaskHypothesis(for: request)
        let resolvedCaptureMode: CaptureModeMetadata? = request.metadata.captureMode.map { captureMode in
            let resolvedMode = CaptureBundleContext.worldModelCandidate(for: request, evidence: evidence)
                ? "site_world_candidate"
                : "qualification_only"
            let downgradeReason: String? = (captureMode.requestedMode == "site_world_candidate" && resolvedMode == "qualification_only")
                ? "insufficient_arkit_evidence"
                : nil
            return CaptureModeMetadata(
                requestedMode: captureMode.requestedMode,
                resolvedMode: resolvedMode,
                downgradeReason: downgradeReason
            )
        }
        let context = CaptureContextFile(
            schemaVersion: "v1",
            sceneId: CaptureBundleContext.sceneIdentifier(for: request),
            captureId: CaptureBundleContext.captureIdentifier(for: request),
            siteSubmissionId: request.metadata.siteSubmissionId ?? request.metadata.jobId,
            buyerRequestId: request.metadata.buyerRequestId,
            captureJobId: request.metadata.captureJobId,
            regionId: request.metadata.regionId,
            captureSource: request.metadata.captureSource.rawValue,
            specialTaskType: request.metadata.specialTaskType?.rawValue,
            priorityWeight: request.metadata.priorityWeight,
            quotedPayoutCents: request.metadata.quotedPayoutCents,
            rightsProfile: request.metadata.rightsProfile,
            requestedOutputs: request.metadata.requestedOutputs,
            captureModality: CaptureBundleContext.captureModality(for: request, evidence: evidence),
            captureProfileId: CaptureBundleContext.captureProfileId(for: request, evidence: evidence),
            evidenceTier: CaptureBundleContext.evidenceTier(for: request, evidence: evidence),
            scaffoldingUsed: derivedScaffolding,
            coveragePlan: request.metadata.scaffoldingPacket?.coveragePlan ?? [],
            calibrationAssets: request.metadata.scaffoldingPacket?.calibrationAssets ?? [],
            scaleAnchorAssets: request.metadata.scaffoldingPacket?.scaleAnchorAssets ?? [],
            checkpointAssets: request.metadata.scaffoldingPacket?.checkpointAssets ?? [],
            validatedScaleMeters: request.metadata.scaffoldingPacket?.validatedScaleMeters,
            validatedPoseCoverage: request.metadata.scaffoldingPacket?.validatedPoseCoverage,
            hiddenZoneBound: request.metadata.scaffoldingPacket?.hiddenZoneBound,
            validatedMetricBundle: request.metadata.scaffoldingPacket?.hasValidatedMetricBundle ?? false,
            uncertaintyPriors: request.metadata.scaffoldingPacket?.uncertaintyPriors ?? [:],
            intakePresent: request.metadata.intakePacket?.isComplete == true,
            intakeSource: intakeMetadata?.source.rawValue,
            intakeInferenceModel: intakeMetadata?.model,
            intakeInferenceFPS: intakeMetadata?.fps,
            intakeInferenceConfidence: intakeMetadata?.confidence,
            intakeWarnings: intakeMetadata?.warnings ?? [],
            taskHypothesisStatus: taskHypothesis.status.rawValue,
            taskTextHint: taskHypothesis.workflowName ?? request.metadata.intakePacket?.workflowName,
            taskSteps: taskHypothesis.taskSteps,
            facilityTemplate: request.metadata.intakePacket?.facilityTemplate,
            requiredCoverageAreas: request.metadata.intakePacket?.requiredCoverageAreas ?? [],
            benchmarkStations: request.metadata.intakePacket?.benchmarkStations ?? [],
            lightingWindows: request.metadata.intakePacket?.lightingWindows ?? [],
            shiftTrafficWindows: request.metadata.intakePacket?.shiftTrafficWindows ?? [],
            movableObstacles: request.metadata.intakePacket?.movableObstacles ?? [],
            floorConditionNotes: request.metadata.intakePacket?.floorConditionNotes ?? [],
            reflectiveSurfaceNotes: request.metadata.intakePacket?.reflectiveSurfaceNotes ?? [],
            accessRules: request.metadata.intakePacket?.accessRules ?? [],
            sceneMemory: normalizedSceneMemory,
            captureRights: normalizedRights,
            captureEvidence: evidence,
            captureCapabilities: capabilities,
            worldModelCandidate: CaptureBundleContext.worldModelCandidate(for: request, evidence: evidence),
            worldModelCandidateReasoning: CaptureBundleContext.worldModelCandidateReasoning(for: request, evidence: evidence),
            siteIdentity: request.metadata.siteIdentity,
            captureTopology: topology,
            captureMode: resolvedCaptureMode,
            semanticAnchors: request.metadata.semanticAnchors,
            capturedAt: ISO8601DateFormatter().string(from: request.metadata.capturedAt)
        )
        let contextURL = directory.appendingPathComponent("capture_context.json")
        try encoder.encode(context).write(to: contextURL, options: .atomic)

        // Write standalone site_identity.json for pipeline and bridge consumption.
        if let siteIdentity = request.metadata.siteIdentity {
            let siteIdentityURL = directory.appendingPathComponent("site_identity.json")
            try encoder.encode(siteIdentity).write(to: siteIdentityURL, options: .atomic)
        }

        let topologyURL = directory.appendingPathComponent("capture_topology.json")
        try encoder.encode(topology).write(to: topologyURL, options: .atomic)
        if let captureMode = resolvedCaptureMode {
            let captureModeURL = directory.appendingPathComponent(captureModeFilename)
            try encoder.encode(captureMode).write(to: captureModeURL, options: .atomic)
        }

        let semanticAnchors = request.metadata.semanticAnchors

        // Write route_anchors.json from entry anchor plus any semantic anchors observed during capture.
        let semanticRouteAnchors = semanticAnchors.reduce(into: [String: RouteAnchorsFile.RouteAnchor]()) { anchors, event in
            let anchorId = event.id
            anchors[anchorId] = RouteAnchorsFile.RouteAnchor(
                anchorId: anchorId,
                anchorType: event.anchorType.rawValue,
                label: event.label ?? event.anchorType.displayLabel,
                expectedObservation: "tap_marker",
                requiredInPrimaryPass: false,
                requiredInRevisitPass: true
            )
        }
        let routeAnchors = RouteAnchorsFile(
            schemaVersion: "v1",
            routeAnchors: ([
                RouteAnchorsFile.RouteAnchor(
                    anchorId: "anchor_entry",
                    anchorType: "entry",
                    label: "Site entry point",
                    expectedObservation: "pause_and_pan",
                    requiredInPrimaryPass: true,
                    requiredInRevisitPass: true
                )
            ] + semanticRouteAnchors.values.sorted { $0.anchorId < $1.anchorId })
        )
        let routeAnchorsURL = directory.appendingPathComponent("route_anchors.json")
        try encoder.encode(routeAnchors).write(to: routeAnchorsURL, options: .atomic)

        // Write checkpoint_events.json from entry hold plus semantic checkpoints.
        var checkpointEvents: [CheckpointEventsFile.CheckpointEvent] = []
        if let tCaptureSec = topology.entryAnchorTCaptureSec,
           let holdDuration = topology.entryAnchorHoldDurationSec {
            checkpointEvents.append(CheckpointEventsFile.CheckpointEvent(
                anchorId: "anchor_entry",
                passId: topology.passId,
                tCaptureSec: tCaptureSec,
                holdDurationSec: holdDuration,
                completed: true
            ))
        }
        checkpointEvents += semanticAnchors.compactMap { event in
            guard let tCaptureSec = event.tCaptureSec else { return nil }
            return CheckpointEventsFile.CheckpointEvent(
                anchorId: event.id,
                passId: topology.passId,
                tCaptureSec: tCaptureSec,
                holdDurationSec: 0.0,
                completed: true
            )
        }
        let checkpointEventsFile = CheckpointEventsFile(
            schemaVersion: "v1",
            checkpointEvents: checkpointEvents
        )
        let checkpointEventsURL = directory.appendingPathComponent("checkpoint_events.json")
        try encoder.encode(checkpointEventsFile).write(to: checkpointEventsURL, options: .atomic)

        let semanticAnchorsURL = directory.appendingPathComponent("semantic_anchors.json")
        try encoder.encode(semanticAnchors).write(to: semanticAnchorsURL, options: .atomic)

        let recordingWorldFrame = recordingWorldFrame(for: evidence)
        let recordingSession = RecordingSessionFile(
            schemaVersion: "v1",
            sceneId: CaptureBundleContext.sceneIdentifier(for: request),
            captureId: CaptureBundleContext.captureIdentifier(for: request),
            siteVisitId: topology.siteVisitId ?? topology.captureSessionId,
            routeId: topology.routeId,
            passId: topology.passId,
            passIndex: topology.passIndex,
            passRole: topology.intendedPassRole,
            coordinateFrameSessionId: topology.coordinateFrameSessionId ?? topology.captureSessionId,
            arkitSessionId: topology.arkitSessionId ?? topology.coordinateFrameSessionId,
            worldFrameDefinition: recordingWorldFrame.worldFrameDefinition,
            units: recordingWorldFrame.units,
            handedness: recordingWorldFrame.handedness,
            gravityAligned: recordingWorldFrame.gravityAligned,
            sessionResetCount: recordingWorldFrame.sessionResetCount,
            capturedAt: ISO8601DateFormatter().string(from: request.metadata.capturedAt)
        )
        let recordingSessionURL = directory.appendingPathComponent("recording_session.json")
        try encoder.encode(recordingSession).write(to: recordingSessionURL, options: .atomic)

        let relocalizationEvents = groupedRelocalizationEvents(in: directory)
        let relocalizationEventsFile = RelocalizationEventsFile(
            schemaVersion: "v1",
            relocalizationEvents: relocalizationEvents
        )
        let relocalizationEventsURL = directory.appendingPathComponent("relocalization_events.json")
        try encoder.encode(relocalizationEventsFile).write(to: relocalizationEventsURL, options: .atomic)

        let overlapGraph = OverlapGraphFile(
            schemaVersion: "v1",
            siteVisitId: topology.siteVisitId ?? topology.captureSessionId,
            routeId: topology.routeId,
            passId: topology.passId,
            passRole: topology.intendedPassRole,
            coordinateFrameSessionId: topology.coordinateFrameSessionId ?? topology.captureSessionId,
            observedAnchorIds: Array(Set(checkpointEvents.map(\.anchorId))).sorted(),
            semanticAnchorIds: Array(Set(semanticAnchors.map(\.id))).sorted(),
            relocalizationEventCount: relocalizationEvents.reduce(0) { $0 + $1.frameCount }
        )
        let overlapGraphURL = directory.appendingPathComponent("overlap_graph.json")
        try encoder.encode(overlapGraph).write(to: overlapGraphURL, options: .atomic)

        try writeARKitDerivedSidecars(in: directory, coordinateFrameSessionId: topology.coordinateFrameSessionId ?? topology.captureSessionId)

        let taskHypothesisURL = directory.appendingPathComponent(taskHypothesisFilename)
        try encoder.encode(taskHypothesis).write(to: taskHypothesisURL, options: .atomic)

        let completion = UploadCompletionFile(
            schemaVersion: "v1",
            sceneId: CaptureBundleContext.sceneIdentifier(for: request),
            captureId: CaptureBundleContext.captureIdentifier(for: request),
            rawPrefix: mode.rawPrefix,
            completedAt: ISO8601DateFormatter().string(from: Date())
        )
        let completionURL = directory.appendingPathComponent(completionMarkerFilename)
        try encoder.encode(completion).write(to: completionURL, options: .atomic)

        try writeV3SupplementalFiles(
            in: directory,
            request: request,
            topology: topology,
            rights: normalizedRights
        )
    }

    private func synthesizedTaskHypothesis(for request: CaptureUploadRequest) -> CaptureTaskHypothesis {
        let packet = request.metadata.intakePacket ?? QualificationIntakePacket()
        let metadata = request.metadata.intakeMetadata ?? CaptureIntakeMetadata(source: .authoritative)
        return CaptureTaskHypothesis(packet: packet, metadata: metadata, status: .accepted)
    }

    private func effectiveCaptureTopology(for request: CaptureUploadRequest, directory: URL) -> CaptureTopologyMetadata {
        if let topology = request.metadata.captureTopology {
            return topology
        }

        let manifestURL = directory.appendingPathComponent("manifest.json")
        let manifestObject = (try? JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL))) as? [String: Any]
        let arkitFramesURL = directory.appendingPathComponent("arkit/frames.jsonl")
        let firstFrame = readJSONLines(from: arkitFramesURL).first
        let coordinateFrameSessionId =
            stringValue(in: firstFrame ?? [:], keys: ["coordinate_frame_session_id", "coordinateFrameSessionId"])
            ?? manifestObject?["coordinate_frame_session_id"] as? String
            ?? request.metadata.semanticAnchors.first?.coordinateFrameSessionId
            ?? CaptureBundleContext.captureIdentifier(for: request)

        let captureSessionId = request.metadata.siteSubmissionId
            ?? request.metadata.captureJobId
            ?? request.metadata.jobId

        return CaptureTopologyMetadata(
            captureSessionId: captureSessionId,
            routeId: "route_unknown",
            passId: "pass_primary_1",
            passIndex: 1,
            intendedPassRole: "primary",
            entryAnchorId: "anchor_entry",
            returnAnchorId: nil,
            entryAnchorTCaptureSec: nil,
            entryAnchorHoldDurationSec: nil,
            siteVisitId: captureSessionId,
            coordinateFrameSessionId: coordinateFrameSessionId,
            arkitSessionId: coordinateFrameSessionId
        )
    }

    private func writeV3SupplementalFiles(
        in directory: URL,
        request: CaptureUploadRequest,
        topology: CaptureTopologyMetadata,
        rights: CaptureRightsMetadata
    ) throws {
        let sceneId = CaptureBundleContext.sceneIdentifier(for: request)
        let captureId = CaptureBundleContext.captureIdentifier(for: request)

        let rightsConsent: [String: Any] = [
            "schema_version": "v1",
            "scene_id": sceneId,
            "capture_id": captureId,
            "consent_status": rights.consentStatus.rawValue,
            "capture_basis": rights.consentStatus == .documented ? "site_operator_permission" : "unknown",
            "derived_scene_generation_allowed": rights.derivedSceneGenerationAllowed,
            "data_licensing_allowed": rights.dataLicensingAllowed,
            "capture_contributor_payout_eligible": rights.payoutEligible,
            "permission_document_uri": rights.permissionDocumentURI ?? NSNull(),
            "permission_document_sha256": rights.permissionDocumentURI.map { _ in "unverified_external_reference" } ?? NSNull(),
            "consent_scope": rights.consentScope,
            "consent_notes": rights.consentNotes,
            "redaction_required": true,
            "retention_policy": "standard_blueprint_site_capture",
        ]
        let rightsConsentURL = directory.appendingPathComponent("rights_consent.json")
        let rightsConsentData = try JSONSerialization.data(withJSONObject: rightsConsent, options: [.prettyPrinted, .withoutEscapingSlashes])
        try rightsConsentData.write(to: rightsConsentURL, options: .atomic)

        let semanticObservationsURL = directory.appendingPathComponent("semantic_anchor_observations.jsonl")
        let semanticLines = request.metadata.semanticAnchors.map { event -> String in
            var payload: [String: Any] = [
                "anchor_instance_id": event.id,
                "anchor_type": event.anchorType.rawValue,
                "label": event.label ?? NSNull(),
                "frame_id": event.frameId ?? NSNull(),
                "t_capture_sec": event.tCaptureSec ?? NSNull(),
                "coordinate_frame_session_id": event.coordinateFrameSessionId ?? topology.coordinateFrameSessionId ?? NSNull(),
                "observation_method": "manual_tap",
                "confidence": 1.0,
                "notes": event.notes ?? NSNull(),
            ]
            if let tCaptureSec = event.tCaptureSec {
                payload["t_monotonic_ns"] = Int64((tCaptureSec * 1_000_000_000.0).rounded())
            }
            let data = try? JSONSerialization.data(withJSONObject: payload, options: [.withoutEscapingSlashes])
            return String(data: data ?? Data("{}".utf8), encoding: .utf8) ?? "{}"
        }
        try semanticLines.joined(separator: "\n").appending(semanticLines.isEmpty ? "" : "\n").write(
            to: semanticObservationsURL,
            atomically: true,
            encoding: .utf8
        )

        try writeVideoTrackFile(in: directory)
        try writeHashesAndProvenance(in: directory, request: request)
    }

    private func writeVideoTrackFile(in directory: URL) throws {
        let videoURL = directory.appendingPathComponent("walkthrough.mov")
        let manifestURL = directory.appendingPathComponent("manifest.json")
        let manifestObject = (try? JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL))) as? [String: Any]
        let frameRows = readJSONLines(from: directory.appendingPathComponent("arkit/frames.jsonl"))
        let width = Int((manifestObject?["width"] as? NSNumber)?.doubleValue ?? 0)
        let height = Int((manifestObject?["height"] as? NSNumber)?.doubleValue ?? 0)
        let fps = (manifestObject?["fps_source"] as? NSNumber)?.doubleValue ?? 0.0

        let asset = AVURLAsset(url: videoURL)
        let durationSeconds = asset.duration.seconds.isFinite ? max(0.0, asset.duration.seconds) : 0.0
        let videoTrack = asset.tracks(withMediaType: .video).first
        let trackSize = videoTrack?.naturalSize ?? .zero
        let nominalFPS = videoTrack?.nominalFrameRate ?? Float(fps)
        let estimatedFrameCount: Int = {
            if nominalFPS > 0, durationSeconds > 0 {
                return Int((durationSeconds * Double(nominalFPS)).rounded())
            }
            return frameRows.count
        }()

        let videoTrackPayload: [String: Any] = [
            "schema_version": "v1",
            "video_file": "walkthrough.mov",
            "duration_sec": durationSeconds,
            "frame_count": estimatedFrameCount,
            "nominal_fps": Double(nominalFPS),
            "contains_vfr": false,
            "video_start_pts_sec": 0.0,
            "width": Int(trackSize.width.rounded()).nonZero(or: width),
            "height": Int(trackSize.height.rounded()).nonZero(or: height),
            "orientation": "portrait",
            "codec": "h264",
            "color_space": manifestObject?["color_space"] as? String ?? "unknown",
        ]
        let videoTrackURL = directory.appendingPathComponent("video_track.json")
        let data = try JSONSerialization.data(withJSONObject: videoTrackPayload, options: [.prettyPrinted, .withoutEscapingSlashes])
        try data.write(to: videoTrackURL, options: .atomic)
    }

    private func writeHashesAndProvenance(in directory: URL, request: CaptureUploadRequest) throws {
        let sceneId = CaptureBundleContext.sceneIdentifier(for: request)
        let captureId = CaptureBundleContext.captureIdentifier(for: request)
        let provenanceURL = directory.appendingPathComponent("provenance.json")
        let hashesURL = directory.appendingPathComponent("hashes.json")

        let provisionalProvenance: [String: Any] = [
            "schema_version": "v1",
            "scene_id": sceneId,
            "capture_id": captureId,
            "capture_source": request.metadata.captureSource.rawValue,
            "captured_by_user_id": request.metadata.creatorId,
            "uploaded_by_user_id": request.metadata.creatorId,
            "capture_app_build": Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String ?? "unknown",
            "capture_app_version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            "device_installation_id": request.metadata.creatorId,
            "bundle_created_at": ISO8601DateFormatter().string(from: request.metadata.capturedAt),
            "upload_completed_at": ISO8601DateFormatter().string(from: Date()),
            "bundle_sha256": "pending",
        ]
        let provisionalData = try JSONSerialization.data(withJSONObject: provisionalProvenance, options: [.prettyPrinted, .withoutEscapingSlashes])
        try provisionalData.write(to: provenanceURL, options: .atomic)

        let artifactHashes = try buildArtifactHashes(in: directory, excluding: ["hashes.json"])
        let bundleSha = bundleHash(from: artifactHashes)

        var finalProvenance = provisionalProvenance
        finalProvenance["bundle_sha256"] = bundleSha
        let finalProvenanceData = try JSONSerialization.data(withJSONObject: finalProvenance, options: [.prettyPrinted, .withoutEscapingSlashes])
        try finalProvenanceData.write(to: provenanceURL, options: .atomic)

        let finalArtifactHashes = try buildArtifactHashes(in: directory, excluding: ["hashes.json"])
        let hashesPayload: [String: Any] = [
            "schema_version": "v1",
            "bundle_sha256": bundleHash(from: finalArtifactHashes),
            "artifacts": finalArtifactHashes,
        ]
        let hashesData = try JSONSerialization.data(withJSONObject: hashesPayload, options: [.prettyPrinted, .withoutEscapingSlashes])
        try hashesData.write(to: hashesURL, options: .atomic)
    }

    private func buildArtifactHashes(in directory: URL, excluding excludedNames: Set<String>) throws -> [String: String] {
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return [:]
        }

        var hashes: [String: String] = [:]
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            guard !excludedNames.contains(fileURL.lastPathComponent) else { continue }
            let relative = relativePathInBundle(for: fileURL, relativeTo: directory)
            let data = try Data(contentsOf: fileURL)
            hashes[relative] = sha256Hex(of: data)
        }
        return hashes
    }

    private func bundleHash(from artifactHashes: [String: String]) -> String {
        let canonical = artifactHashes
            .sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }
            .joined(separator: "\n")
        return sha256Hex(of: Data(canonical.utf8))
    }

    private func sha256Hex(of data: Data) -> String {
        #if canImport(CryptoKit)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
        #else
        return data.base64EncodedString()
        #endif
    }

    private func relativePathInBundle(for url: URL, relativeTo directory: URL) -> String {
        let path = url.standardizedFileURL.path
        let basePath = directory.standardizedFileURL.path
        guard path.hasPrefix(basePath) else { return url.lastPathComponent }
        var relative = String(path.dropFirst(basePath.count))
        while relative.hasPrefix("/") {
            relative.removeFirst()
        }
        return relative.isEmpty ? url.lastPathComponent : relative
    }

    private func writeARKitDerivedSidecars(in directory: URL, coordinateFrameSessionId: String?) throws {
        let arkitDirectory = directory.appendingPathComponent("arkit", isDirectory: true)
        let framesURL = arkitDirectory.appendingPathComponent("frames.jsonl")
        guard fileManager.fileExists(atPath: framesURL.path) else { return }

        let frameRows = readJSONLines(from: framesURL)
        guard !frameRows.isEmpty else { return }

        let frameQualityURL = arkitDirectory.appendingPathComponent("frame_quality.jsonl")
        let perFrameCameraStateURL = arkitDirectory.appendingPathComponent("per_frame_camera_state.jsonl")
        let syncMapURL = directory.appendingPathComponent("sync_map.jsonl")
        let depthManifestURL = arkitDirectory.appendingPathComponent("depth_manifest.json")
        let confidenceManifestURL = arkitDirectory.appendingPathComponent("confidence_manifest.json")
        let sessionIntrinsicsURL = arkitDirectory.appendingPathComponent("session_intrinsics.json")
        let manifestURL = directory.appendingPathComponent("manifest.json")
        let rawManifest = (try? JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL))) as? [String: Any]
        let intrinsicsURL = arkitDirectory.appendingPathComponent("intrinsics.json")
        let intrinsicsObject = (try? JSONSerialization.jsonObject(with: Data(contentsOf: intrinsicsURL))) as? [String: Any]

        let frameQualityLines = frameRows.map { row -> String in
            var qualityRow: [String: Any] = [
                "anchor_observations": arrayValue(in: row, keys: ["anchorObservations", "anchor_observations"]),
            ]
            if let frameId = stringValue(in: row, keys: ["frameId", "frame_id"]) {
                qualityRow["frame_id"] = frameId
            }
            if let tCaptureSec = doubleValue(in: row, keys: ["tCaptureSec", "t_capture_sec"]) {
                qualityRow["t_capture_sec"] = tCaptureSec
            }
            if let trackingState = stringValue(in: row, keys: ["trackingState", "tracking_state"]) {
                qualityRow["tracking_state"] = trackingState
            }
            if let trackingReason = stringValue(in: row, keys: ["trackingReason", "tracking_reason"]) {
                qualityRow["tracking_reason"] = trackingReason
            }
            if let worldMappingStatus = stringValue(in: row, keys: ["worldMappingStatus", "world_mapping_status"]) {
                qualityRow["world_mapping_status"] = worldMappingStatus
            }
            if let relocalizationEvent = boolValue(in: row, keys: ["relocalizationEvent", "relocalization_event"]) {
                qualityRow["relocalization_event"] = relocalizationEvent
            }
            if let sharpnessScore = doubleValue(in: row, keys: ["sharpnessScore", "sharpness_score"]) {
                qualityRow["sharpness_score"] = sharpnessScore
            }
            if let depthSource = stringValue(in: row, keys: ["depthSource", "depth_source"]) {
                qualityRow["depth_source"] = depthSource
            }
            if let depthValidFraction = doubleValue(in: row, keys: ["depthValidFraction", "depth_valid_fraction"]) {
                qualityRow["depth_valid_fraction"] = depthValidFraction
            }
            if let missingDepthFraction = doubleValue(in: row, keys: ["missingDepthFraction", "missing_depth_fraction"]) {
                qualityRow["missing_depth_fraction"] = missingDepthFraction
            }
            if let sceneDepthFile = stringValue(in: row, keys: ["sceneDepthFile", "scene_depth_file"]) {
                qualityRow["scene_depth_file"] = sceneDepthFile
            }
            if let smoothedSceneDepthFile = stringValue(in: row, keys: ["smoothedSceneDepthFile", "smoothed_scene_depth_file"]) {
                qualityRow["smoothed_scene_depth_file"] = smoothedSceneDepthFile
            }
            if let confidenceFile = stringValue(in: row, keys: ["confidenceFile", "confidence_file"]) {
                qualityRow["confidence_file"] = confidenceFile
            }
            if let exposureDuration = doubleValue(in: row, keys: ["exposureDurationS", "exposure_duration_s"]) {
                qualityRow["exposure_duration_s"] = exposureDuration
            }
            if let iso = doubleValue(in: row, keys: ["iso"]) {
                qualityRow["iso"] = iso
            }
            if let exposureTargetBias = doubleValue(in: row, keys: ["exposureTargetBias", "exposure_target_bias"]) {
                qualityRow["exposure_target_bias"] = exposureTargetBias
            }
            if let whiteBalanceGains = dictionaryValue(in: row, keys: ["whiteBalanceGains", "white_balance_gains"]) {
                qualityRow["white_balance_gains"] = whiteBalanceGains
            }
            if let coordinateFrameSessionId = stringValue(in: row, keys: ["coordinateFrameSessionId", "coordinate_frame_session_id"]) ?? coordinateFrameSessionId {
                qualityRow["coordinate_frame_session_id"] = coordinateFrameSessionId
            }
            if let tMonotonicNs = objectValue(in: row, keys: ["tMonotonicNs", "t_monotonic_ns"]) as? NSNumber {
                qualityRow["t_monotonic_ns"] = tMonotonicNs.int64Value
            }
            let isRelocalization = boolValue(in: row, keys: ["relocalizationEvent", "relocalization_event"]) ?? false
            let hasDepthRepresentation =
                stringValue(in: row, keys: ["smoothedSceneDepthFile", "smoothed_scene_depth_file"]) != nil ||
                stringValue(in: row, keys: ["sceneDepthFile", "scene_depth_file"]) != nil
            let trackingState = stringValue(in: row, keys: ["trackingState", "tracking_state"]) ?? "unknown"
            qualityRow["usable_for_pose"] = trackingState == "normal" && !isRelocalization
            qualityRow["usable_for_depth"] = hasDepthRepresentation && !isRelocalization
            let encoded = try? JSONSerialization.data(withJSONObject: qualityRow, options: [.withoutEscapingSlashes])
            return String(data: encoded ?? Data("{}".utf8), encoding: .utf8) ?? "{}"
        }
        try frameQualityLines.joined(separator: "\n").appending("\n").write(to: frameQualityURL, atomically: true, encoding: .utf8)

        let perFrameCameraStateLines = frameRows.map { row -> String in
            var payload: [String: Any] = [:]
            if let frameId = stringValue(in: row, keys: ["frameId", "frame_id"]) {
                payload["frame_id"] = frameId
            }
            if let tCaptureSec = doubleValue(in: row, keys: ["tCaptureSec", "t_capture_sec"]) {
                payload["t_capture_sec"] = tCaptureSec
            }
            if let tMonotonicNs = objectValue(in: row, keys: ["tMonotonicNs", "t_monotonic_ns"]) as? NSNumber {
                payload["t_monotonic_ns"] = tMonotonicNs.int64Value
            }
            payload["coordinate_frame_session_id"] = stringValue(in: row, keys: ["coordinateFrameSessionId", "coordinate_frame_session_id"]) ?? coordinateFrameSessionId ?? NSNull()
            if let exposureDuration = doubleValue(in: row, keys: ["exposureDurationS", "exposure_duration_s"]) {
                payload["exposure_duration_s"] = exposureDuration
            }
            if let iso = doubleValue(in: row, keys: ["iso"]) {
                payload["iso"] = iso
            }
            if let exposureTargetBias = doubleValue(in: row, keys: ["exposureTargetBias", "exposure_target_bias"]) {
                payload["exposure_target_bias"] = exposureTargetBias
            }
            if let whiteBalanceGains = dictionaryValue(in: row, keys: ["whiteBalanceGains", "white_balance_gains"]) {
                payload["white_balance_gains"] = whiteBalanceGains
            }
            payload["focus_mode"] = NSNull()
            payload["focus_locked"] = NSNull()
            payload["zoom_factor"] = 1.0
            payload["exposure_mode"] = NSNull()
            payload["exposure_locked"] = NSNull()
            payload["white_balance_mode"] = NSNull()
            payload["video_stabilization_mode"] = NSNull()
            payload["torch_active"] = false
            payload["hdr_active"] = false
            let encoded = try? JSONSerialization.data(withJSONObject: payload, options: [.withoutEscapingSlashes])
            return String(data: encoded ?? Data("{}".utf8), encoding: .utf8) ?? "{}"
        }
        try perFrameCameraStateLines.joined(separator: "\n").appending("\n").write(to: perFrameCameraStateURL, atomically: true, encoding: .utf8)

        let syncMapLines = frameRows.compactMap { row -> String? in
            guard let frameId = stringValue(in: row, keys: ["frameId", "frame_id"]),
                  let tCaptureSec = doubleValue(in: row, keys: ["tCaptureSec", "t_capture_sec"]) else { return nil }
            var payload: [String: Any] = [
                "frame_id": frameId,
                "t_video_sec": tCaptureSec,
                "t_capture_sec": tCaptureSec,
                "pose_frame_id": frameId,
                "sync_status": "exact_frame_id_match",
                "delta_ms": 0.0,
            ]
            if let tMonotonicNs = objectValue(in: row, keys: ["tMonotonicNs", "t_monotonic_ns"]) as? NSNumber {
                payload["t_monotonic_ns"] = tMonotonicNs.int64Value
            } else if let timestamp = doubleValue(in: row, keys: ["timestamp"]) {
                payload["t_monotonic_ns"] = Int64((timestamp * 1_000_000_000.0).rounded())
            }
            let encoded = try? JSONSerialization.data(withJSONObject: payload, options: [.withoutEscapingSlashes])
            return String(data: encoded ?? Data("{}".utf8), encoding: .utf8)
        }
        try syncMapLines.joined(separator: "\n").appending(syncMapLines.isEmpty ? "" : "\n").write(to: syncMapURL, atomically: true, encoding: .utf8)

        let depthEntries = frameRows.compactMap { row -> [String: Any]? in
            guard let frameId = stringValue(in: row, keys: ["frameId", "frame_id"]) else { return nil }
            let depthPath = stringValue(in: row, keys: ["smoothedSceneDepthFile", "smoothed_scene_depth_file"])
                ?? stringValue(in: row, keys: ["sceneDepthFile", "scene_depth_file"])
            guard let depthPath else { return nil }
            var entry: [String: Any] = [
                "frame_id": frameId,
                "depth_path": depthPath,
                "representation": "per_frame_depth_map",
                "depth_source": stringValue(in: row, keys: ["depthSource", "depth_source"]) ?? "unknown",
            ]
            if let depthValidFraction = doubleValue(in: row, keys: ["depthValidFraction", "depth_valid_fraction"]) {
                entry["depth_valid_fraction"] = depthValidFraction
            }
            if let missingDepthFraction = doubleValue(in: row, keys: ["missingDepthFraction", "missing_depth_fraction"]) {
                entry["missing_depth_fraction"] = missingDepthFraction
            }
            return entry
        }
        var depthManifest: [String: Any] = [
            "schema_version": "v1",
            "representation": "per_frame_depth_map",
            "encoding": "png_u16_mm",
            "units": "millimeters",
            "invalid_value_semantics": "0_means_missing",
            "missing_depth_reason": NSNull(),
            "frames": depthEntries,
        ]
        if let coordinateFrameSessionId {
            depthManifest["coordinate_frame_session_id"] = coordinateFrameSessionId
        }
        let depthManifestData = try JSONSerialization.data(withJSONObject: depthManifest, options: [.prettyPrinted, .withoutEscapingSlashes])
        try depthManifestData.write(to: depthManifestURL, options: .atomic)

        let confidenceEntries = frameRows.compactMap { row -> [String: Any]? in
            guard let frameId = stringValue(in: row, keys: ["frameId", "frame_id"]),
                  let confidencePath = stringValue(in: row, keys: ["confidenceFile", "confidence_file"]) else { return nil }
            var entry: [String: Any] = [
                "frame_id": frameId,
                "confidence_path": confidencePath,
                "representation": "per_frame_confidence_map",
            ]
            if let pairedDepthPath = stringValue(in: row, keys: ["smoothedSceneDepthFile", "smoothed_scene_depth_file"])
                ?? stringValue(in: row, keys: ["sceneDepthFile", "scene_depth_file"]) {
                entry["paired_depth_path"] = pairedDepthPath
            }
            return entry
        }
        var confidenceManifest: [String: Any] = [
            "schema_version": "v1",
            "representation": "per_frame_confidence_map",
            "encoding": "png_u8",
            "confidence_scale": [
                "0": "low_or_missing",
                "1": "medium",
                "2": "high",
            ],
            "frames": confidenceEntries,
        ]
        if let coordinateFrameSessionId {
            confidenceManifest["coordinate_frame_session_id"] = coordinateFrameSessionId
        }
        let confidenceManifestData = try JSONSerialization.data(withJSONObject: confidenceManifest, options: [.prettyPrinted, .withoutEscapingSlashes])
        try confidenceManifestData.write(to: confidenceManifestURL, options: .atomic)

        var sessionIntrinsics: [String: Any] = [
            "schema_version": "v1",
            "camera_model": "pinhole",
            "principal_point_reference": "full_resolution_image",
            "distortion_model": "apple_standard",
            "distortion_coeffs": [],
        ]
        if let coordinateFrameSessionId {
            sessionIntrinsics["coordinate_frame_session_id"] = coordinateFrameSessionId
        }
        if let intrinsicsObject {
            sessionIntrinsics["intrinsics"] = intrinsicsObject
        }
        if let cameraIntrinsics = rawManifest?["camera_intrinsics"] as? [String: Any] {
            sessionIntrinsics["camera_intrinsics"] = cameraIntrinsics
        }
        if let exposureSettings = rawManifest?["exposure_settings"] as? [String: Any] {
            sessionIntrinsics["exposure_settings"] = exposureSettings
        }
        let sessionIntrinsicsData = try JSONSerialization.data(withJSONObject: sessionIntrinsics, options: [.prettyPrinted, .withoutEscapingSlashes])
        try sessionIntrinsicsData.write(to: sessionIntrinsicsURL, options: .atomic)
    }

    private func groupedRelocalizationEvents(in directory: URL) -> [RelocalizationEventsFile.RelocalizationEvent] {
        let framesURL = directory.appendingPathComponent("arkit/frames.jsonl")
        let frameRows = readJSONLines(from: framesURL)
        guard !frameRows.isEmpty else { return [] }

        var events: [RelocalizationEventsFile.RelocalizationEvent] = []
        var startFrameId: String?
        var startTCaptureSec: Double?
        var endFrameId: String?
        var endTCaptureSec: Double?
        var frameCount = 0

        func flushEvent() {
            guard frameCount > 0 else { return }
            events.append(
                RelocalizationEventsFile.RelocalizationEvent(
                    startFrameId: startFrameId,
                    endFrameId: endFrameId,
                    startTCaptureSec: startTCaptureSec,
                    endTCaptureSec: endTCaptureSec,
                    frameCount: frameCount
                )
            )
            startFrameId = nil
            startTCaptureSec = nil
            endFrameId = nil
            endTCaptureSec = nil
            frameCount = 0
        }

        for row in frameRows {
            let isRelocalization = boolValue(in: row, keys: ["relocalizationEvent", "relocalization_event"]) ?? false
            let frameId = stringValue(in: row, keys: ["frameId", "frame_id"])
            let tCaptureSec = doubleValue(in: row, keys: ["tCaptureSec", "t_capture_sec"])
            if isRelocalization {
                if frameCount == 0 {
                    startFrameId = frameId
                    startTCaptureSec = tCaptureSec
                }
                endFrameId = frameId
                endTCaptureSec = tCaptureSec
                frameCount += 1
            } else {
                flushEvent()
            }
        }
        flushEvent()
        return events
    }

    private func readJSONLines(from url: URL) -> [[String: Any]] {
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else {
            return []
        }
        return content
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                guard let lineData = String(line).data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                    return nil
                }
                return object
            }
    }

    private func stringValue(in object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }

    private func doubleValue(in object: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = object[key] as? Double {
                return value
            }
            if let value = object[key] as? NSNumber {
                return value.doubleValue
            }
        }
        return nil
    }

    private func boolValue(in object: [String: Any], keys: [String]) -> Bool? {
        for key in keys {
            if let value = object[key] as? Bool {
                return value
            }
            if let value = object[key] as? NSNumber {
                return value.boolValue
            }
        }
        return nil
    }

    private func dictionaryValue(in object: [String: Any], keys: [String]) -> [String: Any]? {
        for key in keys {
            if let value = object[key] as? [String: Any] {
                return value
            }
        }
        return nil
    }

    private func objectValue(in object: [String: Any], keys: [String]) -> Any? {
        for key in keys {
            if let value = object[key] {
                return value
            }
        }
        return nil
    }

    private func arrayValue(in object: [String: Any], keys: [String]) -> [String] {
        for key in keys {
            if let value = object[key] as? [String] {
                return value
            }
        }
        return []
    }
}

protocol CaptureExportServiceProtocol {
    func exportCapture(request: CaptureUploadRequest) async throws -> FinalizedCaptureBundle
}

final class CaptureExportService: CaptureExportServiceProtocol {
    private let finalizer: CaptureBundleFinalizerProtocol

    init(finalizer: CaptureBundleFinalizerProtocol = CaptureBundleFinalizer()) {
        self.finalizer = finalizer
    }

    func exportCapture(request: CaptureUploadRequest) async throws -> FinalizedCaptureBundle {
        let finalized = try finalizer.finalize(request: request, mode: .localExport())
        let exportRoot = try makeExportRoot(for: finalized)
        let rawDestination = exportRoot.appendingPathComponent("raw", isDirectory: true)

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: exportRoot.path) {
            try fileManager.removeItem(at: exportRoot)
        }
        try fileManager.createDirectory(at: exportRoot.deletingLastPathComponent(), withIntermediateDirectories: true)
        try copyDirectory(from: finalized.rawDirectoryURL, to: rawDestination)

        let shareURL = try makeShareArtifact(for: exportRoot)
        return FinalizedCaptureBundle(
            sceneId: finalized.sceneId,
            captureId: finalized.captureId,
            rawDirectoryURL: rawDestination,
            captureRootURL: exportRoot,
            shareURL: shareURL
        )
    }

    private func makeExportRoot(for bundle: FinalizedCaptureBundle) throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let root = base
            .appendingPathComponent("BlueprintCapture", isDirectory: true)
            .appendingPathComponent("Exports", isDirectory: true)
            .appendingPathComponent("scenes", isDirectory: true)
            .appendingPathComponent(bundle.sceneId, isDirectory: true)
            .appendingPathComponent("captures", isDirectory: true)
            .appendingPathComponent(bundle.captureId, isDirectory: true)
        return root
    }

    private func copyDirectory(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.copyItem(at: source, to: destination)
    }

    private func makeShareArtifact(for exportRoot: URL) throws -> URL {
        #if canImport(ZIPFoundation)
        let zipURL = exportRoot
            .deletingLastPathComponent()
            .appendingPathComponent(exportRoot.lastPathComponent)
            .appendingPathExtension("zip")
        if FileManager.default.fileExists(atPath: zipURL.path) {
            try FileManager.default.removeItem(at: zipURL)
        }
        try FileManager.default.zipItem(at: exportRoot, to: zipURL, shouldKeepParent: true)
        return zipURL
        #else
        return exportRoot
        #endif
    }
}

protocol IntakeResolutionServiceProtocol {
    func resolve(request: CaptureUploadRequest) async -> IntakeResolutionOutcome
}

final class IntakeResolutionService: IntakeResolutionServiceProtocol {
    private let inferenceService: CaptureIntakeInferenceServiceProtocol
    private let autoAcceptConfidenceThreshold: Double

    init(
        inferenceService: CaptureIntakeInferenceServiceProtocol = CaptureIntakeInferenceService(),
        autoAcceptConfidenceThreshold: Double = 0.8
    ) {
        self.inferenceService = inferenceService
        self.autoAcceptConfidenceThreshold = autoAcceptConfidenceThreshold
    }

    func resolve(request: CaptureUploadRequest) async -> IntakeResolutionOutcome {
        if request.metadata.intakePacket?.isComplete == true {
            if request.metadata.taskHypothesis?.status == .needsConfirmation {
                let draft = CaptureManualIntakeDraft(
                    workflowName: request.metadata.intakePacket?.workflowName ?? "",
                    taskStepsText: (request.metadata.intakePacket?.taskSteps ?? []).joined(separator: "\n"),
                    zone: request.metadata.intakePacket?.zone ?? "",
                    owner: request.metadata.intakePacket?.owner ?? "",
                    helperText: manualEntryHelperText(taskHypothesis: request.metadata.taskHypothesis),
                    reviewTitle: "Review AI Task Guess"
                )
                return .needsManualEntry(request: request, draft: draft)
            }
            var resolved = request
            if resolved.metadata.intakeMetadata == nil {
                resolved.metadata.intakeMetadata = CaptureIntakeMetadata(source: .authoritative)
            }
            return .resolved(resolved)
        }

        do {
            let inferred = try await inferenceService.inferIntake(for: request)
            var candidate = request
            candidate.metadata.intakePacket = inferred.intakePacket
            candidate.metadata.intakeMetadata = inferred.metadata

            let inferredConfidence = inferred.metadata.confidence ?? 0.0
            let autoAccept = inferred.intakePacket.isComplete && inferredConfidence >= autoAcceptConfidenceThreshold
            candidate.metadata.taskHypothesis = inferred.taskHypothesis.with(
                status: autoAccept ? .accepted : .needsConfirmation
            )

            if autoAccept {
                return .resolved(candidate)
            }

            let draft = CaptureManualIntakeDraft(
                workflowName: inferred.intakePacket.workflowName ?? "",
                taskStepsText: inferred.intakePacket.taskSteps.joined(separator: "\n"),
                zone: inferred.intakePacket.zone ?? "",
                owner: inferred.intakePacket.owner ?? "",
                helperText: manualEntryHelperText(taskHypothesis: candidate.metadata.taskHypothesis),
                reviewTitle: "Review AI Task Guess"
            )
            return .needsManualEntry(request: candidate, draft: draft)
        } catch {
            let helperText = inferenceFailureHelperText(for: error)
            print("🤖 [IntakeResolution] AI inference failed: \(helperText)")
            let draft = CaptureManualIntakeDraft(
                packet: request.metadata.intakePacket,
                helperText: helperText
            )
            return .needsManualEntry(request: request, draft: draft)
        }
    }

    private func manualEntryHelperText(taskHypothesis: CaptureTaskHypothesis?) -> String {
        guard let taskHypothesis else {
            return "AI intake was unavailable. Enter minimal workflow details to continue."
        }
        let workflow = taskHypothesis.workflowName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown task"
        let confidence = Int(round((taskHypothesis.confidence ?? 0.0) * 100.0))
        let warnings = taskHypothesis.warnings.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let warningText = warnings.isEmpty ? "Please confirm or edit the task before continuing." : "Warnings: " + warnings.joined(separator: " ")
        return "We think this task is '\(workflow)' (\(confidence)% confidence). \(warningText)"
    }

    private func inferenceFailureHelperText(for error: Error) -> String {
        let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        #if DEBUG
        return "AI intake failed: \(detail)"
        #else
        return "AI intake failed. \(detail) Enter minimal workflow details to continue."
        #endif
    }
}

extension CaptureUploadRequest {
    func withManualIntake(_ packet: QualificationIntakePacket) -> CaptureUploadRequest {
        var request = self
        request.metadata.intakePacket = packet
        request.metadata.intakeMetadata = CaptureIntakeMetadata(source: .humanManual)
        if let taskHypothesis = request.metadata.taskHypothesis {
            request.metadata.taskHypothesis = taskHypothesis.with(status: .accepted)
        }
        return request
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension JSONEncoder {
    static var snakeCase: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }
}

private extension Int {
    func nonZero(or fallback: Int) -> Int {
        self > 0 ? self : fallback
    }
}
