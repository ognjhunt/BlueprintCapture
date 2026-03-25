import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

struct CaptureRawContractV3ValidationResult: Equatable {
    let isValid: Bool
    let errors: [String]
    let warnings: [String]
}

final class CaptureRawContractV3Validator {
    func validate(rawDirectoryURL: URL) -> CaptureRawContractV3ValidationResult {
        var errors: [String] = []
        var warnings: [String] = []

        let manifest = loadJSONObject(at: rawDirectoryURL.appendingPathComponent("manifest.json"), errors: &errors)
        guard let manifest else {
            return CaptureRawContractV3ValidationResult(isValid: false, errors: errors, warnings: warnings)
        }

        if !isCanonicalV3Manifest(manifest) {
            errors.append("manifest_not_v3")
        }

        validateRequiredManifestFields(manifest, errors: &errors)

        let requiredBaseFiles = [
            "manifest.json",
            "provenance.json",
            "rights_consent.json",
            "capture_context.json",
            "intake_packet.json",
            "task_hypothesis.json",
            "recording_session.json",
            "capture_topology.json",
            "route_anchors.json",
            "checkpoint_events.json",
            "relocalization_events.json",
            "overlap_graph.json",
            "video_track.json",
            "hashes.json",
            "capture_upload_complete.json",
            "sync_map.jsonl",
            "motion.jsonl",
            "semantic_anchor_observations.jsonl",
        ]
        for path in requiredBaseFiles {
            if !FileManager.default.fileExists(atPath: rawDirectoryURL.appendingPathComponent(path).path) {
                errors.append("missing_required_file:\(path)")
            }
        }

        if !hasCanonicalVideo(in: rawDirectoryURL, manifest: manifest) {
            errors.append("missing_required_file:walkthrough")
        }

        let profileId = manifest["capture_profile_id"] as? String ?? ""
        let captureSource = manifest["capture_source"] as? String ?? "unknown"
        let captureCapabilities = manifest["capture_capabilities"] as? [String: Any] ?? [:]
        let arkitRequired = captureSource == "iphone" || profileId.hasPrefix("iphone_arkit") || fileExists(rawDirectoryURL, "arkit/poses.jsonl")
        let arcoreRequired = captureSource == "android" && (
            profileId.hasPrefix("android_arcore")
                || capability(captureCapabilities, key: "camera_pose")
                || fileExists(rawDirectoryURL, "arcore/poses.jsonl")
        )
        let glassesRequired = captureSource == "glasses" || profileId.hasPrefix("glasses_")
        let companionPhoneRequired =
            capability(captureCapabilities, key: "companion_phone_pose")
            || capability(captureCapabilities, key: "companion_phone_intrinsics")
            || capability(captureCapabilities, key: "companion_phone_calibration")
            || fileExists(rawDirectoryURL, "companion_phone/poses.jsonl")

        if arkitRequired {
            requireFiles(
                [
                    "arkit/poses.jsonl",
                    "arkit/frames.jsonl",
                    "arkit/frame_quality.jsonl",
                    "arkit/per_frame_camera_state.jsonl",
                    "arkit/session_intrinsics.json",
                ],
                in: rawDirectoryURL,
                errors: &errors
            )
            if capability(captureCapabilities, key: "depth") || manifest["depth_supported"] as? Bool == true {
                requireFiles(["arkit/depth_manifest.json"], in: rawDirectoryURL, errors: &errors)
            }
            if capability(captureCapabilities, key: "depth_confidence") || manifest["depth_supported"] as? Bool == true {
                requireFiles(["arkit/confidence_manifest.json"], in: rawDirectoryURL, errors: &errors)
            }
            if capability(captureCapabilities, key: "feature_points") {
                requireFiles(["arkit/feature_points.jsonl"], in: rawDirectoryURL, errors: &errors)
            }
            if capability(captureCapabilities, key: "planes") {
                requireFiles(["arkit/plane_observations.jsonl"], in: rawDirectoryURL, errors: &errors)
            }
            if capability(captureCapabilities, key: "light_estimate") {
                requireFiles(["arkit/light_estimates.jsonl"], in: rawDirectoryURL, errors: &errors)
            }
        }

        if arcoreRequired {
            requireFiles(
                [
                    "arcore/poses.jsonl",
                    "arcore/frames.jsonl",
                    "arcore/session_intrinsics.json",
                    "arcore/tracking_state.jsonl",
                ],
                in: rawDirectoryURL,
                errors: &errors
            )
            if capability(captureCapabilities, key: "point_cloud") {
                requireFiles(["arcore/point_cloud.jsonl"], in: rawDirectoryURL, errors: &errors)
            }
            if capability(captureCapabilities, key: "planes") {
                requireFiles(["arcore/planes.jsonl"], in: rawDirectoryURL, errors: &errors)
            }
            if capability(captureCapabilities, key: "light_estimate") {
                requireFiles(["arcore/light_estimates.jsonl"], in: rawDirectoryURL, errors: &errors)
            }
            if capability(captureCapabilities, key: "depth") {
                requireFiles(["arcore/depth_manifest.json"], in: rawDirectoryURL, errors: &errors)
            }
            if capability(captureCapabilities, key: "depth_confidence") {
                requireFiles(["arcore/confidence_manifest.json"], in: rawDirectoryURL, errors: &errors)
            }
        }

        if glassesRequired {
            requireFiles(
                [
                    "glasses/stream_metadata.json",
                    "glasses/frame_timestamps.jsonl",
                    "glasses/device_state.jsonl",
                    "glasses/health_events.jsonl",
                ],
                in: rawDirectoryURL,
                errors: &errors
            )
        }

        if companionPhoneRequired {
            if capability(captureCapabilities, key: "companion_phone_pose") || fileExists(rawDirectoryURL, "companion_phone/poses.jsonl") {
                requireFiles(["companion_phone/poses.jsonl"], in: rawDirectoryURL, errors: &errors)
            }
            if capability(captureCapabilities, key: "companion_phone_intrinsics") || fileExists(rawDirectoryURL, "companion_phone/session_intrinsics.json") {
                requireFiles(["companion_phone/session_intrinsics.json"], in: rawDirectoryURL, errors: &errors)
            }
            if capability(captureCapabilities, key: "companion_phone_calibration") || fileExists(rawDirectoryURL, "companion_phone/calibration.json") {
                requireFiles(["companion_phone/calibration.json"], in: rawDirectoryURL, errors: &errors)
            }
        }

        let provenance = loadJSONObject(at: rawDirectoryURL.appendingPathComponent("provenance.json"), errors: &errors)
        let rightsConsent = loadJSONObject(at: rawDirectoryURL.appendingPathComponent("rights_consent.json"), errors: &errors)
        let captureContext = loadJSONObject(at: rawDirectoryURL.appendingPathComponent("capture_context.json"), errors: &errors)
        let recordingSession = loadJSONObject(at: rawDirectoryURL.appendingPathComponent("recording_session.json"), errors: &errors)
        let captureTopology = loadJSONObject(at: rawDirectoryURL.appendingPathComponent("capture_topology.json"), errors: &errors)
        let completion = loadJSONObject(at: rawDirectoryURL.appendingPathComponent("capture_upload_complete.json"), errors: &errors)
        let hashes = loadJSONObject(at: rawDirectoryURL.appendingPathComponent("hashes.json"), errors: &errors)
        let depthManifest = loadJSONObjectIfPresent(at: rawDirectoryURL.appendingPathComponent("arkit/depth_manifest.json"), errors: &errors)
        let confidenceManifest = loadJSONObjectIfPresent(at: rawDirectoryURL.appendingPathComponent("arkit/confidence_manifest.json"), errors: &errors)
        let sessionIntrinsics = loadJSONObjectIfPresent(at: rawDirectoryURL.appendingPathComponent("arkit/session_intrinsics.json"), errors: &errors)
        let arcoreDepthManifest = loadJSONObjectIfPresent(at: rawDirectoryURL.appendingPathComponent("arcore/depth_manifest.json"), errors: &errors)
        let arcoreConfidenceManifest = loadJSONObjectIfPresent(at: rawDirectoryURL.appendingPathComponent("arcore/confidence_manifest.json"), errors: &errors)
        let arcoreSessionIntrinsics = loadJSONObjectIfPresent(at: rawDirectoryURL.appendingPathComponent("arcore/session_intrinsics.json"), errors: &errors)
        let companionPhoneIntrinsics = loadJSONObjectIfPresent(at: rawDirectoryURL.appendingPathComponent("companion_phone/session_intrinsics.json"), errors: &errors)

        let poses = loadJSONLinesIfPresent(at: rawDirectoryURL.appendingPathComponent("arkit/poses.jsonl"), errors: &errors)
        let frames = loadJSONLinesIfPresent(at: rawDirectoryURL.appendingPathComponent("arkit/frames.jsonl"), errors: &errors)
        let frameQuality = loadJSONLinesIfPresent(at: rawDirectoryURL.appendingPathComponent("arkit/frame_quality.jsonl"), errors: &errors)
        let arcorePoses = loadJSONLinesIfPresent(at: rawDirectoryURL.appendingPathComponent("arcore/poses.jsonl"), errors: &errors)
        let arcoreFrames = loadJSONLinesIfPresent(at: rawDirectoryURL.appendingPathComponent("arcore/frames.jsonl"), errors: &errors)
        let arcoreTracking = loadJSONLinesIfPresent(at: rawDirectoryURL.appendingPathComponent("arcore/tracking_state.jsonl"), errors: &errors)
        let companionPhonePoses = loadJSONLinesIfPresent(at: rawDirectoryURL.appendingPathComponent("companion_phone/poses.jsonl"), errors: &errors)
        let syncMap = loadJSONLines(at: rawDirectoryURL.appendingPathComponent("sync_map.jsonl"), errors: &errors)

        validateIdentityConsistency(
            sceneId: manifest["scene_id"] as? String,
            captureId: manifest["capture_id"] as? String,
            objects: [
                ("provenance", provenance),
                ("rights_consent", rightsConsent),
                ("capture_context", captureContext),
                ("recording_session", recordingSession),
                ("capture_upload_complete", completion),
            ],
            errors: &errors
        )

        validateRecordingSession(
            recordingSession,
            captureCapabilities: captureCapabilities,
            hasPoseWorldTracking: !poses.isEmpty || !arcorePoses.isEmpty || !companionPhonePoses.isEmpty,
            errors: &errors
        )

        let manifestCfs = manifest["coordinate_frame_session_id"] as? String
        let sessionCfs = recordingSession?["coordinate_frame_session_id"] as? String
        let topologyCfs = captureTopology?["coordinate_frame_session_id"] as? String
        let intrinsicsCfs = sessionIntrinsics?["coordinate_frame_session_id"] as? String
        let arcoreIntrinsicsCfs = arcoreSessionIntrinsics?["coordinate_frame_session_id"] as? String
        let companionIntrinsicsCfs = companionPhoneIntrinsics?["coordinate_frame_session_id"] as? String
        let expectedCfs = manifestCfs ?? sessionCfs ?? topologyCfs ?? intrinsicsCfs ?? arcoreIntrinsicsCfs ?? companionIntrinsicsCfs
        for (label, value) in [
            ("manifest", manifestCfs),
            ("recording_session", sessionCfs),
            ("capture_topology", topologyCfs),
            ("session_intrinsics", intrinsicsCfs),
            ("arcore_session_intrinsics", arcoreIntrinsicsCfs),
            ("companion_phone_intrinsics", companionIntrinsicsCfs),
        ] {
            if let expectedCfs, let value, value != expectedCfs {
                errors.append("coordinate_frame_session_mismatch:\(label)")
            }
        }

        validateFrameIdsAndTime(label: "poses", rows: poses, frameIdKey: "frame_id", timeKey: "t_capture_sec", errors: &errors)
        validateFrameIdsAndTime(label: "frames", rows: frames, frameIdKey: "frame_id", timeKey: "t_capture_sec", errors: &errors)
        validateFrameIdsAndTime(label: "frame_quality", rows: frameQuality, frameIdKey: "frame_id", timeKey: "t_capture_sec", errors: &errors)
        validateFrameIdsAndTime(label: "arcore_poses", rows: arcorePoses, frameIdKey: "frame_id", timeKey: "t_capture_sec", errors: &errors)
        validateFrameIdsAndTime(label: "arcore_frames", rows: arcoreFrames, frameIdKey: "frame_id", timeKey: "t_capture_sec", errors: &errors)
        validateFrameIdsAndTime(label: "arcore_tracking_state", rows: arcoreTracking, frameIdKey: "frame_id", timeKey: "t_capture_sec", errors: &errors)
        validateFrameIdsAndTime(label: "companion_phone_poses", rows: companionPhonePoses, frameIdKey: "frame_id", timeKey: "t_capture_sec", errors: &errors)
        validateFrameIdsAndTime(label: "sync_map", rows: syncMap, frameIdKey: "frame_id", timeKey: "t_capture_sec", errors: &errors)

        if (!poses.isEmpty || !arcorePoses.isEmpty || !companionPhonePoses.isEmpty) && syncMap.isEmpty {
            errors.append("sync_map_missing_rows")
        }

        for pose in poses + arcorePoses + companionPhonePoses {
            guard let frameId = pose["frame_id"] as? String else { continue }
            if !isValidTransformMatrix(pose["T_world_camera"]) {
                errors.append("invalid_transform_matrix:\(frameId)")
            }
            if let poseCfs = pose["coordinate_frame_session_id"] as? String, let expectedCfs, poseCfs != expectedCfs {
                errors.append("coordinate_frame_session_mismatch:pose:\(frameId)")
            }
        }

        validateReferencedArtifacts(
            manifest: depthManifest,
            rowArrayKey: "frames",
            pathKeys: ["depth_path", "paired_confidence_path"],
            baseDirectory: rawDirectoryURL,
            errors: &errors
        )
        validateReferencedArtifacts(
            manifest: confidenceManifest,
            rowArrayKey: "frames",
            pathKeys: ["confidence_path", "paired_depth_path"],
            baseDirectory: rawDirectoryURL,
            errors: &errors
        )
        validateReferencedArtifacts(
            manifest: arcoreDepthManifest,
            rowArrayKey: "frames",
            pathKeys: ["depth_path", "paired_confidence_path"],
            baseDirectory: rawDirectoryURL,
            errors: &errors
        )
        validateReferencedArtifacts(
            manifest: arcoreConfidenceManifest,
            rowArrayKey: "frames",
            pathKeys: ["confidence_path", "paired_depth_path"],
            baseDirectory: rawDirectoryURL,
            errors: &errors
        )

        validateTruthfulness(manifest: manifest, errors: &errors)

        if let rightsConsent, (rightsConsent["redaction_required"] as? Bool) != true {
            warnings.append("rights_redaction_not_explicitly_required")
        }

        validateHashes(rawDirectoryURL: rawDirectoryURL, hashes: hashes, errors: &errors)

        return CaptureRawContractV3ValidationResult(
            isValid: errors.isEmpty,
            errors: errors,
            warnings: warnings
        )
    }

    private func validateRequiredManifestFields(_ manifest: [String: Any], errors: inout [String]) {
        let requiredStrings = [
            "schema_version",
            "capture_schema_version",
            "scene_id",
            "capture_id",
            "capture_source",
            "capture_tier_hint",
            "coordinate_frame_session_id",
            "video_uri",
            "os_version",
            "app_version",
            "app_build",
            "hardware_model_identifier",
            "device_model_marketing",
            "rights_profile",
            "capture_profile_id",
        ]
        let requiredNumbers = ["capture_start_epoch_ms", "fps_source", "width", "height"]
        let requiredBooleans = ["has_lidar", "depth_supported"]

        for key in requiredStrings where (manifest[key] as? String)?.isEmpty != false {
            errors.append("manifest_missing_string:\(key)")
        }
        for key in requiredNumbers {
            let value = manifest[key]
            if !(value is NSNumber) {
                errors.append("manifest_missing_number:\(key)")
            }
        }
        for key in requiredBooleans where !(manifest[key] is Bool) {
            errors.append("manifest_missing_boolean:\(key)")
        }
        if !(manifest["capture_capabilities"] is [String: Any]) {
            errors.append("manifest_missing_object:capture_capabilities")
        }
    }

    private func fileExists(_ root: URL, _ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(relativePath).path)
    }

    private func requireFiles(_ paths: [String], in root: URL, errors: inout [String]) {
        for path in paths where !fileExists(root, path) {
            errors.append("missing_required_file:\(path)")
        }
    }

    private func capability(_ capabilities: [String: Any], key: String) -> Bool {
        capabilities[key] as? Bool == true
    }

    private func hasCanonicalVideo(in root: URL, manifest: [String: Any]) -> Bool {
        if let videoURI = manifest["video_uri"] as? String, !videoURI.isEmpty {
            let normalized = videoURI.replacingOccurrences(of: "raw/", with: "")
            if fileExists(root, normalized) || fileExists(root, videoURI) {
                return true
            }
        }
        return fileExists(root, "walkthrough.mov") || fileExists(root, "walkthrough.mp4")
    }

    private func validateIdentityConsistency(
        sceneId: String?,
        captureId: String?,
        objects: [(String, [String: Any]?)],
        errors: inout [String]
    ) {
        for (label, object) in objects {
            guard let object else { continue }
            if let sceneId, let objectSceneId = object["scene_id"] as? String, objectSceneId != sceneId {
                errors.append("identity_mismatch:\(label):scene_id")
            }
            if let captureId, let objectCaptureId = object["capture_id"] as? String, objectCaptureId != captureId {
                errors.append("identity_mismatch:\(label):capture_id")
            }
        }
    }

    private func validateFrameIdsAndTime(
        label: String,
        rows: [[String: Any]],
        frameIdKey: String,
        timeKey: String,
        errors: inout [String]
    ) {
        var seen = Set<String>()
        var lastTime = -Double.infinity
        for row in rows {
            guard let frameId = row[frameIdKey] as? String else {
                errors.append("missing_frame_id:\(label)")
                continue
            }
            if !seen.insert(frameId).inserted {
                errors.append("frame_id_duplicate:\(label):\(frameId)")
            }
            if let timeValue = numericValue(row[timeKey]) {
                if timeValue < lastTime {
                    errors.append("timestamp_non_monotonic:\(label):\(frameId)")
                }
                lastTime = timeValue
            } else {
                errors.append("missing_time:\(label):\(frameId)")
            }
        }
    }

    private func validateReferencedArtifacts(
        manifest: [String: Any]?,
        rowArrayKey: String,
        pathKeys: [String],
        baseDirectory: URL,
        errors: inout [String]
    ) {
        guard let manifest,
              let rows = manifest[rowArrayKey] as? [[String: Any]] else { return }
        for row in rows {
            let frameId = (row["frame_id"] as? String) ?? "unknown"
            for key in pathKeys {
                guard let path = row[key] as? String else { continue }
                if !FileManager.default.fileExists(atPath: baseDirectory.appendingPathComponent(path).path) {
                    errors.append("referenced_artifact_missing:\(frameId):\(path)")
                }
            }
        }
    }

    private func validateHashes(rawDirectoryURL: URL, hashes: [String: Any]?, errors: inout [String]) {
        guard let hashes,
              let artifacts = hashes["artifacts"] as? [String: String] else {
            errors.append("missing_hash_manifest")
            return
        }

        for (relativePath, expectedHash) in artifacts {
            let fileURL = rawDirectoryURL.appendingPathComponent(relativePath)
            guard let data = try? Data(contentsOf: fileURL) else {
                errors.append("hash_target_missing:\(relativePath)")
                continue
            }
            let actualHash = sha256Hex(of: data)
            if actualHash != expectedHash {
                errors.append("hash_mismatch:\(relativePath)")
            }
        }
    }

    private func validateTruthfulness(manifest: [String: Any], errors: inout [String]) {
        let capabilities = manifest["capture_capabilities"] as? [String: Any] ?? [:]
        let evidence = manifest["capture_evidence"] as? [String: Any] ?? [:]
        let motionAuthority = evidence["motion_authority"] as? String
        let motionProvenance = evidence["motion_provenance"] as? String

        if capability(capabilities, key: "motion_authoritative"), motionAuthority != "authoritative_raw" {
            errors.append("false_claim:motion_authoritative")
        }
        if motionAuthority == "authoritative_raw", motionProvenance == "phone_imu_diagnostic_only" {
            errors.append("false_claim:diagnostic_motion_as_authoritative")
        }
        if capability(capabilities, key: "camera_pose"),
           ((evidence["pose_rows"] as? NSNumber)?.intValue ?? 0) <= 0 {
            errors.append("false_claim:camera_pose_without_pose_rows")
        }
        if capability(capabilities, key: "camera_intrinsics"),
           evidence["intrinsics_valid"] as? Bool != true {
            errors.append("false_claim:camera_intrinsics_without_intrinsics")
        }
        if capability(capabilities, key: "depth"),
           ((evidence["depth_frames"] as? NSNumber)?.intValue ?? 0) <= 0 {
            errors.append("false_claim:depth_without_frames")
        }
        if (evidence["pose_authority"] as? String) == "authoritative_raw",
           (manifest["capture_source"] as? String) == "glasses" {
            errors.append("false_claim:glasses_pose_authoritative_raw")
        }
    }

    private func validateRecordingSession(
        _ recordingSession: [String: Any]?,
        captureCapabilities: [String: Any],
        hasPoseWorldTracking: Bool,
        errors: inout [String]
    ) {
        guard let recordingSession else {
            errors.append("missing_recording_session")
            return
        }
        let requiredStrings = [
            "scene_id",
            "capture_id",
            "coordinate_frame_session_id",
            "arkit_session_id",
            "world_frame_definition",
            "units",
            "handedness",
        ]
        for key in requiredStrings where (recordingSession[key] as? String)?.isEmpty != false {
            errors.append("recording_session_missing_string:\(key)")
        }
        if !(recordingSession["gravity_aligned"] is Bool) {
            errors.append("recording_session_missing_boolean:gravity_aligned")
        }
        if !(recordingSession["session_reset_count"] is NSNumber) {
            errors.append("recording_session_missing_number:session_reset_count")
        }
        let worldFrameDefinition = recordingSession["world_frame_definition"] as? String ?? ""
        if hasPoseWorldTracking && worldFrameDefinition.hasPrefix("unavailable_") {
            errors.append("recording_session_false_claim:world_frame_unavailable_with_pose")
        }
        if capability(captureCapabilities, key: "camera_pose") && worldFrameDefinition.hasPrefix("unavailable_") {
            errors.append("recording_session_false_claim:camera_pose_without_world_frame")
        }
        if hasPoseWorldTracking && (recordingSession["gravity_aligned"] as? Bool) != true {
            errors.append("recording_session_false_claim:pose_world_not_gravity_aligned")
        }
        if let units = recordingSession["units"] as? String, units != "meters" {
            errors.append("recording_session_invalid_units")
        }
    }

    private func loadJSONObject(at url: URL, errors: inout [String]) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            errors.append("invalid_json:\(url.lastPathComponent)")
            return nil
        }
        return object
    }

    private func loadJSONObjectIfPresent(at url: URL, errors: inout [String]) -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return loadJSONObject(at: url, errors: &errors)
    }

    private func loadJSONLines(at url: URL, errors: inout [String]) -> [[String: Any]] {
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else {
            return []
        }
        return content.split(whereSeparator: \.isNewline).compactMap { line in
            guard let lineData = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                errors.append("invalid_jsonl:\(url.lastPathComponent)")
                return nil
            }
            return object
        }
    }

    private func loadJSONLinesIfPresent(at url: URL, errors: inout [String]) -> [[String: Any]] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return loadJSONLines(at: url, errors: &errors)
    }

    private func isCanonicalV3Manifest(_ manifest: [String: Any]) -> Bool {
        (manifest["schema_version"] as? String) == "v3" &&
        ((manifest["capture_schema_version"] as? String)?.hasPrefix("3.") == true)
    }

    private func isValidTransformMatrix(_ value: Any?) -> Bool {
        guard let matrix = value as? [[NSNumber]], matrix.count == 4 else { return false }
        return matrix.allSatisfy { row in
            row.count == 4 && row.allSatisfy { $0.doubleValue.isFinite }
        }
    }

    private func numericValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        return nil
    }

    private func sha256Hex(of data: Data) -> String {
        #if canImport(CryptoKit)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
        #else
        return data.base64EncodedString()
        #endif
    }
}
