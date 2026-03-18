# Capture Bundle Compatibility

This guide describes the raw capture bundle that BlueprintCapture uploads for downstream processing.

The app preserves evidence. It does not perform reconstruction or scene generation.

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

## Required Files

| File | Purpose |
|------|---------|
| `manifest.json` | Raw capture metadata |
| `walkthrough.mov` | Source video |

## Optional Raw Evidence

| File or Folder | Purpose |
|------|---------|
| `motion.jsonl` | Device motion samples |
| `arkit/poses.jsonl` | Camera pose timeline |
| `arkit/intrinsics.json` | Camera calibration |
| `arkit/frames.jsonl` | ARKit frame timing |
| `arkit/depth/*.png` | Depth evidence |
| `arkit/confidence/*.png` | Depth confidence evidence |
| `arkit/meshes/*.obj` | ARKit mesh evidence |

## Manifest Shape

Required root fields:

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
  "capture_schema_version": "2.0.0",
  "capture_source": "iphone|android|glasses",
  "capture_tier_hint": "tier1_iphone|tier2_android|tier2_glasses"
}
```

Required normalized metadata blocks:

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
    "motion_timestamps_capture_relative": false
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
    "motion_samples": 0,
    "motion_provenance": null,
    "motion_timestamps_capture_relative": false
  }
}
```

Finalized bundles always include `task_hypothesis.json`, even when the task hypothesis is synthesized from authoritative or manual intake.

## Why The ARKit Data Matters

- `poses.jsonl` preserves camera motion aligned to the capture
- `intrinsics.json` preserves camera calibration
- `frames.jsonl` preserves timing
- `depth` and `confidence` preserve geometric evidence
- `meshes` preserve ARKit surface evidence

These files help downstream scene-memory derivation stay capture-backed.

## Bridge Outputs

The bridge writes:

```text
scenes/{scene_id}/captures/{capture_id}/frames/index.jsonl
scenes/{scene_id}/captures/{capture_id}/capture_descriptor.json
scenes/{scene_id}/captures/{capture_id}/qa_report.json
```

There is no generation request payload in this repo’s contract.
