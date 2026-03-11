# Platform Context

This repo is one part of a three-repo system.

## System Framing

- `BlueprintCapture` creates the evidence package.
- `BlueprintCapturePipeline` creates the qualification record and handoff.
- `Blueprint-WebApp` is the operating system around those records:
  - intake
  - routing
  - admin review
  - qualified opportunity exchange
  - later evaluation / tuning packaging
  - monetization

This platform is qualification-first.

Canonical scene doctrine:

- capture evidence serves qualification first
- the same capture should also be world-model-ready when possible
- derived scenes and datasets are downstream products, not default truth

The capture app should be treated as the evidence entry point for a scoped request, not as the product center of gravity by itself.

## What This Repo Owns

`BlueprintCapture` is the guided evidence-capture layer.

Its main jobs are:

- collect walkthrough evidence for a known site/task request
- package raw capture artifacts in the correct contract
- preserve device, timing, and optional ARKit data needed downstream
- upload the evidence bundle into the storage layout expected by the bridge and pipeline
- support recapture when evidence is incomplete or low quality
- attach scene-memory readiness metadata and rights metadata without doing reconstruction in-app

This repo should be treated as the system that turns field capture into a reusable evidence bundle, not as the place where readiness decisions are made.

## Relationship To The Other Repos

### Upstream

`Blueprint-WebApp` should create the request context:

- `requestId`
- `site_submission_id`
- buyer/task/workflow metadata
- requested lanes

### This repo

This repo should attach that context to the capture and emit the raw evidence package.

### Downstream

`BlueprintCapturePipeline` should consume the evidence package and turn it into:

- qualification artifacts
- readiness decisions
- blocker / evidence-gap outputs
- opportunity handoffs
- later advanced-geometry artifacts only when justified

## Raw Evidence Contract

The intended capture bundle is:

```text
raw/
  manifest.json
  intake_packet.json
  capture_context.json
  capture_upload_complete.json
  walkthrough.mov
  optional arkit/...
```

Bridge outputs should then populate:

```text
scenes/<scene_id>/captures/<capture_id>/
  capture_descriptor.json
  qa_report.json
```

Agents in this repo should preserve compatibility with:

- `docs/CAPTURE_BRIDGE_CONTRACT.md`
- `docs/GPU_PIPELINE_COMPATIBILITY.md`

## Product Context

The capture app supports the primary product, but it is not the product by itself.

The correct stack remains:

1. primary product: site qualification / readiness pack
2. secondary product: qualified opportunity exchange for robot teams
3. third product: scene memory / preview simulation / evaluation package
4. fourth product: training data / managed tuning / licensing

This repo exists to gather the evidence needed for step 1 and to make that evidence reusable for downstream scene-memory derivation.

It should not assume that every capture should become:

- a simulator artifact
- a marketplace scene
- a training-data engagement

Those are downstream lanes, not the default result of capture.

## Operational Model

The intended lifecycle is:

1. `Blueprint-WebApp` creates a scoped request and `site_submission_id`.
2. This repo captures the walkthrough evidence and packages it into the raw contract.
3. The capture bridge emits `capture_descriptor.json` and `qa_report.json`.
4. `BlueprintCapturePipeline` converts that package into qualification artifacts and a handoff.
5. `Blueprint-WebApp` ingests those outputs and updates operating state.

## Biggest Integration Concern

The most important boundary in this repo is preserving a clean handoff into the qualification pipeline.

That means agents should optimize for:

- correct capture metadata
- durable upload layout
- evidence completeness
- explicit recapture signaling
- compatibility with downstream descriptor / QA generation

Do not let shiny reconstruction paths replace evidence integrity as the default priority.
Do not let world-model ambitions weaken the raw capture contract or decision-grade evidence rules.

## Practical Rule For Agents In This Repo

When making changes here, optimize for:

1. scoped evidence capture for a known request
2. preserving the raw bundle and bridge contract
3. explicit QA and recapture readiness
4. downstream compatibility with qualification artifacts

Do not make this repo the place where final readiness judgments or downstream commercialization logic live.
