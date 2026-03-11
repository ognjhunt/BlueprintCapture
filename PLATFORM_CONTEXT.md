# Platform Context

This repo is the Blueprint evidence-capture layer.

## Doctrine

- Blueprint is qualification-first.
- This repo captures evidence. It does not make readiness decisions.
- Capture-backed scene memory is downstream of the raw bundle.
- The app should produce world-model-ready evidence when possible.
- Capture quality is the moat.
- Generated scenes are downstream derived products, not truth.

## What This Repo Owns

- guided capture on iPhone and Meta glasses
- raw bundle packaging
- ARKit, intrinsics, depth, timing, meshes, and motion preservation when available
- scene-memory-readiness metadata
- rights, consent, and payout-eligibility metadata
- upload into the canonical raw layout

## Canonical Layout

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

Bridge outputs:

```text
scenes/{scene_id}/captures/{capture_id}/capture_descriptor.json
scenes/{scene_id}/captures/{capture_id}/qa_report.json
```

## Boundaries

This repo should not:

- run reconstruction in-app
- run world models
- run downstream simulation
- turn generated scenes into source truth

The handoff out of this repo is the raw evidence bundle plus bridge descriptor and QA outputs.
