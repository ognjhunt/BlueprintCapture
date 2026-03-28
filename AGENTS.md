# BlueprintCapture Agent Guide

## Mission

`BlueprintCapture` is the evidence-capture client. It records truthful site evidence and uploads canonical capture bundles for downstream processing.

This repo must stay aligned with:

- `/Users/nijelhunt_1/workspace/BlueprintCapture/PLATFORM_CONTEXT.md`
- `/Users/nijelhunt_1/workspace/BlueprintCapture/WORLD_MODEL_STRATEGY_CONTEXT.md`

## Read First

1. `/Users/nijelhunt_1/workspace/BlueprintCapture/PLATFORM_CONTEXT.md`
2. `/Users/nijelhunt_1/workspace/BlueprintCapture/WORLD_MODEL_STRATEGY_CONTEXT.md`
3. `/Users/nijelhunt_1/workspace/BlueprintCapture/README.md`
4. `/Users/nijelhunt_1/workspace/BlueprintCapture/docs/CAPTURE_RAW_CONTRACT_V3.md`

## Product Rules

- Qualification comes after truthful evidence capture.
- Preserve raw capture truth, timestamps, motion, poses, intrinsics, depth, and device metadata when available.
- Do not fabricate live supply, payout readiness, provider readiness, or rights states.
- In-app hints are advisory UX, not authoritative commercialization or qualification decisions.
- Generated or downstream artifacts are not the same thing as captured truth.

## Repo Map

- `BlueprintCapture/`: iOS app code, services, models, and views
- `BlueprintCaptureTests/`: contract and integration coverage
- `BlueprintCaptureUITests/`: UI flow coverage
- `android/`: Android capture client
- `cloud/`: bridge and backend helper functions
- `scripts/`: alpha-readiness and release validation
- `docs/`: rollout, alpha, bridge, and capture constraints

## Working Rules

- Favor truthful capture, bundle integrity, upload reliability, and explicit user state.
- Keep contracts compatible with `BlueprintCapturePipeline`.
- Avoid UI or backend behavior that implies unsupported provider or payout readiness.
- Treat capture bundle correctness as a first-order requirement.

## Commands

Open in Xcode:

```bash
open BlueprintCapture.xcodeproj
```

Build:

```bash
xcodebuild -project BlueprintCapture.xcodeproj -scheme BlueprintCapture -derivedDataPath build/DerivedData
```

Swift tests:

```bash
BLUEPRINT_IOS_SIMULATOR_NAME="iPhone 17 Pro" \
xcodebuild test -project BlueprintCapture.xcodeproj -scheme BlueprintCapture \
  -destination "platform=iOS Simulator,name=${BLUEPRINT_IOS_SIMULATOR_NAME}" \
  -derivedDataPath build/DerivedData
```

Bridge tests:

```bash
cd cloud/extract-frames && npm test
```

Alpha validation:

```bash
./scripts/archive_external_alpha.sh --validate-config-only
./scripts/android_alpha_readiness.sh --validate-config-only
```
