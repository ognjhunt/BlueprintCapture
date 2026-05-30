---
name: capture-public-copy-truth
description: Review BlueprintCapture public, Catalyst, investor, capturer, launch, Stripe/payout/provider, Android XR, and Google/Meta glasses copy before use by classifying every claim as approved, blocked, or proof-required against repo truth docs.
---

# Capture Public Copy Truth

Use this skill before drafting, reusing, or approving any external-facing BlueprintCapture copy, including public-site, Catalyst, investor, capturer, launch, payout, provider, Android XR, Google glasses, or Meta glasses language.

This workflow is a review gate. Do not write as if a Catalyst application, investor update, launch packet, provider integration, payout setup, or public submission has already happened unless current proof is cited in the repo.

## Required Sources

Read these first, in order:

1. `README.md`
2. `docs/PUBLIC_COPY_TRUTH_INDEX_2026-05-24.md`
3. `docs/architecture/source-of-truth-map.md`
4. `docs/CAPTURER_MARKETING_COPY_POSITIONING_2026-05-13.md`
5. `docs/ANDROID_XR_AI_GLASSES_READINESS.md`
6. `PLATFORM_CONTEXT.md`
7. `WORLD_MODEL_STRATEGY_CONTEXT.md`
8. `docs/CAPTURE_RAW_CONTRACT_V3.md`
9. `docs/PRIVATE_ALPHA_READINESS.md` when release, alpha, TestFlight, launch, or distribution state is mentioned

If a candidate copy source is listed as historical/internal, unsafe/stale archive, or ambiguous external draft in the truth index, treat it as non-authoritative until current sources and proof agree.

## Classification Rules

Classify every material claim before use:

- `approved`: Current repo truth supports the statement as default public-safe wording, with any required qualifiers preserved.
- `proof-required`: The statement might be usable only after exact proof is cited from current source docs, release validators, hardware/device evidence, live backend/provider state, Pipeline/WebApp artifacts, or approved policy. Do not publish it until that proof exists.
- `blocked`: The statement relies on stale Stripe/setup docs, mock earnings, generated packets, historical prompts, unsupported provider/device state, missing upstream ids, or language that turns advisory UX into payout, buyer, provider, marketplace, or launch readiness.

Do not use live APIs, Stripe setup, payment credentials, Google/Meta credentials, Firebase secrets, or local release config to satisfy this review. Missing live evidence is a review result, not something to patch around.

## Approved Phrasing

Use this family of claims when the copy needs safe default language:

- "BlueprintCapture records truthful real-site walkthrough evidence."
- "Captures preserve raw video, timestamps, motion, device metadata, and available pose/depth signals."
- "Qualification, buyer access, hosted review, payout eligibility, provider readiness, and launch readiness are downstream decisions."
- "Blueprint turns captured evidence into site-specific world-model packages and hosted access through downstream processing."
- "Approved assignments may show a quoted payout before capture; final eligibility still depends on quality, rights, scope, account review, and provider state."
- "Phone capture is the default; Google/Meta glasses and Android XR paths are internal or limited until assignment, hardware, release, and downstream proof exist for the same chain."
- "Android XR projected capture is currently video-first in this repo and not world-tracking, geospatial, payout, or public-launch authoritative."

## Blocked Phrasing

Block or rewrite claims like these unless a newer source doc explicitly changes the claim ceiling:

- "Start earning today."
- "Every capture earns" or "get paid for any place you capture."
- "Guaranteed payouts," "cash out anytime," or average/minimum earnings without approved policy and live provider proof.
- "Stripe is ready," "provider-ready," or "payout-ready" from setup docs, config examples, or tests alone.
- "Marketplace is live," "buyer-ready," "buyer access is ready," or "launch-ready" from capture completion or contract-only proof.
- "Rights-cleared" without explicit rights/provenance and downstream policy evidence.
- "Google/Meta smart glasses are live for everyone."
- "Android XR is public-ready," "Android XR world tracking is verified," or "Android XR geospatial/ARCore pose/depth proof exists" without matching hardware and raw-bundle evidence.
- "Catalyst application submitted," "Catalyst accepted," or "investor proof package complete" when the repo only contains draft/local answer-bank material.

## Proof-Required Claims

Mark these as `proof-required` unless exact current evidence is cited:

- Any payout, Stripe, wallet cashout, provider-readiness, or earnings claim.
- Any marketplace, buyer-ready, hosted-review, launch-ready, city-launch, or live-supply claim.
- Any Android XR, Google glasses, Meta glasses, Gemini Live, hardware-readiness, projected-camera, device-smoke, or public-distribution claim.
- Any Catalyst, investor, capturer-cohort, external submission, or public launch copy that implies acceptance, submission, live users, paid assignments, or buyer demand.
- Any statement copied from `output/`, historical prompt packs, stale Stripe docs, or generated packets.

## Review Output

Return a compact review in this format:

```text
Audience:
Candidate source:
Source docs checked:
Decision: approved | blocked | proof-required

Claim log:
| Claim | Classification | Evidence | Required edit |
| --- | --- | --- | --- |

Approved phrasing:
Blocked phrasing:
Proof required:
Next action:
```

Rules for the output:

- Keep claims separate; do not approve a paragraph when one sentence is blocked.
- Use `approved`, `blocked`, and `proof-required` exactly.
- Cite repo paths or concrete evidence references, not vibes or assumptions.
- If no proof is available, say what proof is missing and keep the copy blocked or proof-required.
- Do not draft external submission copy as if submitted.
