// Extracted from CaptureBundleSupport.swift (behavior-preserving decomposition).
import Foundation

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

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

    /// Returns a copy of this mode with the videoURI corrected to match the actual
    /// on-disk video file extension (.mov or .mp4). Falls back to the existing
    /// videoURI if neither file is found.
    func resolvingVideoExtension(in directory: URL) -> CaptureBundleFinalizationMode {
        let fm = FileManager.default
        let uri = URL(fileURLWithPath: videoURI)
        let baseName = uri.lastPathComponent
        let baseWithoutExt = (baseName as NSString).deletingPathExtension
        let uriDirectory = uri.deletingLastPathComponent().relativePath
        let uriPrefix = uriDirectory == "." ? "" : uriDirectory

        let movURL = directory.appendingPathComponent(baseWithoutExt + ".mov")
        let mp4URL = directory.appendingPathComponent(baseWithoutExt + ".mp4")

        let actualVideo: String
        let uriForFileName: (String) -> String = { fileName in
            uriPrefix.isEmpty ? fileName : (uriPrefix as NSString).appendingPathComponent(fileName)
        }
        if fm.fileExists(atPath: mp4URL.path) {
            actualVideo = uriForFileName(baseWithoutExt + ".mp4")
        } else if fm.fileExists(atPath: movURL.path) {
            actualVideo = uriForFileName(baseWithoutExt + ".mov")
        } else {
            return self  // Neither exists — keep the caller-provided URI
        }

        switch self {
        case .upload(let prefix, _):
            // For upload mode, preserve the remote prefix but fix the extension
            let remoteFileName = (prefix as NSString).appendingPathComponent(baseWithoutExt + (actualVideo.hasSuffix(".mp4") ? ".mp4" : ".mov"))
            return .upload(remoteRawPrefix: prefix, videoURI: remoteFileName)
        case .localExport(let localRawPrefix, _):
            return .localExport(localRawPrefix: localRawPrefix, videoURI: actualVideo)
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

struct CaptureEvidenceSummary: Equatable, Encodable {
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
    let declaredDepthSupported: Bool

    enum CodingKeys: String, CodingKey {
        case arkitFrameRows
        case arkitPoseRows
        case arkitIntrinsicsValid
        case arkitDepthFrames
        case arkitConfidenceFrames
        case arkitMeshFiles
        case arkitFeaturePointRows
        case arkitPlaneRows
        case arkitTrackingStateRows
        case arkitRelocalizationEventRows
        case arkitLightEstimateRows
        case arcoreFrameRows
        case arcorePoseRows
        case arcoreIntrinsicsValid
        case arcoreDepthFrames
        case arcoreConfidenceFrames
        case arcorePointCloudSamples
        case arcorePlaneRows
        case arcoreTrackingStateRows
        case arcoreLightEstimateRows
        case glassesFrameTimestampRows
        case glassesDeviceStateRows
        case glassesHealthEventRows
        case companionPhonePoseRows
        case companionPhoneIntrinsicsValid
        case companionPhoneCalibrationPresent
        case poseMatchRate
        case p95PoseDeltaSec
        case motionSamples
        case motionProvenance
        case motionTimestampsCaptureRelative
        case declaredDepthSupported
        case poseAuthority
        case intrinsicsAuthority
        case depthAuthority
        case motionAuthority
        case geometrySource
        case geometryExpectedDownstream
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(arkitFrameRows, forKey: .arkitFrameRows)
        try container.encode(arkitPoseRows, forKey: .arkitPoseRows)
        try container.encode(arkitIntrinsicsValid, forKey: .arkitIntrinsicsValid)
        try container.encode(arkitDepthFrames, forKey: .arkitDepthFrames)
        try container.encode(arkitConfidenceFrames, forKey: .arkitConfidenceFrames)
        try container.encode(arkitMeshFiles, forKey: .arkitMeshFiles)
        try container.encode(arkitFeaturePointRows, forKey: .arkitFeaturePointRows)
        try container.encode(arkitPlaneRows, forKey: .arkitPlaneRows)
        try container.encode(arkitTrackingStateRows, forKey: .arkitTrackingStateRows)
        try container.encode(arkitRelocalizationEventRows, forKey: .arkitRelocalizationEventRows)
        try container.encode(arkitLightEstimateRows, forKey: .arkitLightEstimateRows)
        try container.encode(arcoreFrameRows, forKey: .arcoreFrameRows)
        try container.encode(arcorePoseRows, forKey: .arcorePoseRows)
        try container.encode(arcoreIntrinsicsValid, forKey: .arcoreIntrinsicsValid)
        try container.encode(arcoreDepthFrames, forKey: .arcoreDepthFrames)
        try container.encode(arcoreConfidenceFrames, forKey: .arcoreConfidenceFrames)
        try container.encode(arcorePointCloudSamples, forKey: .arcorePointCloudSamples)
        try container.encode(arcorePlaneRows, forKey: .arcorePlaneRows)
        try container.encode(arcoreTrackingStateRows, forKey: .arcoreTrackingStateRows)
        try container.encode(arcoreLightEstimateRows, forKey: .arcoreLightEstimateRows)
        try container.encode(glassesFrameTimestampRows, forKey: .glassesFrameTimestampRows)
        try container.encode(glassesDeviceStateRows, forKey: .glassesDeviceStateRows)
        try container.encode(glassesHealthEventRows, forKey: .glassesHealthEventRows)
        try container.encode(companionPhonePoseRows, forKey: .companionPhonePoseRows)
        try container.encode(companionPhoneIntrinsicsValid, forKey: .companionPhoneIntrinsicsValid)
        try container.encode(companionPhoneCalibrationPresent, forKey: .companionPhoneCalibrationPresent)
        try container.encodeIfPresent(poseMatchRate, forKey: .poseMatchRate)
        try container.encodeIfPresent(p95PoseDeltaSec, forKey: .p95PoseDeltaSec)
        try container.encode(motionSamples, forKey: .motionSamples)
        try container.encodeIfPresent(motionProvenance, forKey: .motionProvenance)
        try container.encode(motionTimestampsCaptureRelative, forKey: .motionTimestampsCaptureRelative)
        try container.encode(declaredDepthSupported, forKey: .declaredDepthSupported)

        let capabilities = captureCapabilities
        try container.encode(capabilities.poseAuthority, forKey: .poseAuthority)
        try container.encode(capabilities.intrinsicsAuthority, forKey: .intrinsicsAuthority)
        try container.encode(capabilities.depthAuthority, forKey: .depthAuthority)
        try container.encode(capabilities.motionAuthority, forKey: .motionAuthority)
        try container.encodeIfPresent(capabilities.geometrySource, forKey: .geometrySource)
        try container.encode(capabilities.geometryExpectedDownstream, forKey: .geometryExpectedDownstream)
    }

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
        let missingDepthReason = hasDepth
            ? nil
            : declaredDepthSupported
            ? "not_enabled"
            : "not_supported"
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
            missingDepthReason: missingDepthReason,
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
