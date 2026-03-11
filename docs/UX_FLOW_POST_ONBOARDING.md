# Post-Onboarding Capture Flow

This document summarizes the main user flow after onboarding.

## App Sections

- Nearby Targets
- Glasses Capture
- Settings

## Main Flow

1. The user opens the app after onboarding.
2. The app shows nearby targets or the glasses capture entry point.
3. The user reserves a target or enters a direct glasses capture flow.
4. The app records walkthrough evidence.
5. The app finalizes a raw capture bundle.
6. The app uploads the bundle under `scenes/{scene_id}/captures/{capture_id}/raw/`.
7. The cloud bridge extracts frames and writes `capture_descriptor.json` and `qa_report.json`.

## Raw Bundle Contents

```text
raw/
  manifest.json
  intake_packet.json
  capture_context.json
  capture_upload_complete.json
  walkthrough.mov
  motion.jsonl
  arkit/
    poses.jsonl
    frames.jsonl
    intrinsics.json
    depth/
    confidence/
    meshes/
```

## Manifest Expectations

The manifest must include:

- raw capture identity fields
- ARKit and device metadata
- `scene_memory_capture`
- `capture_rights`

Unknown values should still be written as explicit defaults.

## Product Boundary

This app captures evidence.

It does not:

- make readiness decisions
- reconstruct scenes in-app
- generate world models
- generate downstream simulations
