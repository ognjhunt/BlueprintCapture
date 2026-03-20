import Foundation
import Testing
#if canImport(CryptoKit)
import CryptoKit
#endif
@testable import BlueprintCapture

struct CaptureRawContractV3ValidatorTests {

    @Test
    func validatorAcceptsCoherentBundle() throws {
        let root = try makeValidBundle()
        let result = CaptureRawContractV3Validator().validate(rawDirectoryURL: root)
        #expect(result.isValid == true)
        #expect(result.errors.isEmpty)
    }

    @Test
    func validatorRejectsCoordinateFrameMismatchAndMissingArtifacts() throws {
        let root = try makeValidBundle()
        let recordingSessionURL = root.appendingPathComponent("recording_session.json")
        try Data("""
{"schema_version":"v1","coordinate_frame_session_id":"cfs-2"}
""".utf8).write(to: recordingSessionURL)
        try FileManager.default.removeItem(at: root.appendingPathComponent("arkit/confidence/000001.png"))
        try refreshHashes(in: root)

        let result = CaptureRawContractV3Validator().validate(rawDirectoryURL: root)
        #expect(result.isValid == false)
        #expect(result.errors.contains("coordinate_frame_session_mismatch:recording_session"))
        #expect(result.errors.contains("referenced_artifact_missing:000001:arkit/confidence/000001.png"))
    }

    private func makeValidBundle() throws -> URL {
        let fileManager = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("raw-contract-v3-\(UUID().uuidString)", isDirectory: true)
        let arkit = root.appendingPathComponent("arkit", isDirectory: true)
        try fileManager.createDirectory(at: arkit.appendingPathComponent("depth", isDirectory: true), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: arkit.appendingPathComponent("confidence", isDirectory: true), withIntermediateDirectories: true)

        try Data([0x01, 0x02]).write(to: root.appendingPathComponent("walkthrough.mov"))
        try writeJSON([
            "schema_version": "v3",
            "capture_schema_version": "3.0.0",
            "scene_id": "scene-1",
            "capture_id": "capture-1",
            "capture_source": "iphone",
            "capture_tier_hint": "tier1_iphone",
            "coordinate_frame_session_id": "cfs-1",
            "video_uri": "raw/walkthrough.mov",
            "capture_start_epoch_ms": 1_700_000_000_000,
            "app_version": "1.0.0",
            "app_build": "100",
            "ios_version": "18.3.1",
            "ios_build": "22D68",
            "hardware_model_identifier": "iPhone16,2",
            "device_model_marketing": "iPhone 15 Pro",
            "has_lidar": true,
            "depth_supported": true,
            "fps_source": 30.0,
            "width": 1920,
            "height": 1440,
            "rights_profile": "documented_permission",
        ], to: root.appendingPathComponent("manifest.json"))
        try writeJSON(["scene_id": "scene-1", "capture_id": "capture-1"], to: root.appendingPathComponent("provenance.json"))
        try writeJSON(["scene_id": "scene-1", "capture_id": "capture-1", "redaction_required": true], to: root.appendingPathComponent("rights_consent.json"))
        try writeJSON(["scene_id": "scene-1", "capture_id": "capture-1"], to: root.appendingPathComponent("capture_context.json"))
        try writeJSON(["schema_version": "v1"], to: root.appendingPathComponent("intake_packet.json"))
        try writeJSON(["schema_version": "v1"], to: root.appendingPathComponent("task_hypothesis.json"))
        try writeJSON(["schema_version": "v1", "coordinate_frame_session_id": "cfs-1"], to: root.appendingPathComponent("recording_session.json"))
        try writeJSON(["schema_version": "v1", "coordinate_frame_session_id": "cfs-1"], to: root.appendingPathComponent("capture_topology.json"))
        try writeJSON(["schema_version": "v1", "route_anchors": []], to: root.appendingPathComponent("route_anchors.json"))
        try writeJSON(["schema_version": "v1", "checkpoint_events": []], to: root.appendingPathComponent("checkpoint_events.json"))
        try writeJSON(["schema_version": "v1", "relocalization_events": []], to: root.appendingPathComponent("relocalization_events.json"))
        try writeJSON(["schema_version": "v1", "observed_anchor_ids": []], to: root.appendingPathComponent("overlap_graph.json"))
        try writeJSON(["schema_version": "v1"], to: root.appendingPathComponent("video_track.json"))
        try writeJSON(["scene_id": "scene-1", "capture_id": "capture-1"], to: root.appendingPathComponent("capture_upload_complete.json"))
        try writeJSON([
            "schema_version": "v1",
            "coordinate_frame_session_id": "cfs-1",
            "camera_model": "pinhole",
            "principal_point_reference": "full_resolution_image",
            "distortion_model": "apple_standard",
            "distortion_coeffs": [],
            "intrinsics": ["fx": 1, "fy": 1, "cx": 1, "cy": 1, "width": 1, "height": 1],
        ], to: arkit.appendingPathComponent("session_intrinsics.json"))
        try Data([0x01]).write(to: arkit.appendingPathComponent("depth/000001.png"))
        try Data([0x01]).write(to: arkit.appendingPathComponent("confidence/000001.png"))
        try writeJSON([
            "schema_version": "v1",
            "frames": [[
                "frame_id": "000001",
                "depth_path": "arkit/depth/000001.png",
                "paired_confidence_path": "arkit/confidence/000001.png",
            ]],
        ], to: arkit.appendingPathComponent("depth_manifest.json"))
        try writeJSON([
            "schema_version": "v1",
            "frames": [[
                "frame_id": "000001",
                "confidence_path": "arkit/confidence/000001.png",
                "paired_depth_path": "arkit/depth/000001.png",
            ]],
        ], to: arkit.appendingPathComponent("confidence_manifest.json"))

        try writeLines([
            #"{"frame_id":"000001","t_capture_sec":0.0,"coordinate_frame_session_id":"cfs-1","T_world_camera":[[1,0,0,0],[0,1,0,0],[0,0,1,0],[0,0,0,1]]}"#,
        ], to: arkit.appendingPathComponent("poses.jsonl"))
        try writeLines([
            #"{"frame_id":"000001","t_capture_sec":0.0}"#,
        ], to: arkit.appendingPathComponent("frames.jsonl"))
        try writeLines([
            #"{"frame_id":"000001","t_capture_sec":0.0}"#,
        ], to: arkit.appendingPathComponent("frame_quality.jsonl"))
        try writeLines([
            #"{"frame_id":"000001","t_capture_sec":0.0}"#,
        ], to: root.appendingPathComponent("sync_map.jsonl"))
        try writeLines([
            #"{"timestamp":1.0,"t_capture_sec":0.0}"#,
        ], to: root.appendingPathComponent("motion.jsonl"))
        try writeLines([], to: root.appendingPathComponent("semantic_anchor_observations.jsonl"))
        try writeLines([
            #"{"frame_id":"000001","t_capture_sec":0.0,"coordinate_frame_session_id":"cfs-1"}"#,
        ], to: arkit.appendingPathComponent("per_frame_camera_state.jsonl"))

        try refreshHashes(in: root)
        return root
    }

    private func refreshHashes(in root: URL) throws {
        var artifacts: [String: String] = [:]
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        while let fileURL = enumerator?.nextObject() as? URL {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            guard fileURL.lastPathComponent != "hashes.json" else { continue }
            let relative = fileURL.path.replacingOccurrences(of: root.path + "/", with: "")
            artifacts[relative] = sha256Hex(try Data(contentsOf: fileURL))
        }
        try writeJSON([
            "schema_version": "v1",
            "bundle_sha256": sha256Hex(Data(artifacts.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: "\n").utf8)),
            "artifacts": artifacts,
        ], to: root.appendingPathComponent("hashes.json"))
    }

    private func writeJSON(_ object: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .withoutEscapingSlashes])
        try data.write(to: url)
    }

    private func writeLines(_ lines: [String], to url: URL) throws {
        try lines.joined(separator: "\n").appending(lines.isEmpty ? "" : "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func sha256Hex(_ data: Data) -> String {
        #if canImport(CryptoKit)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
        #else
        return data.base64EncodedString()
        #endif
    }
}
