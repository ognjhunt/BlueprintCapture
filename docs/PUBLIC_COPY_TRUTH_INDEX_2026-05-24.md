# Public Copy Truth Index

Date: 2026-05-24

Status: current repo source-of-truth index for documents that mention Stripe, payouts, earnings, paid assignments, marketplace mechanics, provider readiness, production readiness, buyer readiness, launch readiness, Android XR, Google/Meta glasses, Catalyst, capturer, or investor-facing claims.

Use this index before reusing any repo text in external capturer, startup, investor, launch, Catalyst, or public-site copy.

## Current Claim Ceiling

- BlueprintCapture captures truthful evidence first. Qualification, buyer access, hosted review, payout eligibility, provider readiness, and launch readiness are downstream decisions.
- Do not turn Stripe/debugging docs, mock earnings notes, settings implementation summaries, prompt packs, generated packets, or historical plans into public claims.
- Public/default copy should follow `docs/CAPTURER_MARKETING_COPY_POSITIONING_2026-05-13.md`.
- Release truth should follow `README.md`, `docs/PRIVATE_ALPHA_READINESS.md`, `docs/architecture/source-of-truth-map.md`, and the fail-closed scripts.
- Android XR, Meta, Google glasses, and provider language is internal/limited until assignment, hardware, release config, device smoke, downstream Pipeline/WebApp proof, and provider proof exist for the same chain.
- Payout copy must stay review-gated unless a real upstream assignment, approved payout policy, backend review, and live payout provider state support the exact cohort.

## Classification Key

- Current source-of-truth: can be used for repo orientation or guardrails, but still must not be clipped into public copy without its qualifiers.
- Historical/internal: useful context only. Not public copy and not launch, provider, payout, buyer, or commercialization proof.
- Unsafe/stale archive: contains old mock, setup, or completion language that could overclaim if quoted. Use only with the warning banner and current sources above.
- Ambiguous external draft: may be form-ready or external-draft material, but it is not submitted proof and must be refreshed before use.

## Inventory

| Path | Classification | Guardrail |
| --- | --- | --- |
| `.agents/skills/capture-public-copy-truth/SKILL.md` | Current source-of-truth | Repo-local Codex workflow for classifying public/Catalyst/investor/capturer claims as approved, blocked, or proof-required before use. |
| `AGENTS.md` | Current source-of-truth | Repo agent rules; no public copy extraction without capture-first/payout-provider qualifiers. |
| `AUTH_UI_IMPROVEMENTS.md` | Historical/internal | Superseded sign-in redesign notes; the "get paid instantly" copy it describes is not shipping copy and is not payout/provider/launch proof. |
| `AUTOCOMPLETE_DOCUMENTATION_INDEX.md` | Historical/internal | Already marked archived; not payout/provider/launch proof. |
| `AUTONOMOUS_ORG.md` | Current source-of-truth | Internal org doctrine; not external readiness proof. |
| `BlueprintCapture/AGENTS.md` | Current source-of-truth | iOS app agent rules; simulator and UI states are not payout/provider/TestFlight proof. |
| `BlueprintCapture/docs/2026-04-21-blueprintcapture-full-app-mockup-prompt-pack.md` | Historical/internal | Design prompt pack only; no invented payout readiness. |
| `BlueprintCapture/docs/superpowers/specs/2026-04-16-launch-city-org-backed-capture-design.md` | Historical/internal | Implementation/design context; not launch proof. |
| `CHANGES_APPLIED.md` | Unsafe/stale archive | Historical Stripe/debug note; warning required. |
| `CLAUDE.md` | Current source-of-truth | Agent rule file; not external copy. |
| `FILES_ADDED.md` | Unsafe/stale archive | Historical settings/mock-earnings summary; warning required. |
| `PLATFORM_CONTEXT.md` | Current source-of-truth | Platform doctrine; use with capture-first, real-site robot-evaluation/data-package-first framing. |
| `QUICKSTART.md` | Current source-of-truth | Developer quickstart with proof limits; not public readiness copy. |
| `README.md` | Current source-of-truth | Primary repo orientation and alpha boundaries. |
| `README_STRIPE_DEBUGGING.md` | Unsafe/stale archive | Historical Stripe debug guide; warning required. |
| `SETTINGS_INTEGRATION_GUIDE.md` | Unsafe/stale archive | Historical settings/payout integration guide; warning required. |
| `SETTINGS_TAB_SUMMARY.md` | Unsafe/stale archive | Historical mock-earnings/settings summary; warning required. |
| `STRIPE_BACKEND_CONFIG.md` | Unsafe/stale archive | Historical backend setup note; warning required. |
| `STRIPE_CONFIGURATION_CHECKLIST.md` | Unsafe/stale archive | Historical Stripe checklist; warning required. |
| `STRIPE_DEBUGGING_GUIDE.md` | Unsafe/stale archive | Historical Stripe debugging guide; warning required. |
| `STRIPE_DEBUG_QUICK_START.md` | Unsafe/stale archive | Historical Stripe quick-start; warning required. |
| `STRIPE_DOCUMENTATION_INDEX.md` | Historical/internal | Archived Stripe index with warning; not proof. |
| `STRIPE_ERROR_REFERENCE.txt` | Unsafe/stale archive | Historical Stripe error card; warning required. |
| `STRIPE_FLOW_DIAGRAM.md` | Unsafe/stale archive | Historical Stripe flow doc; warning required. |
| `STRIPE_IMPLEMENTATION_SUMMARY.txt` | Unsafe/stale archive | Historical Stripe implementation summary; warning required. |
| `STRIPE_ISSUE_SUMMARY.md` | Unsafe/stale archive | Historical Stripe issue summary; warning required. |
| `STRIPE_QUICK_SETUP.md` | Unsafe/stale archive | Historical quick setup; warning required. |
| `VISION.md` | Current source-of-truth | Cross-repo strategic doctrine; aspirational scope is not launch, provider, payout, buyer, or readiness proof. |
| `WORLD_MODEL_STRATEGY_CONTEXT.md` | Current source-of-truth | World-model strategy doctrine; buyer/licensing/flywheel framing is strategic scope, not launch, provider, payout, buyer, or commercialization proof. |
| `android/AGENTS.md` | Current source-of-truth | Android agent rules; Android remains internal-only until gates pass. |
| `android/IMPLEMENTATION_SPEC.md` | Current source-of-truth | Android implementation spec; not public launch proof. |
| `android/README.md` | Current source-of-truth | Android local setup/readiness context; no public Android/Meta/XR claims without release proof. |
| `cloud/AGENTS.md` | Current source-of-truth | Cloud agent rules; no fabricated provider, payout, hosted-review, or launch proof. |
| `docs/ALPHA_GO_NO_GO_CHECKLIST_2026-03-22.md` | Historical/internal | Dated go/no-go checklist; current validation scripts and `docs/PRIVATE_ALPHA_READINESS.md` win. |
| `docs/ANDROID_XR_AI_GLASSES_READINESS.md` | Current source-of-truth | Current Android XR claim ceiling; video-first and hardware-blocked. |
| `docs/ANDROID_XR_HARDWARE_VALIDATION_PACKET_2026-05-23.md` | Current source-of-truth | Hardware validation packet; checklist is not completed proof. |
| `docs/ANDROID_XR_OFFLINE_NO_HARDWARE_PACKET.md` | Current source-of-truth | Offline no-hardware packet instructions; valid local blocked packet only, not hardware or public readiness proof. |
| `docs/ANDROID_XR_ON_DEVICE_QA_CHECKLIST_2026-05-23.md` | Current source-of-truth | QA checklist; only completed evidence can support readiness claims. |
| `docs/AUTONOMOUS_DEMAND_SYSTEM_FULL_SPEC_2026-03-20.md` | Historical/internal | Internal demand-system spec; not public marketplace or live-supply proof. |
| `docs/CAPTURE_BRIDGE_CONTRACT.md` | Current source-of-truth | Bridge contract; downstream outputs do not rewrite raw truth. |
| `docs/CAPTURE_RAW_CONTRACT_V3.md` | Current source-of-truth | Raw bundle contract; payout/provider/launch claims stay blocked without upstream proof. |
| `docs/CAPTURE_TO_PIPELINE_ANDROID_XR_PROOF_MAP.md` | Current source-of-truth | Proof map; no Android XR public claim without matching evidence chain. |
| `docs/CAPTURER_MARKETING_COPY_POSITIONING_2026-05-13.md` | Current source-of-truth | Approved/blocked copy guardrail for capturer-facing language. |
| `docs/DEMAND_DRIVEN_OPPORTUNITY_SERVICE_2026-03.md` | Current source-of-truth | Internal service spec; marketplace mechanics are not public supply claims. |
| `docs/GPU_PIPELINE_COMPATIBILITY.md` | Current source-of-truth | Compatibility contract; provider/runtime support is not commercialization proof. |
| `docs/MOBILE_RELEASE_PROOF_GAP_ANALYZER_2026-05-31.md` | Current source-of-truth | Repo-local validate-only release-proof gap report; blocked release config, device, distribution, payout, provider, and downstream proof remain blockers, not launch proof. |
| `docs/NEXT_SESSION_ALPHA_READINESS_MASTER_PROMPT_2026-03-22.md` | Historical/internal | Next-session prompt; not launch state. |
| `docs/NEXT_SESSION_ANDROID_XR_MASTER_PROMPT_2026-03-25.md` | Historical/internal | Android XR continuation prompt; not current hardware, public launch, provider, or Catalyst proof. |
| `docs/NEXT_SESSION_TRUE_ERROR_SPECS_2026-03-18.md` | Historical/internal | Next-session prompt/spec; not current public copy. |
| `docs/PRIVATE_ALPHA_READINESS.md` | Current source-of-truth | Current alpha readiness and fail-closed release posture. |
| `docs/PUBLIC_BETA_CLOSURE_2026-07-16.md` | Current source-of-truth | Post-#52 closure record: contract/CI/telemetry fixes and decisions; not launch, provider, payout, store, or buyer proof. |
| `docs/PUBLIC_BETA_READINESS_2026-07-16.md` | Current source-of-truth | Audit-backed public-beta gap map; blocker states are point-in-time findings, not launch, provider, payout, or buyer proof. |
| `docs/STORAGE_RETENTION_POLICY_2026-07-09.md` | Current source-of-truth | Committed, deployable storage lifecycle policy; applying it to the bucket is an external ops step, not retention proof. |
| `docs/architecture/ai-onboarding-map.md` | Current source-of-truth | Agent onboarding map; generated/support surfaces are not authority. |
| `docs/architecture/command-safety-matrix.md` | Current source-of-truth | Command safety; validators can be blocked by missing local config. |
| `docs/architecture/refactor-hotspots.md` | Current source-of-truth | Internal architecture risk map; not public readiness copy. |
| `docs/architecture/source-of-truth-map.md` | Current source-of-truth | Authority boundary map; use for claim routing. |
| `docs/superpowers/plans/2026-03-28-autonomous-org-implementation.md` | Historical/internal | Implementation plan; not live org/marketplace proof. |
| `docs/superpowers/plans/2026-04-24-ios-city-launch-readiness-gates.md` | Historical/internal | Launch-gate plan; current scripts/proof docs win. |
| `docs/superpowers/specs/2026-03-28-autonomous-org-design.md` | Historical/internal | Design spec; not live marketplace proof. |
| `ops/launch-readiness/README.md` | Current source-of-truth | Launch proof instructions; example/template artifacts are not real launch proof. |
| `output/doc/google_android_xr_catalyst_blueprintcapture_packet_2026-05-24.md` | Ambiguous external draft | Local Catalyst answer bank only; not submitted, not public marketing copy, and not Android XR/payout/provider/launch proof. |
| `scripts/AGENTS.md` | Current source-of-truth | Script guardrails; do not soften fail-closed blockers. |

## Directly Guarded Unsafe Archives

These files must carry a `Current-vs-public-copy note` banner near the top:

- `CHANGES_APPLIED.md`
- `FILES_ADDED.md`
- `README_STRIPE_DEBUGGING.md`
- `SETTINGS_INTEGRATION_GUIDE.md`
- `SETTINGS_TAB_SUMMARY.md`
- `STRIPE_BACKEND_CONFIG.md`
- `STRIPE_CONFIGURATION_CHECKLIST.md`
- `STRIPE_DEBUG_QUICK_START.md`
- `STRIPE_DEBUGGING_GUIDE.md`
- `STRIPE_ERROR_REFERENCE.txt`
- `STRIPE_FLOW_DIAGRAM.md`
- `STRIPE_IMPLEMENTATION_SUMMARY.txt`
- `STRIPE_ISSUE_SUMMARY.md`
- `STRIPE_QUICK_SETUP.md`

## Scanner

`scripts/validate_launch_readiness_tests.py` scans Markdown and text docs for risky public-copy claim patterns, including Stripe/payout/provider/marketplace/readiness, Android XR, Google/Meta glasses, Catalyst, capturer, and investor terms. A matching doc must be listed in this index, and unsafe/stale Stripe/settings archives must carry a direct warning banner.
