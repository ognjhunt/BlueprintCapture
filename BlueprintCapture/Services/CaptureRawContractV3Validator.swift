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

        let requiredJSONFiles = [
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
            "arkit/session_intrinsics.json",
            "arkit/depth_manifest.json",
            "arkit/confidence_manifest.json",
        ]
        let requiredJSONLFiles = [
            "sync_map.jsonl",
            "motion.jsonl",
            "semantic_anchor_observations.jsonl",
            "arkit/poses.jsonl",
            "arkit/frames.jsonl",
            "arkit/frame_quality.jsonl",
            "arkit/per_frame_camera_state.jsonl",
        ]
        let requiredBinaryFiles = ["walkthrough.mov"]

        for path in requiredJSONFiles + requiredJSONLFiles + requiredBinaryFiles {
            if !FileManager.default.fileExists(atPath: rawDirectoryURL.appendingPathComponent(path).path) {
                errors.append("missing_required_file:\(path)")
            }
        }

        let manifest = loadJSONObject(at: rawDirectoryURL.appendingPathComponent("manifest.json"), errors: &errors)
        guard let manifest else {
            return CaptureRawContractV3ValidationResult(isValid: false, errors: errors, warnings: warnings)
        }

        if !isCanonicalV3Manifest(manifest) {
            errors.append("manifest_not_v3")
        }

        validateRequiredManifestFields(manifest, errors: &errors)

        let provenance = loadJSONObject(at: rawDirectoryURL.appendingPathComponent("provenance.json"), errors: &errors)
        let rightsConsent = loadJSONObject(at: rawDirectoryURL.appendingPathComponent("rights_consent.json"), errors: &errors)
        let captureContext = loadJSONObject(at: rawDirectoryURL.appendingPathComponent("capture_context.json"), errors: &errors)
        let recordingSession = loadJSONObject(at: rawDirectoryURL.appendingPathComponent("recording_session.json"), errors: &errors)
        let captureTopology = loadJSONObject(at: rawDirectoryURL.appendingPathComponent("capture_topology.json"), errors: &errors)
        let completion = loadJSONObject(at: rawDirectoryURL.appendingPathComponent("capture_upload_complete.json"), errors: &errors)
        let hashes = loadJSONObject(at: rawDirectoryURL.appendingPathComponent("hashes.json"), errors: &errors)
        let depthManifest = loadJSONObject(at: rawDirectoryURL.appendingPathComponent("arkit/depth_manifest.json"), errors: &errors)
        let confidenceManifest = loadJSONObject(at: rawDirectoryURL.appendingPathComponent("arkit/confidence_manifest.json"), errors: &errors)
        let sessionIntrinsics = loadJSONObject(at: rawDirectoryURL.appendingPathComponent("arkit/session_intrinsics.json"), errors: &errors)

        let poses = loadJSONLines(at: rawDirectoryURL.appendingPathComponent("arkit/poses.jsonl"), errors: &errors)
        let frames = loadJSONLines(at: rawDirectoryURL.appendingPathComponent("arkit/frames.jsonl"), errors: &errors)
        let frameQuality = loadJSONLines(at: rawDirectoryURL.appendingPathComponent("arkit/frame_quality.jsonl"), errors: &errors)
        let syncMap = loadJSONLines(at: rawDirectoryURL.appendingPathComponent("sync_map.jsonl"), errors: &errors)

        validateIdentityConsistency(
            sceneId: manifest["scene_id"] as? String,
            captureId: manifest["capture_id"] as? String,
            objects: [
                ("provenance", provenance),
                ("rights_consent", rightsConsent),
                ("capture_context", captureContext),
                ("capture_upload_complete", completion),
            ],
            errors: &errors
        )

        let manifestCfs = manifest["coordinate_frame_session_id"] as? String
        let sessionCfs = recordingSession?["coordinate_frame_session_id"] as? String
        let topologyCfs = captureTopology?["coordinate_frame_session_id"] as? String
        let intrinsicsCfs = sessionIntrinsics?["coordinate_frame_session_id"] as? String
        let expectedCfs = manifestCfs ?? sessionCfs ?? topologyCfs ?? intrinsicsCfs
        for (label, value) in [
            ("manifest", manifestCfs),
            ("recording_session", sessionCfs),
            ("capture_topology", topologyCfs),
            ("session_intrinsics", intrinsicsCfs),
        ] {
            if let expectedCfs, let value, value != expectedCfs {
                errors.append("coordinate_frame_session_mismatch:\(label)")
            }
        }

        validateFrameIdsAndTime(label: "poses", rows: poses, frameIdKey: "frame_id", timeKey: "t_capture_sec", errors: &errors)
        validateFrameIdsAndTime(label: "frames", rows: frames, frameIdKey: "frame_id", timeKey: "t_capture_sec", errors: &errors)
        validateFrameIdsAndTime(label: "frame_quality", rows: frameQuality, frameIdKey: "frame_id", timeKey: "t_capture_sec", errors: &errors)
        validateFrameIdsAndTime(label: "sync_map", rows: syncMap, frameIdKey: "frame_id", timeKey: "t_capture_sec", errors: &errors)

        if !poses.isEmpty && syncMap.isEmpty {
            errors.append("sync_map_missing_rows")
        }

        for pose in poses {
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
            "app_version",
            "app_build",
            "ios_version",
            "ios_build",
            "hardware_model_identifier",
            "device_model_marketing",
            "rights_profile",
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

    private func loadJSONObject(at url: URL, errors: inout [String]) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            errors.append("invalid_json:\(url.lastPathComponent)")
            return nil
        }
        return object
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
