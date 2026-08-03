import Foundation
import Testing
@testable import BlueprintCapture

struct CaptureDownstreamCandidateManifestTests {
    @Test
    func providerNeutralCandidateRegistryAcceptsExactRetainedObservationMapping() throws {
        let syncRows = makeSyncRows()
        let manifest = try makeManifest(syncRows: syncRows)

        let errors = CaptureDownstreamCandidateManifest.validationErrors(
            manifest: manifest,
            syncRows: syncRows,
            expectedVideoURI: "walkthrough.mov",
            expectedCoordinateFrameSessionId: "cfs-1",
            rightsConsent: rightsConsent()
        )

        #expect(errors.isEmpty)
    }

    @Test
    func providerSelectionOrDirectUploadAuthorizationFailsClosed() throws {
        let syncRows = makeSyncRows()
        var manifest = try makeManifest(syncRows: syncRows)
        var providerNeutrality = try #require(
            manifest["provider_neutrality"] as? [String: Any]
        )
        providerNeutrality["third_party_provider_upload_authorized"] = true
        providerNeutrality["provider_selected"] = "forbidden-provider"
        manifest["provider_neutrality"] = providerNeutrality
        refreshDigest(&manifest)

        let errors = CaptureDownstreamCandidateManifest.validationErrors(
            manifest: manifest,
            syncRows: syncRows,
            expectedVideoURI: "walkthrough.mov",
            expectedCoordinateFrameSessionId: "cfs-1",
            rightsConsent: rightsConsent()
        )

        #expect(errors.contains("downstream_candidate_third_party_upload_not_denied"))
        #expect(errors.contains("downstream_candidate_provider_selection_forbidden"))
    }

    @Test
    func timestampAndRawObservationMismatchFailsClosed() throws {
        let syncRows = makeSyncRows()
        var manifest = try makeManifest(syncRows: syncRows)
        var candidates = try #require(manifest["candidates"] as? [[String: Any]])
        candidates[1]["decoded_source_pts_sec"] = 99.0
        candidates[1]["frame_id"] = "999999"
        manifest["candidates"] = candidates
        refreshDigest(&manifest)

        let errors = CaptureDownstreamCandidateManifest.validationErrors(
            manifest: manifest,
            syncRows: syncRows,
            expectedVideoURI: "walkthrough.mov",
            expectedCoordinateFrameSessionId: "cfs-1",
            rightsConsent: rightsConsent()
        )

        #expect(errors.contains("downstream_candidate_frame_binding_mismatch:1"))
        #expect(errors.contains(
            "downstream_candidate_time_binding_mismatch:1:decoded_source_pts_sec"
        ))
    }

    @Test
    func trackingLossCannotBeMarkedPoseAssistedEligible() throws {
        let syncRows = makeSyncRows()
        var manifest = try makeManifest(syncRows: syncRows)
        var candidates = try #require(manifest["candidates"] as? [[String: Any]])
        candidates[1]["tracking_state"] = "limited"
        candidates[1]["tracking_reason"] = "relocalizing"
        candidates[1]["relocalization_event"] = true
        candidates[1]["pose_assisted_eligible"] = true
        manifest["candidates"] = candidates
        refreshDigest(&manifest)

        let errors = CaptureDownstreamCandidateManifest.validationErrors(
            manifest: manifest,
            syncRows: syncRows,
            expectedVideoURI: "walkthrough.mov",
            expectedCoordinateFrameSessionId: "cfs-1",
            rightsConsent: rightsConsent()
        )

        #expect(errors.contains("downstream_candidate_pose_eligibility_invalid:1"))
    }

    private func makeSyncRows() -> [[String: Any]] {
        [
            [
                "frame_id": "000001",
                "pose_frame_id": "000001",
                "encoded_frame_index": 0,
                "write_attempt_index": 0,
                "t_video_sec": 0.0,
                "decoded_source_pts_sec": 8123.25,
                "decoded_time_origin_pts_sec": 8123.25,
                "t_capture_sec": 0.0,
            ],
            [
                "frame_id": "000003",
                "pose_frame_id": "000003",
                "encoded_frame_index": 1,
                "write_attempt_index": 2,
                "t_video_sec": 0.066,
                "decoded_source_pts_sec": 8123.316,
                "decoded_time_origin_pts_sec": 8123.25,
                "t_capture_sec": 0.066,
            ],
        ]
    }

    private func makeManifest(syncRows: [[String: Any]]) throws -> [String: Any] {
        let identity: [[NSNumber]] = [
            [1, 0, 0, 0],
            [0, 1, 0, 0],
            [0, 0, 1, 0],
            [0, 0, 0, 1],
        ]
        let candidates: [[String: Any]] = syncRows.enumerated().map { ordinal, sync in
            [
                "candidate_id": String(format: "rgb_%06d", ordinal),
                "output_image_relative_path": String(
                    format: "candidate_rgb/%06d.png",
                    ordinal
                ),
                "source_video_uri": "walkthrough.mov",
                "decoded_frame_ordinal": ordinal,
                "encoded_frame_index": sync["encoded_frame_index"]!,
                "write_attempt_index": sync["write_attempt_index"]!,
                "decoded_pts_sec": sync["t_video_sec"]!,
                "decoded_source_pts_sec": sync["decoded_source_pts_sec"]!,
                "t_capture_sec": sync["t_capture_sec"]!,
                "frame_id": sync["frame_id"]!,
                "pose_frame_id": sync["pose_frame_id"]!,
                "coordinate_frame_session_id": "cfs-1",
                "T_site_camera": identity,
                "T_world_camera": identity,
                "camera_intrinsics": [
                    "fx": 1000.0,
                    "fy": 1000.0,
                    "cx": 960.0,
                    "cy": 720.0,
                    "width": 1920,
                    "height": 1440,
                ],
                "tracking_state": "normal",
                "relocalization_event": false,
                "pose_assisted_eligible": true,
            ]
        }
        var manifest: [String: Any] = [
            "schema_version": CaptureDownstreamCandidateManifest.schemaVersion,
            "source_video_uri": "walkthrough.mov",
            "source_video_sha256": String(repeating: "a", count: 64),
            "coordinate_frame_session_id": "cfs-1",
            "candidate_count": candidates.count,
            "provider_neutrality": [
                "mobile_app_direct_provider_upload_allowed": false,
                "third_party_provider_upload_authorized": false,
                "provider_selection_authority": "blueprint_pipeline",
            ],
            "allowed_use_scope": [
                "derived_processing_allowed": true,
                "latest_revocation_check_required": true,
                "redaction_required_before_derived_use": true,
            ],
            "candidates": candidates,
        ]
        refreshDigest(&manifest)
        return manifest
    }

    private func rightsConsent() -> [String: Any] {
        [
            "derived_scene_generation_allowed": true,
            "redaction_required": true,
        ]
    }

    private func refreshDigest(_ manifest: inout [String: Any]) {
        manifest.removeValue(forKey: "manifest_digest")
        manifest["manifest_digest"] = CaptureDownstreamCandidateManifest.canonicalDigest(
            of: manifest
        ) ?? "digest_unavailable"
    }
}
