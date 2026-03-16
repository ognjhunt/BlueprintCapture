# BlueprintCapture

BlueprintCapture is the evidence-capture app for Blueprint.

It records walkthrough evidence, preserves raw sensor data, packages a capture bundle, and uploads that bundle for downstream qualification and scene-memory derivation.

This repo sits on the contributor side of Blueprint's three-sided marketplace:

- capturers gather evidence
- site operators control access and rights
- robot teams buy trusted downstream outcomes

The app owns real-time capture coaching only. It does not make final readiness, payout, rights, or buyer-trust decisions in-app, and it does not run reconstruction, world models, or scene generation locally.

## What This Repo Produces

Canonical raw upload layout:

```text
scenes/{scene_id}/captures/{capture_id}/raw/
  manifest.json
  intake_packet.json
  capture_context.json
  capture_upload_complete.json
  task_hypothesis.json
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

The bridge then emits:

```text
scenes/{scene_id}/captures/{capture_id}/capture_descriptor.json
scenes/{scene_id}/captures/{capture_id}/qa_report.json
scenes/{scene_id}/captures/{capture_id}/pipeline_handoff.json
```

After `capture_upload_complete.json` lands, the cloud bridge publishes the handoff payload to
Pub/Sub topic `blueprint-capture-pipeline-handoff` so `BlueprintCapturePipeline` can pick up the
capture automatically.

## Core Rules

- Qualification comes first.
- This repo is the evidence-capture layer, not the readiness-decision layer.
- In-app quality, coverage, and earnings cues are advisory and immediate UX only.
- Capture-backed scene memory is downstream of the raw bundle.
- Generated scenes are downstream derived products, not truth.
- ARKit poses, intrinsics, depth, timing, meshes, and motion are preserved when available.
- Raw bundle metadata reports only evidence that was actually captured and validated.

## Main Areas

- [/Users/nijelhunt_1/workspace/BlueprintCapture/BlueprintCapture/VideoCaptureManager.swift](/Users/nijelhunt_1/workspace/BlueprintCapture/BlueprintCapture/VideoCaptureManager.swift): iPhone capture and ARKit logging
- [/Users/nijelhunt_1/workspace/BlueprintCapture/BlueprintCapture/GlassesCaptureManager.swift](/Users/nijelhunt_1/workspace/BlueprintCapture/BlueprintCapture/GlassesCaptureManager.swift): Meta glasses capture
- [/Users/nijelhunt_1/workspace/BlueprintCapture/BlueprintCapture/Services/CaptureBundleSupport.swift](/Users/nijelhunt_1/workspace/BlueprintCapture/BlueprintCapture/Services/CaptureBundleSupport.swift): bundle finalization and export
- [/Users/nijelhunt_1/workspace/BlueprintCapture/BlueprintCapture/Services/CaptureUploadService.swift](/Users/nijelhunt_1/workspace/BlueprintCapture/BlueprintCapture/Services/CaptureUploadService.swift): upload pipeline
- [/Users/nijelhunt_1/workspace/BlueprintCapture/cloud/extract-frames/src/index.ts](/Users/nijelhunt_1/workspace/BlueprintCapture/cloud/extract-frames/src/index.ts): frame extraction bridge

## Build

```bash
open BlueprintCapture.xcodeproj
```

```bash
xcodebuild -project BlueprintCapture.xcodeproj -scheme BlueprintCapture
```

## Tests

Swift:

```bash
xcodebuild test -project BlueprintCapture.xcodeproj -scheme BlueprintCapture -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:BlueprintCaptureTests/CaptureBundleAndInferenceTests -only-testing:BlueprintCaptureTests/PipelineContractTests -only-testing:BlueprintCaptureTests/ScanHomeAndUploadTests
```

Cloud bridge:

```bash
cd cloud/extract-frames
npm test
```
