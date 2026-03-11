# Capture Bridge Contract

This document defines the bridge contract emitted by [/Users/nijelhunt_1/workspace/BlueprintCapture/cloud/extract-frames/src/index.ts](/Users/nijelhunt_1/workspace/BlueprintCapture/cloud/extract-frames/src/index.ts).

## Input Paths

Canonical:

```text
scenes/{scene_id}/captures/{capture_id}/raw/walkthrough.mov
```

Accepted for compatibility:

```text
scenes/{scene_id}/{source}/{capture_id}/raw/walkthrough.mov
targets/{scene_id}/raw/walkthrough.mov
```

## Raw Bundle

```text
scenes/{scene_id}/captures/{capture_id}/raw/
  manifest.json
  intake_packet.json
  capture_context.json
  capture_upload_complete.json
  walkthrough.mov
  motion.jsonl
  arkit/...
```

## Required Manifest Fields

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
  "capture_source": "iphone|glasses",
  "capture_tier_hint": "tier1_iphone|tier2_glasses"
}
```

## Scene Memory And Rights Blocks

The manifest must also carry normalized scene-memory and rights metadata:

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
    "world_model_candidate": false
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

## Output Files

```text
scenes/{scene_id}/captures/{capture_id}/frames/index.jsonl
scenes/{scene_id}/captures/{capture_id}/capture_descriptor.json
scenes/{scene_id}/captures/{capture_id}/qa_report.json
scenes/{scene_id}/images/{capture_id}_keyframe.jpg
```

## capture_descriptor.json

```json
{
  "schema_version": "v1",
  "scene_id": "string",
  "capture_id": "string",
  "capture_source": "iphone|glasses|unknown",
  "capture_tier": "tier1_iphone|tier2_glasses",
  "processing_profile": "pose_assisted|video_only",
  "raw_prefix_uri": "gs://...",
  "frames_index_uri": "gs://...",
  "keyframe_uri": "gs://.../images/{capture_id}_keyframe.jpg",
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
  "scene_memory_capture": {},
  "capture_rights": {},
  "requested_lanes": ["qualification", "scene_memory"],
  "qa_status": "passed|blocked",
  "qa_report_uri": "gs://...",
  "generated_at": "ISO-8601"
}
```

## qa_report.json

```json
{
  "schema_version": "v1",
  "scene_id": "string",
  "capture_id": "string",
  "capture_source": "iphone|glasses|unknown",
  "capture_tier_initial": "tier1_iphone|tier2_glasses",
  "capture_tier_final": "tier1_iphone|tier2_glasses",
  "processing_profile": "pose_assisted|video_only",
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
    "world_model_candidate": false,
    "recommended_lane": "qualification|scene_memory",
    "derived_only": true
  },
  "reasons": [],
  "warnings": [],
  "generated_at": "ISO-8601"
}
```

## Notes

- The bridge writes descriptor and QA outputs only.
- It does not write a downstream generation request payload.
- Generated scenes, if any, belong to downstream systems.
