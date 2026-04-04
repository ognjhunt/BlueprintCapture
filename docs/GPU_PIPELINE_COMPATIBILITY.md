# Capture Bundle Compatibility

This guide describes the raw capture bundle that `BlueprintCapture` uploads for downstream bridge and GPU-side processing.

The app preserves evidence. It does not perform reconstruction or scene generation locally.

For the canonical raw capture contract, see [/Users/nijelhunt_1/workspace/BlueprintCapture/docs/CAPTURE_RAW_CONTRACT_V3.md](/Users/nijelhunt_1/workspace/BlueprintCapture/docs/CAPTURE_RAW_CONTRACT_V3.md).
For the bridge materialization contract, see [/Users/nijelhunt_1/workspace/BlueprintCapture/docs/CAPTURE_BRIDGE_CONTRACT.md](/Users/nijelhunt_1/workspace/BlueprintCapture/docs/CAPTURE_BRIDGE_CONTRACT.md).

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

Modality-specific files:

- iPhone: `arkit/poses.jsonl`, `arkit/frames.jsonl`, `arkit/frame_quality.jsonl`, `arkit/session_intrinsics.json`
- iPhone depth: `arkit/depth_manifest.json`, `arkit/confidence_manifest.json`, `arkit/depth/*.png`, `arkit/confidence/*.png`
- Android ARCore: `arcore/poses.jsonl`, `arcore/frames.jsonl`, `arcore/session_intrinsics.json`, `arcore/tracking_state.jsonl`, `arcore/point_cloud.jsonl`, `arcore/planes.jsonl`, `arcore/light_estimates.jsonl`, `arcore/depth_manifest.json`, `arcore/confidence_manifest.json`
- Glasses: `glasses/stream_metadata.json`, `glasses/frame_timestamps.jsonl`, `glasses/device_state.jsonl`, `glasses/health_events.jsonl`
- Companion phone: `companion_phone/poses.jsonl`, `companion_phone/session_intrinsics.json`, `companion_phone/calibration.json`

Optional high-value evidence:

- `arkit/meshes/*.obj`

## Manifest Shape

Current raw bundles write `schema_version = "v3"` and `capture_schema_version = "3.1.0"`.

Required manifest fields include:

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

`capture_capabilities` must truthfully describe what was captured. It is not a downstream inference summary.

## Bridge Outputs

The bridge writes:

- `scenes/{scene_id}/captures/{capture_id}/frames/index.jsonl`
- `scenes/{scene_id}/captures/{capture_id}/capture_descriptor.json`
- `scenes/{scene_id}/captures/{capture_id}/qa_report.json`
- `scenes/{scene_id}/captures/{capture_id}/pipeline_handoff.json`

The bridge then publishes the finalized handoff payload to Pub/Sub topic `blueprint-capture-pipeline-handoff`.

## Compatibility Notes

- Legacy `android_phone` bundles may still be accepted during migration, but the canonical downstream contract is now `android`.
- Generated scenes are downstream derived products, not raw truth.
- There is no generation request payload in this repo’s contract.
