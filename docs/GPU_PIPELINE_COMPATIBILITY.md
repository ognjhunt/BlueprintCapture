# Capture Bundle Compatibility

This guide describes the raw capture bundle that `BlueprintCapture` uploads for downstream bridge and GPU-side processing.

The app preserves evidence. It does not perform reconstruction or scene generation locally.

For the canonical raw capture contract, see [/Users/nijelhunt_1/workspace/BlueprintCapture/docs/CAPTURE_RAW_CONTRACT_V3.md](/Users/nijelhunt_1/workspace/BlueprintCapture/docs/CAPTURE_RAW_CONTRACT_V3.md).
For the bridge materialization contract, see [/Users/nijelhunt_1/workspace/BlueprintCapture/docs/CAPTURE_BRIDGE_CONTRACT.md](/Users/nijelhunt_1/workspace/BlueprintCapture/docs/CAPTURE_BRIDGE_CONTRACT.md).

For the canonical upstream raw capture contract, see [CAPTURE_RAW_CONTRACT_V3.md](CAPTURE_RAW_CONTRACT_V3.md).
For the bridge materialization contract, see [CAPTURE_BRIDGE_CONTRACT.md](CAPTURE_BRIDGE_CONTRACT.md).
This document describes GPU pipeline compatibility requirements.

## Upload Layout

Canonical path:

```text
gs://blueprint-8c1ca.appspot.com/scenes/{scene_id}/captures/{capture_id}/raw/
```

Compatibility paths still accepted by the bridge:

```text
gs://blueprint-8c1ca.appspot.com/scenes/{scene_id}/{source}/{capture_id}/raw/
gs://blueprint-8c1ca.appspot.com/targets/{scene_id}/raw/
```

## Required Raw Files

Core bundle files:

- `manifest.json`
- `provenance.json`
- `rights_consent.json`
- `capture_context.json`
- `intake_packet.json`
- `task_hypothesis.json`
- `recording_session.json`
- `capture_topology.json`
- `route_anchors.json`
- `checkpoint_events.json`
- `relocalization_events.json`
- `overlap_graph.json`
- `video_track.json`
- `hashes.json`
- `capture_upload_complete.json`
- `walkthrough.mov`
- `sync_map.jsonl`
- `motion.jsonl`
- `semantic_anchor_observations.jsonl`

<<<<<<< HEAD
Modality-specific files:

- iPhone: `arkit/poses.jsonl`, `arkit/frames.jsonl`, `arkit/frame_quality.jsonl`, `arkit/session_intrinsics.json`
- iPhone depth: `arkit/depth_manifest.json`, `arkit/confidence_manifest.json`, `arkit/depth/*.png`, `arkit/confidence/*.png`
- Android ARCore: `arcore/poses.jsonl`, `arcore/frames.jsonl`, `arcore/session_intrinsics.json`, `arcore/tracking_state.jsonl`, `arcore/point_cloud.jsonl`, `arcore/planes.jsonl`, `arcore/light_estimates.jsonl`, `arcore/depth_manifest.json`, `arcore/confidence_manifest.json`
- Glasses: `glasses/stream_metadata.json`, `glasses/frame_timestamps.jsonl`, `glasses/device_state.jsonl`, `glasses/health_events.jsonl`
- Companion phone: `companion_phone/poses.jsonl`, `companion_phone/session_intrinsics.json`, `companion_phone/calibration.json`

Optional high-value evidence:

- `arkit/meshes/*.obj`
=======
### iPhone / ARKit

| File or Folder | Purpose |
|------|---------|
| `motion.jsonl` | Device motion samples |
| `arkit/poses.jsonl` | Camera pose timeline |
| `arkit/intrinsics.json` | Camera calibration |
| `arkit/frames.jsonl` | ARKit frame timing |
| `arkit/depth/*.png` | Depth evidence |
| `arkit/confidence/*.png` | Depth confidence evidence |
| `arkit/meshes/*.obj` | ARKit mesh evidence |
>>>>>>> c5e8ed3 (Sync platform context with bridge and GPU contracts)

### Android / ARCore

| File or Folder | Purpose |
|------|---------|
| `arcore/poses.jsonl` | Camera pose timeline (when camera_pose=true and geometry_source=arcore) |
| `arcore/frames.jsonl` | ARCore frame timing (when camera_pose=true and geometry_source=arcore) |
| `arcore/session_intrinsics.json` | Camera calibration (when camera_intrinsics=true and geometry_source=arcore) |
| `arcore/tracking_state.jsonl` | Tracking state (when tracking_state=true and geometry_source=arcore) |
| `arcore/point_cloud.jsonl` | Point cloud samples (when point_cloud=true) |
| `arcore/planes.jsonl` | Plane observations (when planes=true and geometry_source=arcore) |
| `arcore/light_estimates.jsonl` | Light estimates (when light_estimate=true and geometry_source=arcore) |
| `arcore/depth_manifest.json` | Depth manifest (when depth=true and geometry_source=arcore) |
| `arcore/confidence_manifest.json` | Depth confidence manifest (when depth_confidence=true and geometry_source=arcore) |

### Glasses / Companion Phone

| File or Folder | Purpose |
|------|---------|
| `glasses/stream_metadata.json` | Stream metadata (required for glasses captures) |
| `glasses/frame_timestamps.jsonl` | Frame timestamps (required for glasses captures) |
| `glasses/device_state.jsonl` | Device state (required for glasses captures) |
| `glasses/health_events.jsonl` | Health events (required for glasses captures) |
| `companion_phone/poses.jsonl` | Companion phone poses (when companion_phone_pose=true) |
| `companion_phone/session_intrinsics.json` | Companion phone intrinsics (when companion_phone_intrinsics=true) |
| `companion_phone/calibration.json` | Calibration data (when companion_phone_calibration=true) |

## Manifest Shape

Current raw bundles write `schema_version = "v3"` and `capture_schema_version = "3.1.0"`.

<<<<<<< HEAD
Required manifest fields include:
=======
```json
{
  "scene_id": "string",
  "video_uri": "string",
  "device_model": "string",
  "os_version": "string",
  "fps_source": 30.0,
  "width": 1920,
  "height": 1440,
  "capture_start_epoch_ms": 1702137045123,
  "has_lidar": true,
  "depth_supported": true,
  "capture_schema_version": "3.1.0",
  "capture_source": "iphone|android|glasses",
  "capture_tier_hint": "tier1_iphone|tier2_android|tier2_glasses",
  "capture_profile_id": "iphone_arkit_lidar|iphone_arkit_non_lidar|android_arcore_depth|android_arcore_pose_only|android_camera_only|glasses_pov|glasses_pov_companion_phone",
  "capture_capabilities": {}
}
```
>>>>>>> c5e8ed3 (Sync platform context with bridge and GPU contracts)

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

<<<<<<< HEAD
`capture_capabilities` must truthfully describe what was captured. It is not a downstream inference summary.
=======
```json
{
  "scene_memory_capture": {
    "continuity_score": null,
    "lighting_consistency": "unknown",
    "dynamic_object_density": "unknown",
    "sensor_availability": {
      "arkit_poses": false,
      "arkit_intrinsics": false,
      "arkit_depth": false,
      "arkit_confidence": false,
      "arkit_meshes": false,
      "motion": false
    },
    "operator_notes": [],
    "inaccessible_areas": [],
    "world_model_candidate": false,
    "motion_provenance": null,
    "motion_timestamps_capture_relative": false,
    "geometry_source": null,
    "geometry_expected_downstream": true
  },
  "capture_rights": {
    "derived_scene_generation_allowed": false,
    "data_licensing_allowed": false,
    "capture_contributor_payout_eligible": false,
    "consent_status": "documented|policy_only|unknown",
    "permission_document_uri": null,
    "consent_scope": [],
    "consent_notes": []
  }
}
```

Validated evidence is reported separately:

```json
{
  "capture_evidence": {
    "arkit_frame_rows": 0,
    "arkit_pose_rows": 0,
    "arkit_intrinsics_valid": false,
    "arkit_depth_frames": 0,
    "arkit_confidence_frames": 0,
    "arkit_mesh_files": 0,
    "pose_rows": 0,
    "intrinsics_valid": false,
    "depth_frames": 0,
    "confidence_frames": 0,
    "point_cloud_samples": 0,
    "plane_rows": 0,
    "feature_point_rows": 0,
    "tracking_state_rows": 0,
    "relocalization_event_rows": 0,
    "light_estimate_rows": 0,
    "motion_samples": 0,
    "pose_authority": "not_available",
    "intrinsics_authority": "not_available",
    "depth_authority": "not_available",
    "motion_authority": "diagnostic_only",
    "motion_provenance": null,
    "motion_timestamps_capture_relative": false,
    "geometry_source": null,
    "geometry_expected_downstream": true
  }
}
```

Finalized bundles always include `task_hypothesis.json`, even when the task hypothesis is synthesized from authoritative or manual intake.

## Why The Raw Evidence Matters

### ARKit Data (iPhone)

- `poses.jsonl` preserves camera motion aligned to the capture
- `intrinsics.json` preserves camera calibration
- `frames.jsonl` preserves timing
- `depth` and `confidence` preserve geometric evidence
- `meshes` preserve ARKit surface evidence

### ARCore Data (Android)

- `poses.jsonl` preserves camera motion for ARCore-aligned captures
- `session_intrinsics.json` preserves camera calibration
- `tracking_state.jsonl` preserves tracking quality
- `point_cloud.jsonl` preserves sparse 3D observations
- `planes.jsonl` preserves surface plane observations

### Glasses Data

- `stream_metadata.json` preserves capture stream configuration
- `frame_timestamps.jsonl` preserves frame timing
- `device_state.jsonl` preserves device telemetry
- `health_events.jsonl` preserves device health markers

These files help downstream scene-memory derivation stay capture-backed.
>>>>>>> c5e8ed3 (Sync platform context with bridge and GPU contracts)

The bridge must preserve the raw-vs-derived distinction:

- raw first-party evidence stays authoritative
- `capture_capabilities` declares what the device truthfully captured
- downstream geometry remains derived and must not be mislabeled as raw evidence

## Bridge Outputs

The bridge writes:

<<<<<<< HEAD
- `scenes/{scene_id}/captures/{capture_id}/frames/index.jsonl`
- `scenes/{scene_id}/captures/{capture_id}/capture_descriptor.json`
- `scenes/{scene_id}/captures/{capture_id}/qa_report.json`
- `scenes/{scene_id}/captures/{capture_id}/pipeline_handoff.json`

The bridge then publishes the finalized handoff payload to Pub/Sub topic `blueprint-capture-pipeline-handoff`.

## Compatibility Notes

- Legacy `android_phone` bundles may still be accepted during migration, but the canonical downstream contract is now `android`.
- Generated scenes are downstream derived products, not raw truth.
- There is no generation request payload in this repo’s contract.
=======
```text
scenes/{scene_id}/captures/{capture_id}/frames/index.jsonl
scenes/{scene_id}/captures/{capture_id}/capture_descriptor.json
scenes/{scene_id}/captures/{capture_id}/qa_report.json
scenes/{scene_id}/captures/{capture_id}/pipeline_handoff.json
```

The bridge now triggers downstream pipeline orchestration by publishing `pipeline_handoff.json` to Pub/Sub after upload completion and QA materialization. See [CAPTURE_BRIDGE_CONTRACT.md](CAPTURE_BRIDGE_CONTRACT.md) for the full handoff contract.

Legacy `android_phone` bundles may still be accepted during migration, but the canonical contract emitted downstream is now `android`.
>>>>>>> c5e8ed3 (Sync platform context with bridge and GPU contracts)
