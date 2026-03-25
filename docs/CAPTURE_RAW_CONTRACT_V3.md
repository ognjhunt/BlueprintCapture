# Capture Raw Contract V3

This document defines the canonical raw capture bundle contract for site walkthrough capture in `BlueprintCapture`.

It is intentionally stricter than the bridge compatibility layer in [/Users/nijelhunt_1/workspace/BlueprintCapture/cloud/extract-frames/src/index.ts](/Users/nijelhunt_1/workspace/BlueprintCapture/cloud/extract-frames/src/index.ts). Compatibility parsing for older bundles is a bridge concern. V3 is the format new raw bundles should write.

## Additive V3.1 Update

`capture_schema_version = 3.1.0` keeps `schema_version = "v3"` while extending the contract across iPhone, Android, and glasses modalities.

New bundles remain backward-compatible but must additionally emit:

- top-level `capture_profile_id`
- top-level `capture_capabilities`
- modality-specific sidecars under `arkit/`, `arcore/`, `glasses/`, and `companion_phone/` only when those signals are truthfully available

Raw first-party evidence remains authoritative. Derived geometry remains separate and non-authoritative.

## Goals

- Keep raw capture independent of any single world-model provider.
- Preserve enough truth to swap downstream backends without re-capturing sites.
- Make coordinate frames, timing, depth, quality, and rights unambiguous.
- Fail early on malformed or weak raw bundles instead of letting ambiguity leak downstream.

## Canonical Path

```text
scenes/{scene_id}/captures/{capture_id}/raw/
```

## Canonical Bundle Layout

```text
raw/
  manifest.json                              required
  provenance.json                            required
  rights_consent.json                        required
  capture_context.json                       required
  intake_packet.json                         required
  task_hypothesis.json                       required
  recording_session.json                     required
  capture_topology.json                      required
  route_anchors.json                         required
  checkpoint_events.json                     required
  relocalization_events.json                 required
  overlap_graph.json                         required
  video_track.json                           required
  hashes.json                                required
  capture_upload_complete.json               required
  walkthrough.mov                            required
  sync_map.jsonl                             required
  motion.jsonl                               required
  semantic_anchor_observations.jsonl         required
  glasses/
    stream_metadata.json                     required for glasses
    frame_timestamps.jsonl                   required for glasses
    device_state.jsonl                       required for glasses
    health_events.jsonl                      required for glasses
  companion_phone/
    poses.jsonl                              required when companion_phone_pose=true
    session_intrinsics.json                  required when companion_phone_intrinsics=true
    calibration.json                         required when companion_phone_calibration=true
  arkit/
    poses.jsonl                              required for iphone
    frames.jsonl                             required for iphone
    frame_quality.jsonl                      required for iphone
    session_intrinsics.json                  required for iphone
    per_frame_camera_state.jsonl             required for iphone
    feature_points.jsonl                     required when feature_points=true
    plane_observations.jsonl                 required when planes=true
    light_estimates.jsonl                    required when light_estimate=true
    depth_manifest.json                      required when depth_supported=true
    confidence_manifest.json                 required when depth_supported=true
    depth/*.png                              required when depth_supported=true
    confidence/*.png                         required when depth_supported=true
    mesh_manifest.json                       optional but high-value
    meshes/*.obj                             optional but high-value
  arcore/
    poses.jsonl                              required when camera_pose=true and geometry_source=arcore
    frames.jsonl                             required when camera_pose=true and geometry_source=arcore
    session_intrinsics.json                  required when camera_intrinsics=true and geometry_source=arcore
    tracking_state.jsonl                     required when tracking_state=true and geometry_source=arcore
    point_cloud.jsonl                        required when point_cloud=true
    planes.jsonl                             required when planes=true and geometry_source=arcore
    light_estimates.jsonl                    required when light_estimate=true and geometry_source=arcore
    depth_manifest.json                      required when depth=true and geometry_source=arcore
    confidence_manifest.json                 required when depth_confidence=true and geometry_source=arcore
```

## Global Rules

### Serialization

- All JSON keys must be `snake_case`.
- Every JSON object file must include `schema_version`.
- All timestamps with wall-clock meaning must use UTC ISO-8601 strings.
- All durations must be seconds as floating-point values.
- All monotonic capture timestamps must use integer nanoseconds in `t_monotonic_ns` when available.
- All distances and transforms must use meters.

### Identity

- `scene_id`, `capture_id`, and `coordinate_frame_session_id` must agree across all sidecars.
- `frame_id` must be six-digit, zero-padded, unique, and monotonic within the recording.
- One V3 bundle represents one canonical recording session. If ARKit resets into a new world frame, the reset must either:
  - split into a new capture, or
  - be explicitly recorded as a discontinuity with a new `coordinate_frame_session_id` segment.

### Coordinate Frame Truth

- `T_world_camera` means a row-major 4x4 transform that maps camera coordinates into the world frame.
- The world frame must be right-handed, meter-scaled, and ARKit-aligned.
- `recording_session.json` must explicitly state:
  - world-frame definition
  - units
  - handedness
  - gravity alignment
  - whether resets occurred
- A consumer must not infer transform meaning from file name alone.

### Time And Synchronization

- `t_capture_sec` is the canonical capture-relative time used across video, pose, motion, depth, anchors, and relocalization.
- `t_capture_sec = 0.0` is the first retained video frame in `walkthrough.mov`.
- `t_video_sec` is the decoded video presentation time for downstream extracted frames.
- `t_monotonic_ns` is the preferred cross-stream join key when available.
- Any stream that cannot be aligned to canonical capture time must say so explicitly with a status field. It must not silently omit timing semantics.

### Missing Data Semantics

- `null` means the field is known but unavailable for this record.
- Empty arrays mean the file is present and the set is empty.
- Absent fields are only allowed when the file schema marks them optional.
- Depth absence must be distinguished between:
  - `not_supported`
  - `not_enabled`
  - `temporarily_unavailable`
  - `dropped_at_write`
  - `invalid_for_frame`

### Rights And Provenance

- Rights must be explicit, conservative, and fail-closed.
- Derived generation, licensing, and payout eligibility must not be inferred from job type alone.
- Consent evidence source and permission document hash must be preserved.
- Raw bundle finalization must write a hash manifest for all contract files.

## Required Files

### `manifest.json`

Purpose:
- Top-level identity, modality, device, capture, and declared capability metadata.

Required fields:
- `schema_version`
- `capture_schema_version`
- `scene_id`
- `capture_id`
- `capture_source`
- `capture_tier_hint`
- `capture_profile_id`
- `capture_capabilities`
- `coordinate_frame_session_id`
- `video_uri`
- `capture_start_epoch_ms`
- `app_version`
- `app_build`
- `ios_version`
- `ios_build`
- `hardware_model_identifier`
- `device_model_marketing`
- `has_lidar`
- `depth_supported`
- `fps_source`
- `width`
- `height`
- `rights_profile`
- `requested_outputs`

`capture_profile_id` values currently written:

- `iphone_arkit_lidar`
- `iphone_arkit_non_lidar`
- `android_arcore_depth`
- `android_arcore_pose_only`
- `android_camera_only`
- `glasses_pov`
- `glasses_pov_companion_phone`

`capture_capabilities` carries:

- neutral availability flags such as `camera_pose`, `camera_intrinsics`, `depth`, `depth_confidence`, `point_cloud`, `planes`, `feature_points`, `tracking_state`, `relocalization_events`, `light_estimate`, `motion`, `motion_authoritative`, `companion_phone_pose`, `companion_phone_intrinsics`, `companion_phone_calibration`
- normalized evidence counters such as `pose_rows`, `intrinsics_valid`, `depth_frames`, `confidence_frames`, `mesh_files`, `point_cloud_samples`, `plane_rows`, `feature_point_rows`, `tracking_state_rows`, `relocalization_event_rows`, `light_estimate_rows`, `motion_samples`
- authority labels such as `pose_authority`, `intrinsics_authority`, `depth_authority`, `motion_authority`
- `motion_provenance`
- `geometry_source`
- `geometry_expected_downstream`

Example:

```json
{
  "schema_version": "v3",
  "capture_schema_version": "3.0.0",
  "scene_id": "scene_warehouse_a",
  "capture_id": "cap_20260320_001",
  "capture_source": "iphone",
  "capture_tier_hint": "tier1_iphone",
  "coordinate_frame_session_id": "cfs_8ec7d26d-1f0e-4ed0-86de-5b3c6d4c7d91",
  "video_uri": "raw/walkthrough.mov",
  "capture_start_epoch_ms": 1774015205123,
  "app_version": "1.18.0",
  "app_build": "241",
  "ios_version": "18.3.1",
  "ios_build": "22D68",
  "hardware_model_identifier": "iPhone16,2",
  "device_model_marketing": "iPhone 15 Pro",
  "has_lidar": true,
  "depth_supported": true,
  "fps_source": 30.0,
  "width": 1920,
  "height": 1440,
  "video_codec": "h264",
  "color_space": "bt709",
  "rights_profile": "documented_permission",
  "requested_outputs": ["qualification", "scene_memory", "preview_simulation"]
}
```

### `provenance.json`

Purpose:
- Preserve chain-of-custody, capture app identity, and artifact provenance.

Required fields:
- `schema_version`
- `scene_id`
- `capture_id`
- `capture_source`
- `captured_by_user_id`
- `uploaded_by_user_id`
- `capture_app_build`
- `capture_app_version`
- `bundle_created_at`
- `upload_completed_at`
- `bundle_sha256`

Example:

```json
{
  "schema_version": "v1",
  "scene_id": "scene_warehouse_a",
  "capture_id": "cap_20260320_001",
  "capture_source": "iphone",
  "captured_by_user_id": "user_123",
  "uploaded_by_user_id": "user_123",
  "capture_app_build": "241",
  "capture_app_version": "1.18.0",
  "device_installation_id": "install_7b8a0d2d",
  "bundle_created_at": "2026-03-20T14:00:15Z",
  "upload_completed_at": "2026-03-20T14:03:02Z",
  "bundle_sha256": "9f3e91e7855b45d7648e4f6f931ae5fe9f540f5313a6a22e76ac8d7b31fca12d"
}
```

### `rights_consent.json`

Purpose:
- Preserve downstream rights, consent basis, and commercialization boundaries.

Required fields:
- `schema_version`
- `scene_id`
- `capture_id`
- `consent_status`
- `capture_basis`
- `derived_scene_generation_allowed`
- `data_licensing_allowed`
- `capture_contributor_payout_eligible`
- `permission_document_uri`
- `permission_document_sha256`
- `consent_scope`
- `consent_notes`
- `redaction_required`

Example:

```json
{
  "schema_version": "v1",
  "scene_id": "scene_warehouse_a",
  "capture_id": "cap_20260320_001",
  "consent_status": "documented",
  "capture_basis": "site_operator_permission",
  "derived_scene_generation_allowed": true,
  "data_licensing_allowed": false,
  "capture_contributor_payout_eligible": true,
  "permission_document_uri": "gs://blueprint-secure/permissions/perm_123.pdf",
  "permission_document_sha256": "1f5d3b7c4d947764930a7a33a6f0a9ef9c8d4bce6e8a7d5b1ffceac28ddf417e",
  "consent_scope": ["entry", "dock_a", "main_aisle"],
  "consent_notes": ["No employee faces in derived media", "Do not expose control room signage"],
  "redaction_required": true,
  "retention_policy": "standard_blueprint_site_capture"
}
```

### `capture_context.json`

Purpose:
- Preserve business context, intake resolution, scene-memory intent, and normalized capture evidence summary.

Required fields:
- `schema_version`
- `scene_id`
- `capture_id`
- `site_submission_id`
- `buyer_request_id`
- `capture_job_id`
- `capture_source`
- `requested_outputs`
- `scene_memory_capture`
- `capture_evidence`
- `capture_rights`

Example:

```json
{
  "schema_version": "v1",
  "scene_id": "scene_warehouse_a",
  "capture_id": "cap_20260320_001",
  "site_submission_id": "sub_456",
  "buyer_request_id": "req_789",
  "capture_job_id": "job_321",
  "region_id": "nyc_metro",
  "capture_source": "iphone_video",
  "requested_outputs": ["qualification", "scene_memory", "preview_simulation"],
  "capture_modality": "iphone_arkit_lidar",
  "evidence_tier": "qualified_metric_capture",
  "task_text_hint": "Inbound pallet walk",
  "task_steps": ["Enter dock door", "Walk receiving lane", "Pause at handoff point"],
  "scene_memory_capture": {
    "continuity_score": 0.92,
    "lighting_consistency": "stable",
    "dynamic_object_density": "medium",
    "semantic_anchors_observed": ["entrance", "dock_turn", "handoff_point"],
    "relocalization_count": 1,
    "overlap_checkpoint_count": 3,
    "world_model_candidate": true
  },
  "capture_evidence": {
    "arkit_frame_rows": 1842,
    "arkit_pose_rows": 1842,
    "arkit_intrinsics_valid": true,
    "arkit_depth_frames": 771,
    "arkit_confidence_frames": 771,
    "arkit_mesh_files": 0,
    "motion_samples": 2365,
    "motion_provenance": "iphone_device_imu",
    "motion_timestamps_capture_relative": true
  },
  "capture_rights": {
    "consent_status": "documented",
    "derived_scene_generation_allowed": true,
    "data_licensing_allowed": false,
    "capture_contributor_payout_eligible": true
  }
}
```

### `intake_packet.json`

Purpose:
- Preserve authoritative or resolved site/task intake.

Required fields:
- `schema_version`
- `workflow_name`
- `task_steps`

Example:

```json
{
  "schema_version": "v1",
  "workflow_name": "Inbound pallet walk",
  "task_steps": ["Enter dock door", "Walk receiving lane", "Pause at handoff point"],
  "target_kpi": "clearance_ok",
  "zone": "dock_a",
  "shift": "day",
  "owner": "receiving_ops",
  "required_coverage_areas": ["dock_threshold", "receiving_lane", "handoff_area"],
  "capture_restrictions": ["Do not enter control cage"],
  "privacy_security_limits": ["Blur employee badges if readable"]
}
```

### `task_hypothesis.json`

Purpose:
- Preserve the resolved task hypothesis, including whether it came from authoritative intake, manual entry, or AI inference.

Required fields:
- `schema_version`
- `workflow_name`
- `task_steps`
- `source`
- `status`

Example:

```json
{
  "schema_version": "v1",
  "workflow_name": "Inbound pallet walk",
  "task_steps": ["Enter dock door", "Walk receiving lane", "Pause at handoff point"],
  "target_kpi": "clearance_ok",
  "zone": "dock_a",
  "owner": "receiving_ops",
  "confidence": 0.91,
  "source": "authoritative",
  "model": null,
  "fps": null,
  "warnings": [],
  "status": "accepted"
}
```

### `recording_session.json`

Purpose:
- Declare the canonical recording and coordinate-frame session.

Required fields:
- `schema_version`
- `scene_id`
- `capture_id`
- `coordinate_frame_session_id`
- `arkit_session_id`
- `world_frame_definition`
- `units`
- `handedness`
- `gravity_aligned`
- `session_reset_count`

Example:

```json
{
  "schema_version": "v1",
  "scene_id": "scene_warehouse_a",
  "capture_id": "cap_20260320_001",
  "site_visit_id": "visit_9001",
  "route_id": "route_receiving_v2",
  "pass_id": "pass_primary_1",
  "pass_index": 1,
  "pass_role": "primary",
  "coordinate_frame_session_id": "cfs_8ec7d26d-1f0e-4ed0-86de-5b3c6d4c7d91",
  "arkit_session_id": "arkit_8ec7d26d-1f0e-4ed0-86de-5b3c6d4c7d91",
  "world_frame_definition": "arkit_world_origin_at_session_start",
  "units": "meters",
  "handedness": "right_handed",
  "gravity_aligned": true,
  "session_reset_count": 0,
  "captured_at": "2026-03-20T14:00:05Z"
}
```

### `capture_topology.json`

Purpose:
- Preserve route/pass structure and revisit alignment metadata.

Required fields:
- `schema_version`
- `capture_session_id`
- `route_id`
- `pass_id`
- `pass_index`
- `intended_pass_role`
- `coordinate_frame_session_id`

Example:

```json
{
  "schema_version": "v1",
  "capture_session_id": "visit_9001",
  "route_id": "route_receiving_v2",
  "pass_id": "pass_primary_1",
  "pass_index": 1,
  "intended_pass_role": "primary",
  "entry_anchor_id": "anchor_entry",
  "return_anchor_id": "anchor_exit",
  "entry_anchor_t_capture_sec": 2.146,
  "entry_anchor_hold_duration_sec": 2.041,
  "site_visit_id": "visit_9001",
  "coordinate_frame_session_id": "cfs_8ec7d26d-1f0e-4ed0-86de-5b3c6d4c7d91",
  "arkit_session_id": "arkit_8ec7d26d-1f0e-4ed0-86de-5b3c6d4c7d91"
}
```

### `route_anchors.json`

Purpose:
- Define the expected anchor set for the route.

Required fields:
- `schema_version`
- `route_anchors`

Example:

```json
{
  "schema_version": "v1",
  "route_anchors": [
    {
      "anchor_id": "anchor_entry",
      "anchor_type": "entry",
      "label": "Receiving entry",
      "expected_observation": "pause_and_pan",
      "required_in_primary_pass": true,
      "required_in_revisit_pass": true
    },
    {
      "anchor_id": "anchor_handoff_01",
      "anchor_type": "handoff_point",
      "label": "Pallet handoff point",
      "expected_observation": "tap_marker",
      "required_in_primary_pass": false,
      "required_in_revisit_pass": true
    }
  ]
}
```

### `checkpoint_events.json`

Purpose:
- Record actual anchor/checkpoint completion events.

Required fields:
- `schema_version`
- `checkpoint_events`

Example:

```json
{
  "schema_version": "v1",
  "checkpoint_events": [
    {
      "anchor_id": "anchor_entry",
      "pass_id": "pass_primary_1",
      "t_capture_sec": 2.146,
      "hold_duration_sec": 2.041,
      "completed": true
    },
    {
      "anchor_id": "anchor_handoff_01",
      "pass_id": "pass_primary_1",
      "t_capture_sec": 41.882,
      "hold_duration_sec": 0.0,
      "completed": true
    }
  ]
}
```

### `relocalization_events.json`

Purpose:
- Record tracking-loss or relocalization windows explicitly.

Required fields:
- `schema_version`
- `relocalization_events`

Example:

```json
{
  "schema_version": "v1",
  "relocalization_events": [
    {
      "event_id": "reloc_0001",
      "coordinate_frame_session_id": "cfs_8ec7d26d-1f0e-4ed0-86de-5b3c6d4c7d91",
      "start_frame_id": "000742",
      "end_frame_id": "000759",
      "start_t_capture_sec": 24.733,
      "end_t_capture_sec": 25.312,
      "frame_count": 18,
      "poses_usable": false,
      "recovered": true
    }
  ]
}
```

### `overlap_graph.json`

Purpose:
- Summarize overlap/revisit structure for retrieval and relocalization reasoning.

Required fields:
- `schema_version`
- `coordinate_frame_session_id`
- `observed_anchor_ids`
- `semantic_anchor_ids`

Example:

```json
{
  "schema_version": "v1",
  "site_visit_id": "visit_9001",
  "route_id": "route_receiving_v2",
  "pass_id": "pass_primary_1",
  "pass_role": "primary",
  "coordinate_frame_session_id": "cfs_8ec7d26d-1f0e-4ed0-86de-5b3c6d4c7d91",
  "observed_anchor_ids": ["anchor_entry", "anchor_handoff_01"],
  "semantic_anchor_ids": ["entrance", "dock_turn", "handoff_point"],
  "relocalization_event_count": 1
}
```

### `video_track.json`

Purpose:
- Preserve canonical video timing and encoding properties.

Required fields:
- `schema_version`
- `video_file`
- `duration_sec`
- `frame_count`
- `nominal_fps`
- `contains_vfr`
- `width`
- `height`
- `orientation`
- `codec`
- `color_space`

Example:

```json
{
  "schema_version": "v1",
  "video_file": "walkthrough.mov",
  "duration_sec": 61.433,
  "frame_count": 1842,
  "nominal_fps": 30.0,
  "contains_vfr": false,
  "video_start_pts_sec": 0.0,
  "width": 1920,
  "height": 1440,
  "orientation": "portrait",
  "codec": "h264",
  "color_space": "bt709"
}
```

### `hashes.json`

Purpose:
- Preserve hashes for validator and provenance checks.

Required fields:
- `schema_version`
- `bundle_sha256`
- `artifacts`

Example:

```json
{
  "schema_version": "v1",
  "bundle_sha256": "9f3e91e7855b45d7648e4f6f931ae5fe9f540f5313a6a22e76ac8d7b31fca12d",
  "artifacts": {
    "manifest.json": "efea7df5a6939dd6f2a1f36935cf2a1f8edc0193f8f901f0a6650c690f4d7464",
    "provenance.json": "95d2789e14696cb9bd9fcf0da09df7728fe64098a8bc6f260f1849575fc4317f",
    "rights_consent.json": "df806db6746bb6b8421c2cb7a6859b70cb36d5d5fbaf80c1c991ef79ca19db71",
    "walkthrough.mov": "f47f52f08d9df8de2f7fd7f23602a5bcc1c3f19a1b3dfd14ce58bc5bf48de809",
    "arkit/poses.jsonl": "c59c2d60bfd0b3e56d8be1465d7da78cd0634d8447d70e12b1a0de9860d2b8c9"
  }
}
```

### `capture_upload_complete.json`

Purpose:
- Marker that the raw bundle is finalized and ready for bridge ingestion.

Required fields:
- `schema_version`
- `scene_id`
- `capture_id`
- `raw_prefix`
- `completed_at`

Example:

```json
{
  "schema_version": "v1",
  "scene_id": "scene_warehouse_a",
  "capture_id": "cap_20260320_001",
  "raw_prefix": "scenes/scene_warehouse_a/captures/cap_20260320_001/raw",
  "completed_at": "2026-03-20T14:03:02Z"
}
```

### `sync_map.jsonl`

Purpose:
- Canonical cross-stream timing map for extracted video frames, poses, and motion alignment.

Required per-line fields:
- `frame_id`
- `t_video_sec`
- `t_capture_sec`
- `t_monotonic_ns`
- `pose_frame_id`
- `sync_status`
- `delta_ms`

Example line:

```json
{"frame_id":"000742","t_video_sec":24.733333,"t_capture_sec":24.733333,"t_monotonic_ns":91234567890123,"pose_frame_id":"000742","motion_sample_time":{"before_ns":91234567880000,"after_ns":91234567900000},"sync_status":"exact_frame_id_match","delta_ms":0.0}
```

### `motion.jsonl`

Purpose:
- Preserve phone IMU samples with canonical capture-relative timing.

Required per-line fields:
- `timestamp`
- `t_capture_sec`
- `t_monotonic_ns`
- `wall_time`
- `motion_provenance`
- `attitude`
- `rotation_rate`
- `gravity`
- `user_acceleration`

Example line:

```json
{"timestamp":8123.3371,"t_capture_sec":24.731882,"t_monotonic_ns":91234567880000,"wall_time":"2026-03-20T14:00:29.857Z","motion_provenance":"iphone_device_imu","attitude":{"roll":0.012,"pitch":-0.084,"yaw":1.993,"quaternion":{"x":0.001,"y":-0.041,"z":0.839,"w":0.543}},"rotation_rate":{"x":0.003,"y":-0.004,"z":0.007},"gravity":{"x":0.017,"y":-0.998,"z":0.052},"user_acceleration":{"x":0.011,"y":0.022,"z":-0.006}}
```

### `semantic_anchor_observations.jsonl`

Purpose:
- Preserve concrete semantic anchor instances and their observations.

Required per-line fields:
- `anchor_instance_id`
- `anchor_type`
- `frame_id`
- `t_capture_sec`
- `coordinate_frame_session_id`
- `observation_method`

Example line:

```json
{"anchor_instance_id":"anchor_handoff_01","anchor_type":"handoff_point","label":"Pallet handoff","frame_id":"001233","t_capture_sec":41.882,"t_monotonic_ns":91256700110000,"coordinate_frame_session_id":"cfs_8ec7d26d-1f0e-4ed0-86de-5b3c6d4c7d91","observation_method":"manual_tap","confidence":1.0,"notes":null}
```

## Required `arkit/` Files

### `arkit/poses.jsonl`

Purpose:
- Canonical camera pose timeline.

Required per-line fields:
- `pose_schema_version`
- `frame_id`
- `t_capture_sec`
- `t_monotonic_ns`
- `coordinate_frame_session_id`
- `T_world_camera`
- `tracking_state`
- `tracking_reason`
- `world_mapping_status`

Example line:

```json
{"pose_schema_version":"3.0","frame_id":"000742","t_capture_sec":24.733333,"t_monotonic_ns":91234567890123,"coordinate_frame_session_id":"cfs_8ec7d26d-1f0e-4ed0-86de-5b3c6d4c7d91","T_world_camera":[[0.9998,0.0003,0.0174,2.418],[0.0001,0.9999,-0.0085,1.531],[-0.0174,0.0085,0.9998,-4.202],[0.0,0.0,0.0,1.0]],"tracking_state":"normal","tracking_reason":null,"world_mapping_status":"mapped"}
```

### `arkit/frames.jsonl`

Purpose:
- Preserve raw AR frame metadata before downstream normalization.

Required per-line fields:
- `frame_id`
- `frame_index`
- `timestamp`
- `t_capture_sec`
- `t_monotonic_ns`
- `captured_at`
- `camera_transform`
- `intrinsics`
- `image_resolution`
- `coordinate_frame_session_id`

Example line:

```json
{"frame_id":"000742","frame_index":741,"timestamp":8123.3382,"t_capture_sec":24.733333,"t_monotonic_ns":91234567890123,"captured_at":"2026-03-20T14:00:29.858Z","camera_transform":[1.0,0.0,0.0,2.418,0.0,1.0,0.0,1.531,0.0,0.0,1.0,-4.202,0.0,0.0,0.0,1.0],"intrinsics":[1452.2,0.0,0.0,0.0,1450.9,0.0,959.4,719.2,1.0],"image_resolution":[1920,1440],"tracking_state":"normal","tracking_reason":null,"world_mapping_status":"mapped","relocalization_event":false,"depth_source":"smoothed_scene_depth","scene_depth_file":null,"smoothed_scene_depth_file":"arkit/depth/000742.png","confidence_file":"arkit/confidence/000742.png","depth_valid_fraction":0.83,"missing_depth_fraction":0.17,"sharpness_score":129.4,"anchor_observations":["anchor_entry"],"coordinate_frame_session_id":"cfs_8ec7d26d-1f0e-4ed0-86de-5b3c6d4c7d91"}
```

### `arkit/frame_quality.jsonl`

Purpose:
- Preserve per-frame quality and usability decisions.

Required per-line fields:
- `frame_id`
- `t_capture_sec`
- `tracking_state`
- `tracking_reason`
- `world_mapping_status`
- `relocalization_event`
- `sharpness_score`
- `usable_for_pose`
- `usable_for_depth`

Example line:

```json
{"frame_id":"000742","t_capture_sec":24.733333,"tracking_state":"normal","tracking_reason":null,"world_mapping_status":"mapped","relocalization_event":false,"sharpness_score":129.4,"depth_source":"smoothed_scene_depth","depth_valid_fraction":0.83,"missing_depth_fraction":0.17,"exposure_duration_s":0.008333,"iso":64.0,"exposure_target_bias":0.0,"white_balance_gains":{"red":2.01,"green":1.0,"blue":1.72},"anchor_observations":["anchor_entry"],"coordinate_frame_session_id":"cfs_8ec7d26d-1f0e-4ed0-86de-5b3c6d4c7d91","usable_for_pose":true,"usable_for_depth":true}
```

### `arkit/session_intrinsics.json`

Purpose:
- Preserve canonical intrinsics and camera model semantics.

Required fields:
- `schema_version`
- `coordinate_frame_session_id`
- `intrinsics`
- `camera_model`
- `principal_point_reference`
- `distortion_model`
- `distortion_coeffs`

Example:

```json
{
  "schema_version": "v1",
  "coordinate_frame_session_id": "cfs_8ec7d26d-1f0e-4ed0-86de-5b3c6d4c7d91",
  "camera_model": "pinhole",
  "principal_point_reference": "full_resolution_image",
  "distortion_model": "apple_standard",
  "distortion_coeffs": [],
  "intrinsics": {
    "fx": 1452.2,
    "fy": 1450.9,
    "cx": 959.4,
    "cy": 719.2,
    "width": 1920,
    "height": 1440
  },
  "camera_intrinsics": {
    "resolution_width": 1920,
    "resolution_height": 1440,
    "intrinsic_matrix": [1452.2, 0.0, 0.0, 0.0, 1450.9, 0.0, 959.4, 719.2, 1.0]
  },
  "exposure_settings": {
    "mode": "arSession",
    "white_balance_mode": "automatic",
    "point_of_interest": null
  }
}
```

### `arkit/per_frame_camera_state.jsonl`

Purpose:
- Preserve any camera state that can vary per frame and affect future backend interpretation.

Required per-line fields:
- `frame_id`
- `t_capture_sec`
- `coordinate_frame_session_id`

Recommended fields:
- `zoom_factor`
- `focus_mode`
- `focus_locked`
- `exposure_mode`
- `exposure_locked`
- `white_balance_mode`
- `video_stabilization_mode`
- `torch_active`
- `hdr_active`

Example line:

```json
{"frame_id":"000742","t_capture_sec":24.733333,"coordinate_frame_session_id":"cfs_8ec7d26d-1f0e-4ed0-86de-5b3c6d4c7d91","zoom_factor":1.0,"focus_mode":"continuous_auto_focus","focus_locked":false,"exposure_mode":"continuous_auto_exposure","exposure_locked":false,"white_balance_mode":"automatic","video_stabilization_mode":"standard","torch_active":false,"hdr_active":false}
```

### `arkit/depth_manifest.json`

Purpose:
- Define depth encoding, units, and missing-depth semantics.

Required fields:
- `schema_version`
- `coordinate_frame_session_id`
- `representation`
- `encoding`
- `units`
- `invalid_value_semantics`
- `missing_depth_reason`
- `frames`

Example:

```json
{
  "schema_version": "v1",
  "coordinate_frame_session_id": "cfs_8ec7d26d-1f0e-4ed0-86de-5b3c6d4c7d91",
  "representation": "per_frame_depth_map",
  "encoding": "png_u16_mm",
  "units": "millimeters",
  "invalid_value_semantics": "0_means_missing",
  "missing_depth_reason": null,
  "frames": [
    {
      "frame_id": "000742",
      "depth_path": "arkit/depth/000742.png",
      "width": 256,
      "height": 192,
      "depth_source": "smoothed_scene_depth",
      "depth_valid_fraction": 0.83,
      "missing_depth_fraction": 0.17,
      "paired_confidence_path": "arkit/confidence/000742.png"
    }
  ]
}
```

### `arkit/confidence_manifest.json`

Purpose:
- Define depth-confidence semantics and pairing.

Required fields:
- `schema_version`
- `coordinate_frame_session_id`
- `representation`
- `encoding`
- `confidence_scale`
- `frames`

Example:

```json
{
  "schema_version": "v1",
  "coordinate_frame_session_id": "cfs_8ec7d26d-1f0e-4ed0-86de-5b3c6d4c7d91",
  "representation": "per_frame_confidence_map",
  "encoding": "png_u8",
  "confidence_scale": {
    "0": "low_or_missing",
    "1": "medium",
    "2": "high"
  },
  "frames": [
    {
      "frame_id": "000742",
      "confidence_path": "arkit/confidence/000742.png",
      "paired_depth_path": "arkit/depth/000742.png"
    }
  ]
}
```

## Optional But High-Value `arkit/` Files

### `arkit/mesh_manifest.json`

Purpose:
- Describe optional mesh evidence without forcing downstream consumers to parse OBJ first.

Example:

```json
{
  "schema_version": "v1",
  "coordinate_frame_session_id": "cfs_8ec7d26d-1f0e-4ed0-86de-5b3c6d4c7d91",
  "mesh_files": [
    {
      "mesh_id": "mesh_0001",
      "mesh_path": "arkit/meshes/mesh_0001.obj",
      "triangle_count": 18234,
      "vertex_count": 9451,
      "bounds_m": {
        "min": [-1.2, -0.1, -3.4],
        "max": [4.8, 2.9, 1.7]
      }
    }
  ]
}
```

## Contract Invariants

The following must be true for a canonical V3 raw bundle:

1. `walkthrough.mov` exists, is non-empty, and is decodable.
2. Every required JSON file exists, parses, and matches its required schema.
3. Every required JSONL file exists and contains only valid objects.
4. `scene_id` and `capture_id` are identical across `manifest.json`, `capture_context.json`, `provenance.json`, and `capture_upload_complete.json`.
5. `coordinate_frame_session_id` is identical across all ARKit and route/relocalization sidecars.
6. `frame_id` is unique and monotonic across `arkit/poses.jsonl`, `arkit/frames.jsonl`, `arkit/frame_quality.jsonl`, and `sync_map.jsonl`.
7. `t_capture_sec` is monotonic within each stream.
8. `sync_map.jsonl` is the canonical timing join for downstream bridge and pipeline work.
9. Any file path referenced by a manifest or JSONL row must exist in the bundle.
10. Rights remain conservative. Unknown rights must not authorize derived generation.

## Validator Checklist

### Upload Validator

Hard fail:
- Missing `walkthrough.mov`.
- Missing any required JSON or JSONL sidecar.
- Invalid JSON parse or JSONL parse.
- Missing `scene_id`, `capture_id`, or `coordinate_frame_session_id`.
- `hardware_model_identifier` missing or generic-only device metadata.
- `sync_map.jsonl` missing.
- `arkit/poses.jsonl`, `arkit/frames.jsonl`, `arkit/frame_quality.jsonl`, or `arkit/session_intrinsics.json` missing for iPhone capture.
- Depth supported but `depth_manifest.json` or `confidence_manifest.json` missing.
- Referenced depth/confidence files missing.
- Any file listed in `hashes.json` has a mismatched hash.
- `frame_id` duplicates.
- Non-monotonic `t_capture_sec` within a stream.
- `T_world_camera` missing, malformed, non-4x4, or non-finite.

Warn and retain:
- `mesh_manifest.json` missing.
- Zero semantic anchors observed.
- Low depth valid fraction.
- Relocalization windows present but recovered.

Metrics to compute at upload:
- `pose_row_count`
- `frame_row_count`
- `motion_sample_count`
- `depth_frame_count`
- `confidence_frame_count`
- `relocalization_event_count`
- `median_depth_valid_fraction`
- `max_tracking_loss_window_sec`

### Bridge Validator

Hard fail:
- Canonical V3 bundle uses legacy or mixed pose schema.
- `sync_map.jsonl` cannot align extracted frames to canonical capture time.
- `capture_upload_complete.json` identity does not match path identity.
- `scene_id` or `capture_id` mismatch between path and sidecars.
- `coordinate_frame_session_id` mismatch between ARKit sidecars.
- `rights_consent.json` missing when `requested_outputs` includes `scene_memory` or `preview_simulation`.

Downgrade from `pose_assisted` to `video_only`:
- Pose match coverage below threshold.
- `p95` sync delta above threshold.
- Excessive relocalization frames.
- Invalid intrinsics.

Recommended bridge thresholds:
- `pose_match_rate >= 0.90`
- `p95_pose_delta_sec <= 0.10`
- `max_pose_delta_sec <= 0.25`
- `relocalization_frame_fraction < 0.20`

Bridge outputs should preserve:
- original `coordinate_frame_session_id`
- sync quality metrics
- rights gates
- relocalization summary
- semantic anchor instance ids

### Pipeline Validator

Hard fail for any derived-world lane:
- `derived_scene_generation_allowed != true`
- `consent_status == "unknown"`
- `capture_rights.redaction_required == true` but required privacy preprocessing missing
- `processing_profile != "pose_assisted"` for tier1 iPhone world-model conditioning
- invalid or missing depth semantics
- unresolved coordinate-frame discontinuity

Qualification lane may continue with warnings:
- No meshes
- Low semantic anchor density
- Limited depth coverage
- Short relocalization windows

Recommended pipeline gates for `world_model_candidate=true`:
- iPhone capture source
- valid intrinsics
- valid poses
- valid depth
- acceptable sync quality
- acceptable relocalization fraction
- rights allow derived generation

## Common Failure Codes

- `missing_required_file`
- `invalid_json`
- `invalid_jsonl`
- `identity_mismatch`
- `coordinate_frame_session_mismatch`
- `frame_id_duplicate`
- `timestamp_non_monotonic`
- `invalid_transform_matrix`
- `missing_depth_sidecar`
- `missing_confidence_sidecar`
- `referenced_artifact_missing`
- `hash_mismatch`
- `rights_not_sufficient_for_derived_generation`
- `sync_alignment_failed`
- `pose_quality_below_threshold`
- `relocalization_fraction_too_high`

## Migration Rule

V3 is the canonical raw bundle contract for new iPhone capture output.

The bridge may continue to accept older layouts or mixed pose rows during migration, but those compatibility paths must be normalized before descriptor generation. No new raw writer should emit a legacy-only or mixed schema bundle once V3 is adopted.
