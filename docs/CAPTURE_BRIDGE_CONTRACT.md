# Capture Bridge Contract

This document defines the bridge contract emitted by `cloud/extract-frames/src/index.ts` for each uploaded capture.

## Scope

- Inbound capture path (primary):
  - `scenes/{scene_id}/{source}/{capture_id}/raw/walkthrough.mov`
- Compatibility path:
  - `targets/{scene_id}/raw/walkthrough.mov`

The bridge extracts frames, aligns ARKit pose data, emits QA artifacts, and writes a trigger request for downstream orchestration when quality gates pass.

## Upload Layout

Input capture layout:

```text
scenes/{scene_id}/{source}/{capture_id}/raw/
  manifest.json
  walkthrough.mov
  motion.jsonl
  arkit/...
```

Bridge outputs:

```text
scenes/{scene_id}/{source}/{capture_id}/frames/
  000001.jpg
  ...
  index.jsonl

scenes/{scene_id}/images/
  {capture_id}_keyframe.jpg

scenes/{scene_id}/captures/{capture_id}/
  capture_descriptor.json
  qa_report.json

scenes/{scene_id}/prompts/
  scene_request.json   (written only on QA pass)
```

## `manifest.json` additions

The iOS/glasses capture manifests must include:

```json
{
  "capture_schema_version": "2.0.0",
  "capture_source": "iphone|glasses",
  "capture_tier_hint": "tier1_iphone|tier2_glasses"
}
```

Scene-memory readiness metadata should also be attached when available:

```json
{
  "scene_memory_capture": {
    "continuity_score": 0.0,
    "lighting_consistency": "stable|variable|unknown",
    "dynamic_object_density": "low|medium|high|unknown",
    "sensor_availability": {
      "arkit_poses": true,
      "arkit_intrinsics": true,
      "arkit_depth": true,
      "arkit_confidence": false
    },
    "operator_notes": [],
    "inaccessible_areas": [],
    "world_model_candidate": true
  },
  "capture_rights": {
    "derived_scene_generation_allowed": true,
    "data_licensing_allowed": false,
    "capture_contributor_payout_eligible": false,
    "consent_notes": []
  }
}
```

## `arkit/poses.jsonl` v2 row (backward compatible)

Each row includes both legacy and bridge fields:

```json
{
  "pose_schema_version": "2.0",
  "frameIndex": 0,
  "timestamp": 12345.6789,
  "transform": [[...],[...],[...],[...]],
  "frame_id": "000001",
  "t_device_sec": 0.0,
  "T_world_camera": [[...],[...],[...],[...]]
}
```

## `frames/index.jsonl` row

Each extracted frame includes canonical frame timing plus optional aligned ARKit pose:

```json
{
  "frame_id": "000001",
  "t_video_sec": 0.0,
  "arkit_pose": {
    "pose_frame_id": "000001",
    "pose_schema_version": "2.0",
    "source_schema": "v2|legacy|mixed",
    "T_world_camera": [[...],[...],[...],[...]],
    "t_device_sec": 0.0,
    "delta_sec": 0.0,
    "match_type": "frame_id|time"
  }
}
```

## `capture_descriptor.json` schema

```json
{
  "schema_version": "v1",
  "scene_id": "string",
  "capture_id": "string",
  "capture_source": "iphone|glasses|unknown",
  "capture_tier": "tier1_iphone|tier2_glasses",
  "raw_prefix_uri": "gs://...",
  "frames_index_uri": "gs://...",
  "keyframe_uri": "gs://.../images/{capture_id}_keyframe.jpg",
  "nurec_mode": "mono_pose_assisted|mono_slam",
  "swap_focus": ["kitchen", "warehouse"],
  "intended_space_type": "string",
  "quality": {
    "pose_match_rate": 0.0,
    "p95_pose_delta_sec": 0.0,
    "frame_count": 0
  },
  "capture_bundle": {
    "arkit_poses_uri": "gs://...",
    "arkit_intrinsics_uri": "gs://...",
    "arkit_depth_prefix_uri": "gs://...",
    "arkit_confidence_prefix_uri": "gs://..."
  },
  "qa_status": "passed|blocked",
  "qa_report_uri": "gs://...",
  "requested_lanes": ["qualification", "scene_memory", "advanced_geometry"],
  "auto_triggered": true,
  "generated_at": "ISO-8601"
}
```

## `qa_report.json` schema

```json
{
  "schema_version": "v1",
  "scene_id": "string",
  "capture_id": "string",
  "capture_source": "iphone|glasses|unknown",
  "capture_tier_initial": "tier1_iphone|tier2_glasses",
  "capture_tier_final": "tier1_iphone|tier2_glasses",
  "nurec_mode": "mono_pose_assisted|mono_slam",
  "status": "passed|blocked",
  "required_files": {
    "walkthrough": true,
    "manifest": true
  },
  "manifest_validation": {
    "valid": true,
    "missing_required": [],
    "warnings": []
  },
  "quality": {
    "frame_count": 0,
    "pose_matches": 0,
    "pose_match_rate": 0.0,
    "p95_pose_delta_sec": 0.0
  },
  "scene_memory_readiness": {
    "world_model_candidate": true,
    "recommended_lane": "scene_memory",
    "derived_only": true
  },
  "reasons": [],
  "warnings": [],
  "auto_triggered": true,
  "trigger_error": null,
  "generated_at": "ISO-8601"
}
```

## Auto trigger payload (`scene_request.json`)

Written to `scenes/{scene_id}/prompts/scene_request.json` on QA pass:

```json
{
  "schema_version": "v1",
  "scene_id": "string",
  "source_mode": "image",
  "quality_tier": "standard",
  "image": {
    "gcs_uri": "gs://.../images/{capture_id}_keyframe.jpg",
    "generation": "string"
  },
  "constraints": {
    "capture_bundle": {
      "scene_id": "string",
      "capture_id": "string",
      "capture_source": "string",
      "capture_tier": "string",
      "nurec_mode": "string",
      "raw_prefix_uri": "gs://...",
      "frames_index_uri": "gs://...",
      "keyframe_uri": "gs://...",
      "descriptor_uri": "gs://...",
      "qa_report_uri": "gs://...",
      "swap_focus": ["kitchen", "warehouse"]
    }
  },
  "provider_policy": "openai_primary",
  "fallback": {
    "allow_image_fallback": false
  }
}
```

## Quality gate defaults

- Tier-1 iPhone (`mono_pose_assisted`): requires strong ARKit alignment.
- Tier-2 (`mono_slam`): glasses captures and degraded iPhone captures.
- Block conditions:
  - missing/invalid required files
  - invalid manifest required fields
  - insufficient extracted frame count
