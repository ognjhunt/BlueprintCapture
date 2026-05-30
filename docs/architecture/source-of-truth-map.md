# Source Of Truth Map

This map separates evidence truth, advisory UX, local config, generated artifacts, and downstream authority. Use it when deciding whether a field, screen, test, or artifact can support a readiness claim.

## Truth Hierarchy

| Surface | Authority | Notes |
| --- | --- | --- |
| Raw capture evidence | Authoritative for what was captured | Video, timestamps, motion, poses, intrinsics, depth, confidence, device metadata, sidecars, rights/provenance, hashes, and completion marker. |
| Raw contract | Authoritative for new bundle shape | `docs/CAPTURE_RAW_CONTRACT_V3.md` defines the canonical V3/V3.1 bundle. |
| Upload state | Authoritative only for client upload progress and storage/submission registration | Upload completion can trigger bridge work, but it does not prove buyer, hosted-review, payout, provider, or launch readiness. |
| Bridge outputs | Authoritative for bridge processing status and handoff payloads | `capture_descriptor.json`, `qa_report.json`, and `pipeline_handoff.json` can block or downgrade downstream lanes. They do not rewrite raw truth. |
| Pipeline outputs | Authoritative for site-specific package materialization and optional trust layers | Capture should not claim Pipeline package quality before Pipeline artifacts exist. |
| WebApp outputs | Authoritative for buyer access, hosted review, licensing, ops, and launch-facing surfaces | Capture should not invent WebApp request/job/hosted-review proof. |
| Release validators | Authoritative for fail-closed release gate status | Missing release config, launch proof, provider proof, or device smoke is a blocker, not a code bug by default. |

## Raw Capture Truth

Authoritative raw evidence lives under:

```text
scenes/{scene_id}/captures/{capture_id}/raw/
```

Key truth files include:

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
- `walkthrough.mov` or Android `walkthrough.mp4`
- `sync_map.jsonl`
- `motion.jsonl`
- modality sidecars under `arkit/`, `arcore/`, `glasses/`, and `companion_phone/`

Rules:

- Preserve captured truth even when it is incomplete or weak.
- Use explicit missing-data semantics. Unknown rights, unavailable depth, absent upstream ids, or missing proof should stay visible.
- Do not replace missing WebApp/request/job ids with generated ids to make downstream sync appear ready.
- Do not infer derived generation, licensing, payout eligibility, provider readiness, or launch readiness from job type alone.

## Advisory UX vs Authoritative Decisions

The app owns real-time capture coaching and user state, not final commercialization decisions.

Advisory surfaces include:

- scan-home target cards and capture hints
- quality overlays and route prompts
- open-capture/current-location flows
- wallet banners and local ledger presentation
- onboarding and glasses setup copy
- launch-gate messages
- capture method pickers

Authoritative decisions must come from the correct backend or downstream artifact:

- payout eligibility and cashout state: payout provider/backend state plus approved capture records
- provider readiness: live provider config, SDK/device proof, and release validation
- hosted review: WebApp/request/job ids plus Pipeline/WebApp hosted artifacts
- city launch: launch proof, release config, live backend checks, capture submission, raw upload completion, Pipeline descriptor/QA/handoff, device proof, and monitoring evidence
- rights/commercialization: explicit rights/provenance metadata and downstream policy enforcement

## Ignored Local Release Config

These files are local operational inputs, not repo-source truth:

- `Config/*.xcconfig`, including `Config/BlueprintCapture.release.xcconfig`
- `android/local.properties`
- developer Gradle properties that carry secrets or release values
- Firebase/provider secret material

The repo confirms these are ignored:

- `.gitignore` ignores `Config/*.xcconfig`
- `.gitignore` ignores `android/local.properties`

Do not create, edit, print, or commit these during orientation/documentation work. If validators fail because these files are absent or incomplete, report the earliest gate as a blocker.

## Generated Media, Output, And Build Artifacts

Generated artifacts can be useful evidence of a run, but they are not the contract source unless a doc explicitly says so.

- `build/`, Xcode `DerivedData`, Android build outputs, and test products are generated.
- `BlueprintCapture/output/` contains generated visual/mock artifacts.
- `cloud/*/dist/` contains built JavaScript output for function packages; prefer `cloud/*/src/` for implementation reasoning.
- `cloud/*/node_modules/` is dependency output and should not be edited.
- captured media and uploaded raw bundles are evidence artifacts, not source code.

If generated artifacts contradict source or contract docs, inspect the generating code and latest run evidence before treating them as current truth.

## Pipeline And WebApp Boundaries

`BlueprintCapture` owns:

- truthful evidence capture
- raw bundle shape and local validation
- local upload queue state
- upload completion and submission registration attempts
- advisory user guidance

`BlueprintCapturePipeline` owns:

- site-specific package materialization
- GPU/world-model compatibility processing
- package manifests
- optional trust/review outputs
- downstream processing gates

`Blueprint-WebApp` owns:

- buyer, licensing, ops, and hosted-access surfaces
- site submission and buyer request ids
- capture job/request records
- hosted-review presentation
- launch-facing proof aggregation

Capture may carry downstream ids and handoff metadata when they are real. It must not fabricate them to satisfy Pipeline or WebApp paths.

## Current vs Historical Docs

Root-level autocomplete and Stripe documents are historical debugging/change-log docs. They can explain prior fixes, but they are not current release-readiness, provider-readiness, payout-readiness, launch-readiness, or public-copy authority.

Use these current orientation surfaces first:

- `README.md`
- `AGENTS.md`
- `PLATFORM_CONTEXT.md`
- `WORLD_MODEL_STRATEGY_CONTEXT.md`
- `docs/CAPTURE_RAW_CONTRACT_V3.md`
- `docs/PRIVATE_ALPHA_READINESS.md`
- `docs/PUBLIC_COPY_TRUTH_INDEX_2026-05-24.md`
- `docs/CAPTURER_MARKETING_COPY_POSITIONING_2026-05-13.md`
- `docs/architecture/ai-onboarding-map.md`
- `docs/architecture/command-safety-matrix.md`

If a historical doc claims production readiness, mock earnings, or setup completion, treat that as historical unless current code, validators, and live proof agree.
