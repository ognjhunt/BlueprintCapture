// Extracted from CaptureBundleSupport.swift (behavior-preserving decomposition).
import Foundation

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
            && stableSiteIdPresent(for: request)
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
        gates.append("site_id_present:\(stableSiteIdPresent(for: request))")
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

    static func worldModelCandidateMissingReasons(
        for request: CaptureUploadRequest,
        evidence: CaptureEvidenceSummary
    ) -> [String] {
        var reasons: [String] = []
        if !stableSiteIdPresent(for: request) {
            reasons.append("missing_site_id")
        }
        if evidence.arkitPoseRows <= 0 {
            reasons.append("missing_arkit_poses")
        }
        if !evidence.arkitIntrinsicsValid {
            reasons.append("missing_arkit_intrinsics")
        }
        if evidence.arkitDepthFrames <= 0 {
            reasons.append("missing_lidar_depth")
        }
        if !evidence.poseAlignmentOK {
            reasons.append("pose_alignment_not_verified")
        }
        if request.metadata.intakePacket?.isComplete != true {
            reasons.append("missing_complete_intake")
        }
        if request.metadata.captureRights?.derivedSceneGenerationAllowed != true {
            reasons.append("derived_scene_generation_not_allowed")
        }
        return reasons
    }

    static func stableSiteIdPresent(for request: CaptureUploadRequest) -> Bool {
        let siteId = request.metadata.siteIdentity?.siteId.trimmingCharacters(in: .whitespacesAndNewlines)
        return siteId?.isEmpty == false
    }

    static func worldModelCandidateDowngradeReason(
        for request: CaptureUploadRequest,
        evidence: CaptureEvidenceSummary
    ) -> String? {
        guard request.metadata.captureMode?.requestedMode == "site_world_candidate" else {
            return nil
        }
        guard !worldModelCandidate(for: request, evidence: evidence) else {
            return nil
        }
        return worldModelCandidateMissingReasons(for: request, evidence: evidence).first
            ?? "site_world_candidate_gates_not_met"
    }

    static func rawDirectoryURL(for request: CaptureUploadRequest) -> URL {
        request.packageURL
    }
}
