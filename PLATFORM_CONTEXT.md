# Platform Context

<!-- SHARED_PLATFORM_CONTEXT_START -->
## Shared Platform Doctrine

### System Framing

- `BlueprintCapture` is the contributor evidence-capture tool inside Blueprint's three-sided marketplace.
- `BlueprintCapturePipeline` is the authoritative qualification, provenance, and provider-routing service.
- `Blueprint-WebApp` is the three-sided marketplace and operating system connecting capturers, robot teams, and site operators around qualification records and downstream work.
- `BlueprintValidation` is optional downstream infrastructure for provider benchmarking, runtime-backed demos, and deeper robot evaluation after qualification.

This platform is qualification-first.

### Three-Sided Marketplace

- **Capturers** supply evidence packages from real sites.
- **Robot teams** are the primary demand-side buyers of trusted qualification outcomes and downstream technical work.
- **Site operators** control access, rights, and commercialization boundaries for their facilities.

### Truth Hierarchy

- qualification records, readiness decisions, and supporting evidence links are authoritative
- capture-backed scene memory is the preferred downstream substrate when deeper technical work is justified
- preview simulations, world-model outputs, and world-model-trained policies are derived downstream assets; they do not rewrite qualification truth

### Product Stack

1. primary product: site qualification / readiness pack
2. secondary product: qualified opportunity exchange for robot teams
3. third product: scene memory / preview simulation / robot eval package
4. fourth product: world-model-based adaptation, managed tuning, training data, licensing

### Downstream Training Rule

- world-model RL and world-model-based post-training are first-class downstream paths for site adaptation, checkpoint ranking, synthetic rollout generation, and bounded robot-team evaluation
- those paths sit behind qualification and do not by themselves replace stricter validation for contact-critical, safety-critical, or contractual deployment claims
- Isaac-backed, physics-backed, or otherwise stricter validation remains the higher-trust lane when reproducibility, contact fidelity, or formal signoff matters

### Data Rule

- passive site capture and walkthrough evidence are valuable context for qualification, scene memory, preview simulation, and downstream conditioning
- strong robot adaptation gains usually require action-conditioned robot interaction data such as play, teleop logs, or task rollouts; site video alone is usually not enough for reliable policy training from scratch
- derived assets may inform routing and downstream work, but they must not mutate qualification state or source-of-truth readiness records
<!-- SHARED_PLATFORM_CONTEXT_END -->

This repo is the Blueprint evidence-capture layer.

## Local Doctrine

- This repo captures evidence. It does not make readiness decisions.
- The app owns real-time capture coaching only: motion, tracking health, coverage cues, package completeness, and permission gating.
- Lightweight semantic assists in-app are advisory only. They do not decide trust, approval, payout, rights status, or buyer readiness.
- The app should produce world-model-ready evidence when possible, but qualification remains upstream in `BlueprintCapturePipeline`.

## What This Repo Owns

- guided capture on iPhone and Meta glasses
- deterministic capture coaching during recording
- raw bundle packaging
- ARKit, intrinsics, depth, timing, meshes, and motion preservation when available
- capture-side rights, consent, and payout-eligibility inputs
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

- make final approval or payout decisions in-app
- assign final rights/compliance status
- run reconstruction in-app
- run world models
- run downstream simulation
- turn generated scenes into source truth

The handoff out of this repo is the raw evidence bundle plus bridge descriptor and QA outputs.
