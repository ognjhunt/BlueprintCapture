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
{"schema_version":"v1","scene_id":"scene-1","capture_id":"capture-1","coordinate_frame_session_id":"cfs-2","arkit_session_id":"cfs-2","world_frame_definition":"arkit_world_origin_at_session_start","units":"meters","handedness":"right_handed","gravity_aligned":true,"session_reset_count":0}
""".utf8).write(to: recordingSessionURL)
        try FileManager.default.removeItem(at: root.appendingPathComponent("arkit/confidence/000001.png"))
        try refreshHashes(in: root)

        let result = CaptureRawContractV3Validator().validate(rawDirectoryURL: root)
        #expect(result.isValid == false)
        #expect(result.errors.contains("coordinate_frame_session_mismatch:recording_session"))
        #expect(result.errors.contains("referenced_artifact_missing:000001:arkit/confidence/000001.png"))
    }

    @Test
    func validatorRejectsMalformedJsonl() throws {
        let root = try makeValidBundle()
        try writeLines([
            #"{"frame_id":"000001","t_capture_sec":0.0}"#,
            #"{"frame_id":"000002""#,
        ], to: root.appendingPathComponent("arkit/frames.jsonl"))
        try refreshHashes(in: root)

        let result = CaptureRawContractV3Validator().validate(rawDirectoryURL: root)
        #expect(result.isValid == false)
        #expect(result.errors.contains("invalid_jsonl:frames.jsonl"))
    }

    @Test
    func validatorAcceptsNonLiDARIPhoneBundleWithoutDepth() throws {
        let root = try makeValidBundle()
        let manifestURL = root.appendingPathComponent("manifest.json")
        let manifest = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
        var updated = manifest
        updated["has_lidar"] = false
        updated["depth_supported"] = false
        updated["capture_profile_id"] = "iphone_arkit_non_lidar"
        updated["capture_capabilities"] = [
            "camera_pose": true,
            "camera_intrinsics": true,
            "depth": false,
            "depth_confidence": false,
            "planes": false,
            "feature_points": false,
            "tracking_state": true,
            "relocalization_events": false,
            "light_estimate": false,
            "motion": true,
            "motion_authoritative": true,
            "pose_rows": 1,
            "intrinsics_valid": true,
            "depth_frames": 0,
            "confidence_frames": 0,
            "tracking_state_rows": 1,
            "motion_samples": 1,
            "pose_authority": "authoritative_raw",
            "intrinsics_authority": "authoritative_raw",
            "depth_authority": "not_available",
            "motion_authority": "authoritative_raw",
            "motion_provenance": "iphone_device_imu",
            "geometry_source": "arkit",
            "geometry_expected_downstream": true,
        ]
        updated["capture_evidence"] = [
            "pose_rows": 1,
            "intrinsics_valid": true,
            "depth_frames": 0,
            "confidence_frames": 0,
            "tracking_state_rows": 1,
            "motion_samples": 1,
            "pose_authority": "authoritative_raw",
            "intrinsics_authority": "authoritative_raw",
            "depth_authority": "not_available",
            "motion_authority": "authoritative_raw",
            "motion_provenance": "iphone_device_imu",
        ]
        try writeJSON(updated, to: manifestURL)
        try FileManager.default.removeItem(at: root.appendingPathComponent("arkit/depth_manifest.json"))
        try FileManager.default.removeItem(at: root.appendingPathComponent("arkit/confidence_manifest.json"))
        try FileManager.default.removeItem(at: root.appendingPathComponent("arkit/depth"))
        try FileManager.default.removeItem(at: root.appendingPathComponent("arkit/confidence"))
        try refreshHashes(in: root)

        let result = CaptureRawContractV3Validator().validate(rawDirectoryURL: root)
        #expect(result.isValid == true)
    }

    @Test
    func validatorAcceptsAndroidARCoreBundle() throws {
        let root = try makeAndroidARCoreBundle()
        let result = CaptureRawContractV3Validator().validate(rawDirectoryURL: root)
        #expect(result.isValid == true)
    }

    @Test
    func validatorRejectsRecordingSessionMissingWorldFrameFields() throws {
        let root = try makeValidBundle()
        try writeJSON([
            "schema_version": "v1",
            "scene_id": "scene-1",
            "capture_id": "capture-1",
            "coordinate_frame_session_id": "cfs-1",
        ], to: root.appendingPathComponent("recording_session.json"))
        try refreshHashes(in: root)

        let result = CaptureRawContractV3Validator().validate(rawDirectoryURL: root)
        #expect(result.isValid == false)
        #expect(result.errors.contains("recording_session_missing_string:world_frame_definition"))
        #expect(result.errors.contains("recording_session_missing_boolean:gravity_aligned"))
    }

    @Test
    func validatorAcceptsGlassesBundleWithCompanionPhone() throws {
        let root = try makeGlassesBundle(includeCompanionPhone: true)
        let result = CaptureRawContractV3Validator().validate(rawDirectoryURL: root)
        #expect(result.isValid == true)
    }

    @Test
    func validatorRejectsMalformedMotionJsonlContent() throws {
        let root = try makeValidBundle()
        try writeLines([
            #"{\"timestamp\":1.0}"#,
        ], to: root.appendingPathComponent("motion.jsonl"))
        try refreshHashes(in: root)

        let result = CaptureRawContractV3Validator().validate(rawDirectoryURL: root)
        #expect(result.isValid == false)
        #expect(result.errors.contains("invalid_jsonl:motion.jsonl"))
    }

    @Test
    func validatorRejectsNullMotionJsonlFields() throws {
        let root = try makeValidBundle()
        try writeLines([
            #"{"timestamp":1.0,"t_capture_sec":0.0,"t_monotonic_ns":0,"wall_time":"2026-03-20T14:00:29.857Z","motion_provenance":null,"attitude":{"roll":0.0,"pitch":0.0,"yaw":0.0,"quaternion":{"x":0.0,"y":0.0,"z":0.0,"w":1.0}},"rotation_rate":{"x":0.0,"y":0.0,"z":0.0},"gravity":{"x":0.0,"y":0.0,"z":0.0},"user_acceleration":{"x":0.0,"y":0.0,"z":0.0}}"#,
        ], to: root.appendingPathComponent("motion.jsonl"))
        try refreshHashes(in: root)

        let result = CaptureRawContractV3Validator().validate(rawDirectoryURL: root)
        #expect(result.isValid == false)
        #expect(result.errors.contains("motion_missing_field:motion_provenance:line_1"))
    }

    @Test
    func validatorRejectsMalformedSemanticAnchorJsonlContent() throws {
        let root = try makeValidBundle()
        try writeLines([
            #"{\"anchor_instance_id\":\"a1\"}"#,
        ], to: root.appendingPathComponent("semantic_anchor_observations.jsonl"))
        try refreshHashes(in: root)

        let result = CaptureRawContractV3Validator().validate(rawDirectoryURL: root)
        #expect(result.isValid == false)
        #expect(result.errors.contains("invalid_jsonl:semantic_anchor_observations.jsonl"))
    }

    @Test
    func validatorRejectsDiagnosticMotionClaimedAsAuthoritative() throws {
        let root = try makeGlassesBundle(includeCompanionPhone: false)
        let manifestURL = root.appendingPathComponent("manifest.json")
        let manifest = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
        var updated = manifest
        updated["capture_capabilities"] = [
            "motion": true,
            "motion_authoritative": true,
            "pose_rows": 0,
            "intrinsics_valid": false,
            "depth_frames": 0,
            "confidence_frames": 0,
            "motion_samples": 1,
        ]
        updated["capture_evidence"] = [
            "motion_samples": 1,
            "motion_authority": "authoritative_raw",
            "motion_provenance": "phone_imu_diagnostic_only",
        ]
        try writeJSON(updated, to: manifestURL)
        try refreshHashes(in: root)

        let result = CaptureRawContractV3Validator().validate(rawDirectoryURL: root)
        #expect(result.isValid == false)
        #expect(result.errors.contains("false_claim:diagnostic_motion_as_authoritative"))
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
            "capture_schema_version": "3.1.0",
            "scene_id": "scene-1",
            "capture_id": "capture-1",
            "capture_source": "iphone",
            "capture_tier_hint": "tier1_iphone",
            "coordinate_frame_session_id": "cfs-1",
            "video_uri": "raw/walkthrough.mov",
            "capture_start_epoch_ms": 1_700_000_000_000,
            "os_version": "iOS 18.3.1",
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
            "capture_profile_id": "iphone_arkit_lidar",
            "capture_capabilities": [
                "camera_pose": true,
                "camera_intrinsics": true,
                "depth": true,
                "depth_confidence": true,
                "mesh": false,
                "point_cloud": false,
                "planes": false,
                "feature_points": false,
                "tracking_state": true,
                "relocalization_events": false,
                "light_estimate": false,
                "motion": true,
                "motion_authoritative": true,
                "companion_phone_pose": false,
                "companion_phone_intrinsics": false,
                "companion_phone_calibration": false,
                "pose_rows": 1,
                "intrinsics_valid": true,
                "depth_frames": 1,
                "confidence_frames": 1,
                "mesh_files": 0,
                "point_cloud_samples": 0,
                "plane_rows": 0,
                "feature_point_rows": 0,
                "tracking_state_rows": 1,
                "relocalization_event_rows": 0,
                "light_estimate_rows": 0,
                "motion_samples": 1,
                "pose_authority": "authoritative_raw",
                "intrinsics_authority": "authoritative_raw",
                "depth_authority": "authoritative_raw",
                "motion_authority": "authoritative_raw",
                "motion_provenance": "iphone_device_imu",
                "geometry_source": "arkit",
                "geometry_expected_downstream": false,
            ],
            "capture_evidence": [
                "pose_rows": 1,
                "intrinsics_valid": true,
                "depth_frames": 1,
                "confidence_frames": 1,
                "tracking_state_rows": 1,
                "motion_samples": 1,
                "pose_authority": "authoritative_raw",
                "intrinsics_authority": "authoritative_raw",
                "depth_authority": "authoritative_raw",
                "motion_authority": "authoritative_raw",
                "motion_provenance": "iphone_device_imu",
            ],
        ], to: root.appendingPathComponent("manifest.json"))
        try writeJSON(["scene_id": "scene-1", "capture_id": "capture-1"], to: root.appendingPathComponent("provenance.json"))
        try writeJSON(["scene_id": "scene-1", "capture_id": "capture-1", "redaction_required": true], to: root.appendingPathComponent("rights_consent.json"))
        try writeJSON(["scene_id": "scene-1", "capture_id": "capture-1"], to: root.appendingPathComponent("capture_context.json"))
        try writeJSON(["schema_version": "v1"], to: root.appendingPathComponent("intake_packet.json"))
        try writeJSON(["schema_version": "v1"], to: root.appendingPathComponent("task_hypothesis.json"))
        try writeJSON([
            "schema_version": "v1",
            "scene_id": "scene-1",
            "capture_id": "capture-1",
            "coordinate_frame_session_id": "cfs-1",
            "arkit_session_id": "cfs-1",
            "world_frame_definition": "arkit_world_origin_at_session_start",
            "units": "meters",
            "handedness": "right_handed",
            "gravity_aligned": true,
            "session_reset_count": 0,
        ], to: root.appendingPathComponent("recording_session.json"))
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

    private func makeAndroidARCoreBundle() throws -> URL {
        let root = try makeValidBundle()
        try FileManager.default.removeItem(at: root.appendingPathComponent("arkit"))
        try Data([0x01, 0x02]).write(to: root.appendingPathComponent("walkthrough.mp4"))
        try FileManager.default.removeItem(at: root.appendingPathComponent("walkthrough.mov"))
        let arcore = root.appendingPathComponent("arcore", isDirectory: true)
        try FileManager.default.createDirectory(at: arcore.appendingPathComponent("depth", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: arcore.appendingPathComponent("confidence", isDirectory: true), withIntermediateDirectories: true)
        try writeJSON([
            "schema_version": "v1",
            "coordinate_frame_session_id": "cfs-1",
            "fx": 1,
            "fy": 1,
            "cx": 1,
            "cy": 1,
            "width": 1,
            "height": 1,
        ], to: arcore.appendingPathComponent("session_intrinsics.json"))
        try writeJSON([
            "schema_version": "v1",
            "frames": [[
                "frame_id": "000001",
                "depth_path": "arcore/depth/000001.png",
                "paired_confidence_path": "arcore/confidence/000001.png",
            ]],
        ], to: arcore.appendingPathComponent("depth_manifest.json"))
        try writeJSON([
            "schema_version": "v1",
            "frames": [[
                "frame_id": "000001",
                "confidence_path": "arcore/confidence/000001.png",
                "paired_depth_path": "arcore/depth/000001.png",
            ]],
        ], to: arcore.appendingPathComponent("confidence_manifest.json"))
        try Data([0x01]).write(to: arcore.appendingPathComponent("depth/000001.png"))
        try Data([0x01]).write(to: arcore.appendingPathComponent("confidence/000001.png"))
        try writeLines([#"{"frame_id":"000001","t_capture_sec":0.0,"coordinate_frame_session_id":"cfs-1","T_world_camera":[[1,0,0,0],[0,1,0,0],[0,0,1,0],[0,0,0,1]]}"#], to: arcore.appendingPathComponent("poses.jsonl"))
        try writeLines([#"{"frame_id":"000001","t_capture_sec":0.0}"#], to: arcore.appendingPathComponent("frames.jsonl"))
        try writeLines([#"{"frame_id":"000001","t_capture_sec":0.0}"#], to: arcore.appendingPathComponent("tracking_state.jsonl"))
        try writeLines([#"{"frame_id":"000001","t_capture_sec":0.0}"#], to: arcore.appendingPathComponent("point_cloud.jsonl"))
        try writeLines([#"{"frame_id":"000001","t_capture_sec":0.0}"#], to: arcore.appendingPathComponent("planes.jsonl"))
        try writeLines([#"{"frame_id":"000001","t_capture_sec":0.0}"#], to: arcore.appendingPathComponent("light_estimates.jsonl"))
        try writeLines([#"{"frame_id":"000001","t_capture_sec":0.0}"#], to: root.appendingPathComponent("sync_map.jsonl"))
        try writeJSON([
            "schema_version": "v1",
            "scene_id": "scene-1",
            "capture_id": "capture-1",
            "coordinate_frame_session_id": "cfs-1",
            "arkit_session_id": "cfs-1",
            "world_frame_definition": "arcore_world_origin_at_session_start",
            "units": "meters",
            "handedness": "right_handed",
            "gravity_aligned": true,
            "session_reset_count": 0,
        ], to: root.appendingPathComponent("recording_session.json"))
        try writeJSON([
            "schema_version": "v3",
            "capture_schema_version": "3.1.0",
            "scene_id": "scene-1",
            "capture_id": "capture-1",
            "capture_source": "android",
            "capture_tier_hint": "tier2_android",
            "coordinate_frame_session_id": "cfs-1",
            "video_uri": "raw/walkthrough.mp4",
            "capture_start_epoch_ms": 1_700_000_000_000,
            "os_version": "Android 16",
            "app_version": "1.0.0",
            "app_build": "100",
            "hardware_model_identifier": "Pixel 9 Pro",
            "device_model_marketing": "Pixel 9 Pro",
            "has_lidar": false,
            "depth_supported": true,
            "fps_source": 30.0,
            "width": 1920,
            "height": 1080,
            "rights_profile": "documented_permission",
            "capture_profile_id": "android_arcore_depth",
            "capture_capabilities": [
                "camera_pose": true,
                "camera_intrinsics": true,
                "depth": true,
                "depth_confidence": true,
                "point_cloud": true,
                "planes": true,
                "tracking_state": true,
                "light_estimate": true,
                "motion": true,
                "motion_authoritative": true,
                "pose_rows": 1,
                "intrinsics_valid": true,
                "depth_frames": 1,
                "confidence_frames": 1,
                "point_cloud_samples": 1,
                "plane_rows": 1,
                "tracking_state_rows": 1,
                "light_estimate_rows": 1,
                "motion_samples": 1,
                "pose_authority": "raw_tracking_only",
                "intrinsics_authority": "raw_tracking_only",
                "depth_authority": "raw_tracking_only",
                "motion_authority": "authoritative_raw",
                "motion_provenance": "phone_imu_accelerometer_gyroscope",
                "geometry_source": "arcore",
                "geometry_expected_downstream": true,
            ],
            "capture_evidence": [
                "pose_rows": 1,
                "intrinsics_valid": true,
                "depth_frames": 1,
                "confidence_frames": 1,
                "point_cloud_samples": 1,
                "plane_rows": 1,
                "tracking_state_rows": 1,
                "light_estimate_rows": 1,
                "motion_samples": 1,
                "pose_authority": "raw_tracking_only",
                "intrinsics_authority": "raw_tracking_only",
                "depth_authority": "raw_tracking_only",
                "motion_authority": "authoritative_raw",
                "motion_provenance": "phone_imu_accelerometer_gyroscope",
            ],
        ], to: root.appendingPathComponent("manifest.json"))
        try refreshHashes(in: root)
        return root
    }

    private func makeGlassesBundle(includeCompanionPhone: Bool) throws -> URL {
        let root = try makeValidBundle()
        try FileManager.default.removeItem(at: root.appendingPathComponent("arkit"))
        try Data([0x01, 0x02]).write(to: root.appendingPathComponent("walkthrough.mov"))
        let glasses = root.appendingPathComponent("glasses", isDirectory: true)
        try FileManager.default.createDirectory(at: glasses, withIntermediateDirectories: true)
        try writeJSON(["schema_version": "v1"], to: glasses.appendingPathComponent("stream_metadata.json"))
        try writeLines([#"{"frame_index":1,"t_capture_sec":0.0}"#], to: glasses.appendingPathComponent("frame_timestamps.jsonl"))
        try writeLines([#"{"event":"unavailable_in_public_sdk"}"#], to: glasses.appendingPathComponent("device_state.jsonl"))
        try writeLines([#"{"event":"unavailable_in_public_sdk"}"#], to: glasses.appendingPathComponent("health_events.jsonl"))
        if includeCompanionPhone {
            let companion = root.appendingPathComponent("companion_phone", isDirectory: true)
            try FileManager.default.createDirectory(at: companion, withIntermediateDirectories: true)
            try writeLines([#"{"frame_id":"000001","t_capture_sec":0.0,"coordinate_frame_session_id":"cfs-1","T_world_camera":[[1,0,0,0],[0,1,0,0],[0,0,1,0],[0,0,0,1]]}"#], to: companion.appendingPathComponent("poses.jsonl"))
            try writeJSON([
                "fx": 1,
                "fy": 1,
                "cx": 1,
                "cy": 1,
                "width": 1,
                "height": 1,
                "coordinate_frame_session_id": "cfs-1",
            ], to: companion.appendingPathComponent("session_intrinsics.json"))
            try writeJSON(["calibrated_to_glasses_optical_center": false], to: companion.appendingPathComponent("calibration.json"))
        }
        try writeJSON([
            "schema_version": "v1",
            "scene_id": "scene-1",
            "capture_id": "capture-1",
            "coordinate_frame_session_id": "cfs-1",
            "arkit_session_id": "cfs-1",
            "world_frame_definition": includeCompanionPhone ? "arkit_world_origin_at_session_start" : "unavailable_no_public_world_tracking",
            "units": "meters",
            "handedness": includeCompanionPhone ? "right_handed" : "unknown",
            "gravity_aligned": includeCompanionPhone,
            "session_reset_count": 0,
        ], to: root.appendingPathComponent("recording_session.json"))
        try writeJSON([
            "schema_version": "v3",
            "capture_schema_version": "3.1.0",
            "scene_id": "scene-1",
            "capture_id": "capture-1",
            "capture_source": "glasses",
            "capture_tier_hint": "tier2_glasses",
            "coordinate_frame_session_id": "cfs-1",
            "video_uri": "raw/walkthrough.mov",
            "capture_start_epoch_ms": 1_700_000_000_000,
            "os_version": "iOS 18.3.1",
            "app_version": "1.0.0",
            "app_build": "100",
            "hardware_model_identifier": "MetaGlassesiPhoneHost",
            "device_model_marketing": "Meta Ray-Ban Smart Glasses",
            "has_lidar": false,
            "depth_supported": false,
            "fps_source": 30.0,
            "width": 1280,
            "height": 720,
            "rights_profile": "documented_permission",
            "capture_profile_id": includeCompanionPhone ? "glasses_pov_companion_phone" : "glasses_pov",
            "capture_capabilities": [
                "camera_pose": false,
                "camera_intrinsics": false,
                "depth": false,
                "depth_confidence": false,
                "motion": true,
                "motion_authoritative": false,
                "companion_phone_pose": includeCompanionPhone,
                "companion_phone_intrinsics": includeCompanionPhone,
                "companion_phone_calibration": includeCompanionPhone,
                "pose_rows": 0,
                "intrinsics_valid": false,
                "depth_frames": 0,
                "confidence_frames": 0,
                "motion_samples": 1,
                "pose_authority": "not_available",
                "intrinsics_authority": "not_available",
                "depth_authority": "not_available",
                "motion_authority": "diagnostic_only",
                "motion_provenance": "phone_imu_diagnostic_only",
                "geometry_source": NSNull(),
                "geometry_expected_downstream": true,
            ],
            "capture_evidence": [
                "pose_rows": 0,
                "intrinsics_valid": false,
                "depth_frames": 0,
                "confidence_frames": 0,
                "motion_samples": 1,
                "motion_authority": "diagnostic_only",
                "motion_provenance": "phone_imu_diagnostic_only",
            ],
        ], to: root.appendingPathComponent("manifest.json"))
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
