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
  task_hypothesis.json
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

The manifest also includes a validated `capture_evidence` block:

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

Supplemental files use stable snake_case keys:

```text
intake_packet.json
capture_context.json
task_hypothesis.json
```

`task_hypothesis.json` is always materialized for finalized bundles. If intake was authoritative or manually entered, the file is synthesized from the resolved intake packet.

## Output Files

```text
scenes/{scene_id}/captures/{capture_id}/frames/index.jsonl
scenes/{scene_id}/captures/{capture_id}/capture_descriptor.json
scenes/{scene_id}/captures/{capture_id}/qa_report.json
scenes/{scene_id}/captures/{capture_id}/pipeline_handoff.json
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
    "arkit_confidence_prefix_uri": "gs://...",
    "arkit_meshes_prefix_uri": "gs://...",
    "motion_uri": "gs://...",
    "artifact_validity": {
      "arkit_poses": true,
      "arkit_intrinsics": true,
      "arkit_depth": true,
      "arkit_confidence": true,
      "arkit_meshes": false,
      "motion": true
    }
  },
  "site_submission_id": "string|null",
  "buyer_request_id": "string|null",
  "capture_job_id": "string|null",
  "region_id": "string|null",
  "rights_profile": "string|null",
  "requested_outputs": ["qualification", "preview_simulation"],
  "scene_memory_capture": {},
  "capture_rights": {},
  "task_site_context": {},
  "identity": {},
  "requested_lanes": ["qualification", "scene_memory", "preview_simulation"],
  "preview_simulation_requested": true,
  "worldlabs_request_manifest_uri": "gs://...",
  "worldlabs_input_manifest_uri": "gs://...",
  "worldlabs_input_video_uri": "gs://...",
  "qa_status": "passed|blocked",
  "qa_report_uri": "gs://...",
  "pipeline_handoff_uri": "gs://...",
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
  "identity": {},
  "reasons": [],
  "warnings": [],
  "generated_at": "ISO-8601"
}
```

## pipeline_handoff.json

This payload is written to shared storage and published to Pub/Sub topic
`blueprint-capture-pipeline-handoff` (or `BLUEPRINT_CAPTURE_PIPELINE_TOPIC` when overridden).

It includes:

- raw, descriptor, and QA URIs
- `requested_outputs` and normalized `requested_lanes`
- business identifiers such as `site_submission_id`, `buyer_request_id`, and `capture_job_id`
- task/site context lifted from capture intake
- rights and scene-memory blocks
- World Labs preview intent and reserved URIs when `preview_simulation` is requested

## Notes

- The bridge now triggers downstream pipeline orchestration by publishing `pipeline_handoff.json`
  to Pub/Sub after upload completion and QA materialization.
- Generated scenes, if any, belong to downstream systems.
