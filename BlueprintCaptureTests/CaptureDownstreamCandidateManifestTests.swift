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
            frameRows: makeFrameRows(syncRows: syncRows),
            poseRows: makePoseRows(syncRows: syncRows),
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
            frameRows: makeFrameRows(syncRows: syncRows),
            poseRows: makePoseRows(syncRows: syncRows),
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
            frameRows: makeFrameRows(syncRows: syncRows),
            poseRows: makePoseRows(syncRows: syncRows),
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
            frameRows: makeFrameRows(syncRows: syncRows),
            poseRows: makePoseRows(syncRows: syncRows),
            expectedVideoURI: "walkthrough.mov",
            expectedCoordinateFrameSessionId: "cfs-1",
            rightsConsent: rightsConsent()
        )

        #expect(errors.contains("downstream_candidate_pose_eligibility_invalid:1"))
    }

    @Test
    func selectionClaimPoseAndIntrinsicsTamperingFailsClosed() throws {
        let syncRows = makeSyncRows()
        var manifest = try makeManifest(syncRows: syncRows)
        var selection = try #require(manifest["selection_contract"] as? [String: Any])
        selection["capture_default_selection"] = "all"
        manifest["selection_contract"] = selection
        var claimBoundary = try #require(manifest["claim_boundary"] as? [String: Any])
        claimBoundary["candidate_manifest_qualifies_metric_scale"] = true
        manifest["claim_boundary"] = claimBoundary
        var candidates = try #require(manifest["candidates"] as? [[String: Any]])
        candidates[0]["T_site_camera"] = [
            [1, 0, 0, 1],
            [0, 1, 0, 0],
            [0, 0, 1, 0],
            [0, 0, 0, 1],
        ]
        var intrinsics = try #require(candidates[0]["camera_intrinsics"] as? [String: Any])
        intrinsics["matrix_column_major"] = [
            999.0, 0.0, 0.0,
            0.0, 1000.0, 0.0,
            960.0, 720.0, 1.0,
        ]
        candidates[0]["camera_intrinsics"] = intrinsics
        candidates[0]["camera_calibration_digest"] =
            CaptureDownstreamCandidateManifest.canonicalDigest(of: intrinsics)
        manifest["candidates"] = candidates
        refreshDigest(&manifest)

        let errors = CaptureDownstreamCandidateManifest.validationErrors(
            manifest: manifest,
            syncRows: syncRows,
            frameRows: makeFrameRows(syncRows: syncRows),
            poseRows: makePoseRows(syncRows: syncRows),
            expectedVideoURI: "walkthrough.mov",
            expectedCoordinateFrameSessionId: "cfs-1",
            rightsConsent: rightsConsent()
        )

        #expect(errors.contains("downstream_candidate_selection_contract_invalid"))
        #expect(errors.contains("downstream_candidate_claim_boundary_invalid"))
        #expect(errors.contains("downstream_candidate_pose_binding_mismatch:0"))
        #expect(errors.contains("downstream_candidate_intrinsics_binding_mismatch:0"))
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
        let frames = makeFrameRows(syncRows: syncRows)
        let candidates: [[String: Any]] = syncRows.enumerated().map { ordinal, sync in
            let intrinsics: [String: Any] = [
                "fx": 1000.0,
                "fy": 1000.0,
                "cx": 960.0,
                "cy": 720.0,
                "width": 1920,
                "height": 1440,
                "matrix_column_major": frames[ordinal]["intrinsics"]!,
                "authority": "arkit_arframe_exact_per_observation",
            ]
            return [
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
                "site_frame_id": "cfs-1",
                "site_frame_definition": "arkit_world_origin_at_session_start",
                "transform_semantics": "row_major_camera_to_site",
                "T_site_camera": identity,
                "T_world_camera": identity,
                "units": "meters",
                "handedness": "right_handed",
                "up_axis": "Y",
                "gravity_aligned": true,
                "camera_intrinsics": intrinsics,
                "camera_calibration_digest": CaptureDownstreamCandidateManifest.canonicalDigest(
                    of: intrinsics
                )!,
                "arkit_frame_row_ordinal": ordinal,
                "arkit_pose_row_ordinal": ordinal,
                "tracking_state": "normal",
                "relocalization_event": false,
                "pose_assisted_eligible": true,
                "raw_observation_authority": true,
                "downstream_artifact_authority": false,
            ]
        }
        var manifest: [String: Any] = [
            "schema_version": CaptureDownstreamCandidateManifest.schemaVersion,
            "source_video_uri": "walkthrough.mov",
            "source_video_sha256": String(repeating: "a", count: 64),
            "source_video_authority": "immutable_raw_capture_video",
            "decoded_timing_authority": "sync_map_decoded_sample_presentation_timestamps",
            "coordinate_frame_session_id": "cfs-1",
            "candidate_count": candidates.count,
            "candidate_order": "encoded_frame_index_ascending",
            "selection_contract": [
                "selection_authority": "blueprint_pipeline_task_site_profile",
                "capture_default_selection": NSNull(),
                "selection_parameters_required": true,
                "allowed_deterministic_selectors": [
                    "explicit_encoded_frame_ordinals",
                    "profile_bound_even_decoded_pts_coverage",
                    "profile_bound_quality_filter",
                ],
                "smallest_missing_input_when_unselectable":
                    "task_site_evidence_profile_with_frame_selection_parameters",
            ],
            "provider_neutrality": [
                "mobile_app_direct_provider_upload_allowed": false,
                "third_party_provider_upload_authorized": false,
                "provider_selection_authority": "blueprint_pipeline",
                "provider_authorization_status": "not_granted_by_capture_manifest",
            ],
            "allowed_use_scope": [
                "raw_observation_indexing_allowed": true,
                "derived_processing_allowed": true,
                "data_licensing_allowed": false,
                "latest_revocation_check_required": true,
                "redaction_required_before_derived_use": true,
                "provider_upload_requires_separate_downstream_authorization": true,
            ],
            "claim_boundary": [
                "raw_capture_remains_authoritative": true,
                "candidate_manifest_qualifies_reconstruction": false,
                "candidate_manifest_qualifies_metric_scale": false,
                "candidate_manifest_qualifies_collision_or_physics": false,
                "candidate_manifest_proves_task_success": false,
            ],
            "candidates": candidates,
        ]
        refreshDigest(&manifest)
        return manifest
    }

    private func rightsConsent() -> [String: Any] {
        [
            "derived_scene_generation_allowed": true,
            "data_licensing_allowed": false,
            "redaction_required": true,
        ]
    }

    private func makeFrameRows(syncRows: [[String: Any]]) -> [[String: Any]] {
        syncRows.map { sync in
            [
                "frame_id": sync["frame_id"]!,
                "intrinsics": [
                    1000.0, 0.0, 0.0,
                    0.0, 1000.0, 0.0,
                    960.0, 720.0, 1.0,
                ],
                "image_resolution": [1920, 1440],
            ]
        }
    }

    private func makePoseRows(syncRows: [[String: Any]]) -> [[String: Any]] {
        let identity: [[NSNumber]] = [
            [1, 0, 0, 0],
            [0, 1, 0, 0],
            [0, 0, 1, 0],
            [0, 0, 0, 1],
        ]
        return syncRows.map { sync in
            [
                "frame_id": sync["pose_frame_id"]!,
                "T_site_camera": identity,
                "T_world_camera": identity,
            ]
        }
    }

    private func refreshDigest(_ manifest: inout [String: Any]) {
        manifest.removeValue(forKey: "manifest_digest")
        manifest["manifest_digest"] = CaptureDownstreamCandidateManifest.canonicalDigest(
            of: manifest
        ) ?? "digest_unavailable"
    }

    @Test
    func canonicalDigestUsesProductionJavaScriptNumberEncoding() {
        let payload: [String: Any] = [
            "integral": 1.0,
            "negative_zero": -0.0,
            "small": 1e-8,
            "fixed_threshold": 1e-6,
            "large_fixed": 1e20,
        ]

        #expect(
            CaptureDownstreamCandidateManifest.canonicalDigest(of: payload)
                == "sha256:ddea0aaf526b362e0655f6a9dea48ca07d3c6cf7b7b4b0ed0aee0e25541af5a0"
        )
    }
}
