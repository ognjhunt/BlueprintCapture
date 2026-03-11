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

    static func captureModality(for request: CaptureUploadRequest) -> String {
        if let explicit = request.metadata.captureModality?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explicit.isEmpty {
            return explicit
        }
        if request.metadata.captureSource == .iphoneVideo {
            return "iphone_arkit_lidar"
        }
        if !(request.metadata.scaffoldingPacket?.scaffoldingUsed ?? []).isEmpty {
            return "glasses_plus_scaffolding"
        }
        return "glasses_video_only"
    }

    static func evidenceTier(for request: CaptureUploadRequest) -> String {
        if let explicit = request.metadata.evidenceTier?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explicit.isEmpty {
            return explicit
        }
        let intakeComplete = request.metadata.intakePacket?.isComplete == true
        if request.metadata.captureSource == .iphoneVideo && intakeComplete {
            return "qualified_metric_capture"
        }
        if request.metadata.captureSource == .metaGlasses,
           request.metadata.scaffoldingPacket?.hasValidatedMetricBundle == true,
           intakeComplete {
            return "glasses_with_validated_scaffolding"
        }
        return "pre_screen_video"
    }

    static func worldModelCandidate(for request: CaptureUploadRequest) -> Bool {
        guard let continuityScore = request.metadata.sceneMemory?.continuityScore else {
            return false
        }
        return continuityScore >= 0.5
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
        let captureSource: String
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
        let sceneMemory: SceneMemoryCaptureMetadata
        let captureRights: CaptureRightsMetadata
        let worldModelCandidate: Bool
        let capturedAt: String
    }

    private struct UploadCompletionFile: Codable {
        let schemaVersion: String
        let sceneId: String
        let captureId: String
        let rawPrefix: String
        let completedAt: String
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

    private func sensorAvailability(for request: CaptureUploadRequest, directory: URL) -> [String: Bool] {
        let motion = fileManager.fileExists(atPath: directory.appendingPathComponent("motion.jsonl").path)
        guard request.metadata.captureSource == .iphoneVideo else {
            return [
                "arkit_poses": false,
                "arkit_intrinsics": false,
                "arkit_depth": false,
                "arkit_confidence": false,
                "arkit_meshes": false,
                "motion": motion,
            ]
        }

        return [
            "arkit_poses": fileManager.fileExists(atPath: directory.appendingPathComponent("arkit/poses.jsonl").path),
            "arkit_intrinsics": fileManager.fileExists(atPath: directory.appendingPathComponent("arkit/intrinsics.json").path),
            "arkit_depth": fileManager.fileExists(atPath: directory.appendingPathComponent("arkit/depth").path),
            "arkit_confidence": fileManager.fileExists(atPath: directory.appendingPathComponent("arkit/confidence").path),
            "arkit_meshes": fileManager.fileExists(atPath: directory.appendingPathComponent("arkit/meshes").path),
            "motion": motion,
        ]
    }

    private func manifestSceneMemory(
        for request: CaptureUploadRequest,
        directory: URL,
        normalized: SceneMemoryCaptureMetadata
    ) -> [String: Any] {
        [
            "continuity_score": normalized.continuityScore as Any,
            "lighting_consistency": normalized.lightingConsistency ?? "unknown",
            "dynamic_object_density": normalized.dynamicObjectDensity ?? "unknown",
            "sensor_availability": sensorAvailability(for: request, directory: directory),
            "operator_notes": normalized.operatorNotes,
            "inaccessible_areas": normalized.inaccessibleAreas,
            "world_model_candidate": CaptureBundleContext.worldModelCandidate(for: request),
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
        json["scene_id"] = sceneId
        json["capture_id"] = captureId
        json["site_submission_id"] = request.metadata.jobId
        json["capture_modality"] = CaptureBundleContext.captureModality(for: request)
        json["evidence_tier"] = CaptureBundleContext.evidenceTier(for: request)
        json["scaffolding_used"] = request.metadata.scaffoldingPacket?.scaffoldingUsed ?? []
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
            directory: directory,
            normalized: normalizedSceneMemory
        )
        json["task_text_hint"] = request.metadata.taskHypothesis?.workflowName ?? request.metadata.intakePacket?.workflowName
        json["task_steps"] = request.metadata.taskHypothesis?.taskSteps ?? request.metadata.intakePacket?.taskSteps ?? []
        json["capture_rights"] = manifestCaptureRights(normalizedRights)
        json["video_uri"] = mode.videoURI

        let patched = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .withoutEscapingSlashes])
        try patched.write(to: manifestURL, options: .atomic)
    }

    private func materializeSupplementalFiles(in directory: URL, request: CaptureUploadRequest, mode: CaptureBundleFinalizationMode) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]

        if let intakePacket = request.metadata.intakePacket {
            let intakeURL = directory.appendingPathComponent("intake_packet.json")
            try encoder.encode(intakePacket).write(to: intakeURL, options: .atomic)
        }

        let intakeMetadata = request.metadata.intakeMetadata
        let normalizedSceneMemory = normalizedSceneMemory(for: request, directory: directory)
        let normalizedRights = normalizedCaptureRights(for: request)
        let context = CaptureContextFile(
            schemaVersion: "v1",
            sceneId: CaptureBundleContext.sceneIdentifier(for: request),
            captureId: CaptureBundleContext.captureIdentifier(for: request),
            siteSubmissionId: request.metadata.jobId,
            captureSource: request.metadata.captureSource.rawValue,
            captureModality: CaptureBundleContext.captureModality(for: request),
            evidenceTier: CaptureBundleContext.evidenceTier(for: request),
            scaffoldingUsed: request.metadata.scaffoldingPacket?.scaffoldingUsed ?? [],
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
            taskHypothesisStatus: request.metadata.taskHypothesis?.status.rawValue,
            taskTextHint: request.metadata.taskHypothesis?.workflowName ?? request.metadata.intakePacket?.workflowName,
            taskSteps: request.metadata.taskHypothesis?.taskSteps ?? request.metadata.intakePacket?.taskSteps ?? [],
            sceneMemory: normalizedSceneMemory,
            captureRights: normalizedRights,
            worldModelCandidate: CaptureBundleContext.worldModelCandidate(for: request),
            capturedAt: ISO8601DateFormatter().string(from: request.metadata.capturedAt)
        )
        let contextURL = directory.appendingPathComponent("capture_context.json")
        try encoder.encode(context).write(to: contextURL, options: .atomic)

        if let taskHypothesis = request.metadata.taskHypothesis {
            let taskHypothesisURL = directory.appendingPathComponent(taskHypothesisFilename)
            try encoder.encode(taskHypothesis).write(to: taskHypothesisURL, options: .atomic)
        }

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
