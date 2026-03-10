import Foundation
#if canImport(ZIPFoundation)
import ZIPFoundation
#endif

enum CaptureIntakeSource: String, Codable {
    case authoritative
    case humanManual = "human_manual"
    case aiInferred = "ai_inferred"
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

    init(
        id: UUID = UUID(),
        workflowName: String = "",
        taskStepsText: String = "",
        zone: String = "",
        owner: String = "",
        helperText: String = "Add a workflow name, at least one task step, and either a zone or owner."
    ) {
        self.id = id
        self.workflowName = workflowName
        self.taskStepsText = taskStepsText
        self.zone = zone
        self.owner = owner
        self.helperText = helperText
    }

    init(packet: QualificationIntakePacket?, helperText: String) {
        self.init(
            workflowName: packet?.workflowName ?? "",
            taskStepsText: (packet?.taskSteps ?? []).joined(separator: "\n"),
            zone: packet?.zone ?? "",
            owner: packet?.owner ?? "",
            helperText: helperText
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

    private func patchManifest(in directory: URL, request: CaptureUploadRequest, mode: CaptureBundleFinalizationMode) throws {
        let manifestURL = directory.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            return
        }

        let sceneId = CaptureBundleContext.sceneIdentifier(for: request)
        let captureId = CaptureBundleContext.captureIdentifier(for: request)
        let data = try Data(contentsOf: manifestURL)
        var json = (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        json["scene_id"] = sceneId
        json["capture_id"] = captureId
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
        let context = CaptureContextFile(
            schemaVersion: "v1",
            sceneId: CaptureBundleContext.sceneIdentifier(for: request),
            captureId: CaptureBundleContext.captureIdentifier(for: request),
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
            capturedAt: ISO8601DateFormatter().string(from: request.metadata.capturedAt)
        )
        let contextURL = directory.appendingPathComponent("capture_context.json")
        try encoder.encode(context).write(to: contextURL, options: .atomic)

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

    init(inferenceService: CaptureIntakeInferenceServiceProtocol = CaptureIntakeInferenceService()) {
        self.inferenceService = inferenceService
    }

    func resolve(request: CaptureUploadRequest) async -> IntakeResolutionOutcome {
        if request.metadata.intakePacket?.isComplete == true {
            var resolved = request
            if resolved.metadata.intakeMetadata == nil {
                resolved.metadata.intakeMetadata = CaptureIntakeMetadata(source: .authoritative)
            }
            return .resolved(resolved)
        }

        do {
            let inferred = try await inferenceService.inferIntake(for: request)
            var resolved = request
            resolved.metadata.intakePacket = inferred.intakePacket
            resolved.metadata.intakeMetadata = inferred.metadata
            return .resolved(resolved)
        } catch {
            let draft = CaptureManualIntakeDraft(
                packet: request.metadata.intakePacket,
                helperText: "AI intake was unavailable. Enter minimal workflow details to continue."
            )
            return .needsManualEntry(request: request, draft: draft)
        }
    }
}

extension CaptureUploadRequest {
    func withManualIntake(_ packet: QualificationIntakePacket) -> CaptureUploadRequest {
        var request = self
        request.metadata.intakePacket = packet
        request.metadata.intakeMetadata = CaptureIntakeMetadata(source: .humanManual)
        return request
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
