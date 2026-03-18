import Foundation
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

    var hasUsableARKitBundle: Bool {
        arkitPoseRows > 0 && arkitIntrinsicsValid
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
        if !(request.metadata.scaffoldingPacket?.scaffoldingUsed ?? []).isEmpty {
            return "glasses_plus_scaffolding"
        }
        return "glasses_video_only"
    }

    static func evidenceTier(for request: CaptureUploadRequest, evidence: CaptureEvidenceSummary) -> String {
        let intakeComplete = request.metadata.intakePacket?.isComplete == true
        if request.metadata.captureSource == .iphoneVideo && intakeComplete && evidence.hasUsableARKitBundle {
            return "qualified_metric_capture"
        }
        if request.metadata.captureSource == .metaGlasses,
           request.metadata.scaffoldingPacket?.hasValidatedMetricBundle == true,
           intakeComplete {
            return "glasses_with_validated_scaffolding"
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
        var gates: [String] = []
        gates.append("capture_mode_site_world_candidate:\(captureMode?.resolvedMode == "site_world_candidate")")
        gates.append("arkit_poses_valid:\(evidence.arkitPoseRows > 0)")
        gates.append("arkit_intrinsics_valid:\(evidence.arkitIntrinsicsValid)")
        gates.append("depth_coverage_ok:\(evidence.arkitDepthFrames > 0)")
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
        let worldModelCandidate: Bool
        let worldModelCandidateReasoning: [String]
        let siteIdentity: SiteIdentity?
        let captureTopology: CaptureTopologyMetadata?
        let captureMode: CaptureModeMetadata?
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

    private let completionMarkerFilename = "capture_upload_complete.json"
    private let taskHypothesisFilename = "task_hypothesis.json"
    private let fileManager = FileManager.default

    func finalize(request: CaptureUploadRequest, mode: CaptureBundleFinalizationMode) throws -> FinalizedCaptureBundle {
        guard request.metadata.intakePacket?.isComplete == true else {
            throw FinalizationError.missingStructuredIntake
        }

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
            inaccessibleAreas: metadata?.inaccessibleAreas ?? []
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
        let posesURL = arkitDirectory.appendingPathComponent("poses.jsonl")
        let framesURL = arkitDirectory.appendingPathComponent("frames.jsonl")
        let intrinsicsURL = arkitDirectory.appendingPathComponent("intrinsics.json")
        let motionURL = directory.appendingPathComponent("motion.jsonl")

        let motion = inspectMotionMetadata(at: motionURL, captureSource: request.metadata.captureSource)
        return CaptureEvidenceSummary(
            arkitFrameRows: countJSONLines(in: framesURL),
            arkitPoseRows: countJSONLines(in: posesURL),
            arkitIntrinsicsValid: isValidIntrinsicsFile(at: intrinsicsURL),
            arkitDepthFrames: countFiles(in: arkitDirectory.appendingPathComponent("depth", isDirectory: true), extensions: ["png"]),
            arkitConfidenceFrames: countFiles(in: arkitDirectory.appendingPathComponent("confidence", isDirectory: true), extensions: ["png"]),
            arkitMeshFiles: countFiles(in: arkitDirectory.appendingPathComponent("meshes", isDirectory: true), extensions: ["obj"]),
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
        [
            "continuity_score": normalized.continuityScore as Any,
            "lighting_consistency": normalized.lightingConsistency ?? "unknown",
            "dynamic_object_density": normalized.dynamicObjectDensity ?? "unknown",
            "sensor_availability": evidence.sensorAvailability,
            "operator_notes": normalized.operatorNotes,
            "inaccessible_areas": normalized.inaccessibleAreas,
            "world_model_candidate": CaptureBundleContext.worldModelCandidate(for: request, evidence: evidence),
            "world_model_candidate_reasoning": CaptureBundleContext.worldModelCandidateReasoning(for: request, evidence: evidence),
            "motion_provenance": evidence.motionProvenance as Any,
            "motion_timestamps_capture_relative": evidence.motionTimestampsCaptureRelative,
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

        // Site identity, topology, and capture mode blocks.
        if let siteIdentity = request.metadata.siteIdentity {
            json["site_identity"] = try JSONSerialization.jsonObject(with: JSONEncoder.snakeCase.encode(siteIdentity))
        }
        if let topology = request.metadata.captureTopology {
            json["capture_topology"] = try JSONSerialization.jsonObject(with: JSONEncoder.snakeCase.encode(topology))
        }
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
        let derivedScaffolding = Array(Set((request.metadata.scaffoldingPacket?.scaffoldingUsed ?? []).filter { !$0.hasPrefix("arkit_") } + evidence.derivedScaffoldingUsed)).sorted()

        if let intakePacket = request.metadata.intakePacket {
            let intakeURL = directory.appendingPathComponent("intake_packet.json")
            try encoder.encode(intakePacket).write(to: intakeURL, options: .atomic)
        }

        let intakeMetadata = request.metadata.intakeMetadata
        let normalizedSceneMemory = normalizedSceneMemory(for: request, directory: directory)
        let normalizedRights = normalizedCaptureRights(for: request)
        let taskHypothesis = request.metadata.taskHypothesis ?? synthesizedTaskHypothesis(for: request)
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
            worldModelCandidate: CaptureBundleContext.worldModelCandidate(for: request, evidence: evidence),
            worldModelCandidateReasoning: CaptureBundleContext.worldModelCandidateReasoning(for: request, evidence: evidence),
            siteIdentity: request.metadata.siteIdentity,
            captureTopology: request.metadata.captureTopology,
            captureMode: request.metadata.captureMode,
            capturedAt: ISO8601DateFormatter().string(from: request.metadata.capturedAt)
        )
        let contextURL = directory.appendingPathComponent("capture_context.json")
        try encoder.encode(context).write(to: contextURL, options: .atomic)

        // Write standalone site_identity.json for pipeline and bridge consumption.
        if let siteIdentity = request.metadata.siteIdentity {
            let siteIdentityURL = directory.appendingPathComponent("site_identity.json")
            try encoder.encode(siteIdentity).write(to: siteIdentityURL, options: .atomic)
        }

        // Write standalone capture_topology.json.
        if let topology = request.metadata.captureTopology {
            let topologyURL = directory.appendingPathComponent("capture_topology.json")
            try encoder.encode(topology).write(to: topologyURL, options: .atomic)
        }

        // Write route_anchors.json — fixed v1 entry anchor definition.
        let routeAnchors = RouteAnchorsFile(
            schemaVersion: "v1",
            routeAnchors: [
                RouteAnchorsFile.RouteAnchor(
                    anchorId: "anchor_entry",
                    anchorType: "entry",
                    label: "Site entry point",
                    expectedObservation: "pause_and_pan",
                    requiredInPrimaryPass: true,
                    requiredInRevisitPass: true
                )
            ]
        )
        let routeAnchorsURL = directory.appendingPathComponent("route_anchors.json")
        try encoder.encode(routeAnchors).write(to: routeAnchorsURL, options: .atomic)

        // Write checkpoint_events.json — one event if entry hold was detected, else empty.
        let topology = request.metadata.captureTopology
        var checkpointEvents: [CheckpointEventsFile.CheckpointEvent] = []
        if let passId = topology?.passId,
           let tCaptureSec = topology?.entryAnchorTCaptureSec,
           let holdDuration = topology?.entryAnchorHoldDurationSec {
            checkpointEvents.append(CheckpointEventsFile.CheckpointEvent(
                anchorId: "anchor_entry",
                passId: passId,
                tCaptureSec: tCaptureSec,
                holdDurationSec: holdDuration,
                completed: true
            ))
        }
        let checkpointEventsFile = CheckpointEventsFile(
            schemaVersion: "v1",
            checkpointEvents: checkpointEvents
        )
        let checkpointEventsURL = directory.appendingPathComponent("checkpoint_events.json")
        try encoder.encode(checkpointEventsFile).write(to: checkpointEventsURL, options: .atomic)

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
    }

    private func synthesizedTaskHypothesis(for request: CaptureUploadRequest) -> CaptureTaskHypothesis {
        let packet = request.metadata.intakePacket ?? QualificationIntakePacket()
        let metadata = request.metadata.intakeMetadata ?? CaptureIntakeMetadata(source: .authoritative)
        return CaptureTaskHypothesis(packet: packet, metadata: metadata, status: .accepted)
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
