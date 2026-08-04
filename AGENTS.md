# BlueprintCapture Agent Guide

## Mission

`BlueprintCapture` is the evidence-capture client for Blueprint's sole active
program, Arm Decision Proof v1. It must record the truthful structured capture
for one previously unseen fixed-arm workcell without inventing downstream
qualification.

This repo must stay aligned with:

- `/Users/nijelhunt_1/workspace/BlueprintCapture/PLATFORM_CONTEXT.md`
- `/Users/nijelhunt_1/workspace/BlueprintCapture/WORLD_MODEL_STRATEGY_CONTEXT.md`

## Read First

1. `/Users/nijelhunt_1/workspace/BlueprintCapture/PLATFORM_CONTEXT.md`
2. `/Users/nijelhunt_1/workspace/BlueprintCapture/WORLD_MODEL_STRATEGY_CONTEXT.md`
3. `/Users/nijelhunt_1/workspace/BlueprintCapture/README.md`
4. `/Users/nijelhunt_1/workspace/BlueprintCapture/docs/CAPTURE_RAW_CONTRACT_V3.md`

## Product Rules

- Arm Decision Proof v1 is the sole active program. Capture work must unblock its
  day-14 immutable-capture or registration evidence, or preserve required
  compatibility. Humanoid, broad marketplace, unrelated capture-mode, and growth
  work is frozen.
- The immediate program is public-reference harness first. Do not build new
  capture/reconstruction features until ADP-008 passes and a measured harness or
  partner blocker identifies a missing measurement existing inputs cannot supply.
- Existing captures may exercise downstream Pipeline seams but remain
  `development_only`; they cannot prove the new partner capture, task truth,
  robot registration, task physics, sim-to-real fidelity, or partner value.
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

## Shared Doctrine Blocks

The regions between `<!-- SHARED_*_START -->` and `<!-- SHARED_*_END -->` in
`PLATFORM_CONTEXT.md`, `VISION.md`, and `WORLD_MODEL_STRATEGY_CONTEXT.md` are
**generated**. They must stay byte-identical across `BlueprintCapture`,
`BlueprintCapturePipeline`, and `Blueprint-WebApp`.

- Never hand-edit inside those markers. `python3 scripts/verify_shared_doctrine.py`
  runs in CI and rejects it.
- To change shared doctrine, edit the single canonical fragment in
  `BlueprintCapturePipeline doctrine/`, then run
  `python3 scripts/sync_shared_doctrine.py --write` from that repo with this one
  checked out as a sibling. That splices every repo and updates
  `contracts/shared-doctrine.lock.json`.
- Everything outside the markers is this repo's own header and footer. Edit it
  freely; the sync never touches it.

Enforcement compares committed content against the lock, so it needs no sibling
checkout. The previous mechanism was a sibling comparison that passed trivially
in CI whenever the sibling was absent — which is always true in CI — and that is
how all three blocks diverged on 2026-07-29 without any gate firing.

## Working Rules

- Favor the smallest truthful one-walk fixed-arm workcell capture, bundle
  integrity, decoded-time alignment, upload reliability, and explicit user state.
- Require every task to name the Arm Decision Proof backlog item, gate, observed
  blocker, and completion artifact it serves.
- Keep contracts compatible with `BlueprintCapturePipeline`.
- Avoid UI or backend behavior that implies unsupported provider or payout readiness.
- Treat capture bundle correctness as a first-order requirement.
- For Paperclip/autonomous-loop closeouts, use `/Users/nijelhunt_1/workspace/Blueprint-WebApp/docs/autonomous-loop-evidence-checklist-2026-05-03.md` before claiming `done`, `blocked`, or `awaiting_human_decision`.

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
