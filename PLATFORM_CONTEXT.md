# Platform Context

<!-- SHARED_PLATFORM_CONTEXT_START -->
## Shared Platform Doctrine

### System Framing

- `BlueprintCapture` is the contributor evidence-capture tool inside Blueprint's three-sided marketplace.
- `BlueprintCapturePipeline` is the authoritative qualification, privacy, provenance, and downstream-routing service.
- `Blueprint-WebApp` is the marketplace and operating system that ingests pipeline outputs and exposes buyer, ops, preview, and hosted-session surfaces.
- `BlueprintValidation` remains optional downstream infrastructure for benchmarking, runtime-backed demos, and deeper robot evaluation after qualification.

This platform is qualification-first.

### Three-Sided Marketplace

- **Capturers** gather evidence packages from real sites.
- **Robot teams** are the primary buyers of trusted qualification outputs, previews, and deeper downstream work.
- **Site operators** control access, consent, rights, and commercialization boundaries for their facilities.

### Truth Hierarchy

- qualification records, readiness decisions, provenance, and rights/compliance outputs are authoritative
- privacy-safe derived media, World Labs previews, scene-memory bundles, and hosted/runtime artifacts are downstream products
- downstream products do not rewrite qualification truth

### Product Stack

1. primary product: qualification record / readiness decision / buyer-safe evidence bundle
2. secondary product: privacy-safe preview generation and marketplace routing
3. third product: scene memory / hosted runtime prep / deeper evaluation packages
4. fourth product: managed tuning, training data, licensing, and deployment support
<!-- SHARED_PLATFORM_CONTEXT_END -->

This repo is the capture-layer producer of the raw evidence contract.

## What This Repo Owns

`BlueprintCapture` owns:

- guided capture on iPhone and Meta glasses
- capture coaching during recording
- bundle finalization and upload
- preservation of ARKit, motion, timing, and depth evidence when available
- capture-side intake, task context, rights, and payout eligibility inputs

This repo does not decide qualification, readiness, rights approval, or hosted runtime launchability.

## Canonical Output

The app uploads the canonical raw bundle:

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

The cloud bridge then materializes:

```text
scenes/{scene_id}/captures/{capture_id}/capture_descriptor.json
scenes/{scene_id}/captures/{capture_id}/qa_report.json
scenes/{scene_id}/captures/{capture_id}/pipeline_handoff.json
```

and publishes the handoff to the `blueprint-capture-pipeline-handoff` Pub/Sub topic, which triggers the pipeline Cloud Run job.

## Current Default Product Behavior

The current phone and glasses flows request:

- `qualification`
- `preview_simulation`
- `deeper_evaluation` (automatically co-requested whenever `preview_simulation` is present)

That means the default product intent today is:

- upload evidence for qualification
- trigger privacy redaction (SAM3/VIP) and World Labs Marble world generation
- prepare evaluation artifacts for hosted-runtime readiness

Every capture from either device goes through the full pipeline end-to-end: qualification → GPU privacy → World Labs → automatic web app surfacing.

## Important Boundary

This repo should be understood as:

- the producer of evidence and capture-side metadata
- not the producer of hosted runtime artifacts
- not the producer of `evaluation_prep/site_world_spec.json`
- not the source of truth for readiness or buyer-visible launch state

## Upload And Trigger Model

The upload service finalizes the bundle and writes the completion marker as part of the raw upload layout.

Downstream systems pick up the capture through the bridge-produced handoff on `blueprint-capture-pipeline-handoff` (primary). The storage trigger also routes raw upload completions to the same topic as a secondary path, so both flows converge on the same pipeline dispatcher.

## Practical Rule For Agents In This Repo

When changing this repo, optimize for:

1. correct raw-bundle structure
2. conservative rights and consent defaults
3. preserving real sensor evidence instead of inferring it
4. ensuring upload completion means the raw contract is truly ready
5. keeping preview/runtime expectations out of the capture UX unless those downstream lanes are actually requested
