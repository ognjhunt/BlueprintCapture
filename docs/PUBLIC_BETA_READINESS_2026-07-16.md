# Public Beta Readiness — Audit + Remediation (2026-07-16)

Status: point-in-time, audit-backed gap map for taking BlueprintCapture (iOS + Android + Meta glasses) to a public beta with all marketplace sides working. Nothing here is launch, provider, payout, or buyer proof — every remaining blocker below must be closed with real evidence per `ops/launch-readiness/` and the fail-closed scripts.

## How this was produced

Four parallel deep audits (iOS app, Android app + Meta Wearables DAT, cloud functions + Firebase rules, end-to-end marketplace/payments loop) over the full codebase, followed by a remediation pass. Everything marked FIXED below is in this branch; everything marked OPEN is not closable from this repo alone or needs hardware/secrets/external services.

Verified in this environment:

- `cloud/extract-frames`: 58/58 tests pass (5 new).
- `cloud/referral-earnings`: 37/37 tests pass (21 new).
- `scripts/archive_external_alpha.sh --validate-config-only`: storage-rules and upload-resilience checks pass; release-config gate correctly fail-closed (secrets are not in the repo — expected).
- `scripts/validate_launch_readiness_tests.py`: 23/23 pass (fixed a pre-existing failure: `VISION.md` missing from the public-copy truth index).
- iOS (Swift) and Android (Gradle) builds cannot run in this Linux sandbox — those changes are static-reviewed and must be compiled + tested per the commands in `AGENTS.md` before merge.

## What was genuinely solid before this pass (verified, no action needed)

- Capture → upload cores on both platforms: resumable chunked uploads with sha256 verification, offline queues, crash recovery, fail-closed submission registration (raw-storage success alone is never reported as success).
- Bundle contract enforcement (`CaptureRawContractV3Validator` on iOS; fail-closed `AndroidCaptureBundleBuilder` with honest XR/glasses modality + `payoutEligible=false` for XR).
- Money-field security model: clients cannot write `payout_cents`, paying statuses, or `stats.*` (verified against `firestore.rules`); the server recomputes `world_model_candidate` from actual artifacts instead of trusting the manifest.
- Payout UX honesty: no fabricated balances anywhere; payouts are gated on `BLUEPRINT_PAYOUT_PROVIDER_READY` and stay honestly "unavailable" when off.
- The Meta SDK stub cannot leak fake capture data (stub stream is empty + CLOSED; the flow fails instead of fabricating frames).

## Fixed in this pass

### Money path (cloud)

1. **`updateCaptureStatus` had no authentication** — anyone could mark captures approved/paid with arbitrary `payout_cents` and trigger referral commissions. Now fail-closed: requires a `CAPTURE_STATUS_UPDATE_SECRET` bearer (timing-safe) or an admin/ops-claimed Firebase ID token. Callers (WebApp ops) must send the secret — coordinate before deploy.
2. **Referral crediting could double-pay** — the idempotency guard was read outside a transaction while Firestore triggers are at-least-once. `onCaptureApproved` now runs entirely in a transaction, with a server-side self-referral guard, and treats `invited` as a pre-first-capture status (bonus no longer silently skipped). Commission math extracted to `referral-core.ts` with unit tests.
3. **The referral flow was dead end-to-end** — both clients wrote `referralCodes/{code}` and the referrer's `referrals/` records directly, which `firestore.rules` denies (`write: if false`), so referral-code creation *and* attribution batches were rejected. New `onUserProfileWritten` trigger performs both writes server-side (validating `referredByCode` against the claimed referrer so commissions can't be forged); iOS `ReferralService` and Android `AuthRepository` now only write their own user document (which rules allow). Also fixes Android's `signed_up`/`signedUp` status drift.
4. **extract-frames OOM ceiling** — a 1.5 GB inline video limit on a 2 GiB instance whose `/tmp` is RAM-backed tmpfs meant legitimate large captures would OOM-crash-loop. Memory raised to 4 GiB, inline ceiling lowered to 1 GB (larger captures route to segmented ingest via the existing graceful block path).
5. **Concurrent first-run duplicate handoffs** — the Pub/Sub receipt guard was read-then-write. The receipt now doubles as an atomic claim (GCS `ifGenerationMatch` preconditions, stale-claim takeover), with the decision logic pure and unit-tested.
6. Unknown client-supplied `requested_outputs` values no longer become downstream routing lanes (allowlist).

### iOS capture-truth violations (all reachable in the shipping redesign UI)

7. **Fabricated persona everywhere**: every user saw "Maya · Sacramento, CA", "Capturer #214", "27 Captures · 4.9 Rating · 98% Pass rate", a "Certified" rights chip, and an "Active" status chip. Identity now binds to the real Firebase user (`RedesignCoordinator`); fabricated stats/chips removed until real backend data exists.
8. **Fake capture history and QA verdicts**: History and Earnings rendered `BPSample.history` ("Validated"/"Recapture" verdicts for captures that never happened) and hardcoded "3 Reviewed / 1 Needs fix". Both now read the user's real `capture_submissions` via a new `BPCaptureHistoryStore` (equality-only query, no composite index needed) with honest empty states.
9. **Fake notifications** ("Capture validated — passed QA") and a permanent fake unread dot: replaced with an honest empty state; dot removed.
10. **Real capture flow pre-filled a fake person** ("Jordan Smith / jordan@example.com") as "YOUR DETAILS": now loads the signed-in user's actual name/email/phone.
11. **Seven dead Settings toggles** (auto-upload, face-blur, precise location, …) that controlled nothing: replaced with real actions only — system notification settings, legal/policy links, and **in-app account deletion** (store requirement; previously unreachable in the shipping UI).
12. **Dead "Sign out"** button on Profile: wired (with confirmation) to Firebase sign-out + guest re-bootstrap.
13. Orphaned simulated capture flow deleted (`BPCaptureFlow`/`BPViewfinderView`/`BPReviewView`/`BPUploadView`/`BPTaskDetailView`/`BPCameraPreview` — fake upload progress, fake checksums, fake sensor readouts) along with the whole `BPSample` fabricated dataset (rights-training copy kept).
14. Home discovery now uses the app-level shared `NearbyAlertsManager` instead of a throwaway instance (geofence alert state was split across two managers).

### Android

15. **Launch-gate dead end for new users**: the city gate only read `getLastKnownLocation`, permanently locking out fresh devices with no cached fix. Now falls back to an active one-shot location request (15 s timeout, API 29/30+ paths).
16. **No release signing config**: `assembleRelease` produced an unsigned artifact. Signing now wires from untracked `BLUEPRINT_RELEASE_STORE_FILE/_STORE_PASSWORD/_KEY_ALIAS/_KEY_PASSWORD` properties or env vars (absent → stays unsigned, so no placeholder keystore can ship).
17. `BLUETOOTH_SCAN` marked `neverForLocation` (Play policy scrutiny reduction).
18. Meta glasses frame-decode failure is no longer a silent capture loss: non-JPEG streams are detected and logged with leading bytes for hardware validation, and the finalize error now tells the user the frames are preserved on-device.
19. Referral writes aligned with security rules (see #3); dead `captureModalityFor` removed.

### Repo hygiene (investor-facing first impression)

20. Removed 13 stray device screenshots, two `firebase-debug` logs, and a tracked `node_modules` artifact; `.gitignore` extended. Historical Stripe/session docs stay (they're referenced by the copy-truth index and readiness validator) — they're already banner-marked as historical/internal.

## OPEN — what still blocks a public beta (cannot be closed from this repo)

Ranked; each needs real evidence, not doc edits.

1. **BLOCKER — the money backend lives in Blueprint-WebApp / `tryblueprint.io`.** Every earnings/Stripe endpoint the clients call (`v1/creator/earnings`, `v1/stripe/*`, `v1/creator/launch-status`, …) is external to this repo. Confirm they are deployed and forwarded by the gateway, then flip `BLUEPRINT_PAYOUT_PROVIDER_READY` with proof per `ops/launch-readiness/`. The new `CAPTURE_STATUS_UPDATE_SECRET` must be configured on the function and shared with the WebApp ops caller.
2. **BLOCKER — payouts are off in checked-in config on both platforms** (intentionally, per truth rules). iOS needs `BLUEPRINT_PAYOUT_PROVIDER*` in the untracked release xcconfig; Android has **no Stripe onboarding path at all** — a public beta either ships Android as capture-only (stated honestly, as today's copy does) or builds cash-out first.
3. **BLOCKER — wallet source-of-truth split**: iOS reads REST `v1/creator/earnings`; Android reads Firestore `stats.*`, and nothing in this repo writes `stats.totalEarnings`/`availableBalance`. The same capturer can see different balances per platform. Decide one authority (recommend: both platforms read the REST earnings endpoint) before any public money claims.
4. **BLOCKER — buyer side is in the WebApp repo.** "All sides of the marketplace working" (robot teams requesting/paying, demand feed populated with real `capture_jobs`/`demand_signals`) cannot be demonstrated from this repo. Seed real demand data before beta or the opportunity feed is empty (mock fallback is correctly off in release).
5. **HIGH — release configs + store gates are RED by design** until secrets/config exist: iOS `Config/BlueprintCapture.release.xcconfig`, Android release properties + keystore, Play declarations (background location, dataSync foreground service), APNs production cert. Run `./scripts/archive_external_alpha.sh` and `./scripts/android_alpha_readiness.sh` to green before any distribution.
6. **HIGH — Meta glasses path needs real-hardware validation**: the JPEG-frame assumption (now instrumented, see #18) must be confirmed against the real MWDAT stream, plus `MWDAT_APPLICATION_ID`/`CLIENT_TOKEN` provisioning. Until then glasses capture stays behind `MWDAT_ENABLE_PRIVATE_SDK=false`.
7. **MEDIUM — possible referral double-count on iOS wallet**: `totalPending = backend pending + Firestore referral cents`; if the backend's `pending_payout_cents` already includes referral commissions, iOS double-counts. Needs a backend-semantics decision (this repo can't verify).
8. **MEDIUM — compile + device passes for this branch**: iOS `xcodebuild test`, Android `testDebugUnitTest` + `assembleRelease`, and a device smoke of onboarding → capture → upload → history. This sandbox has no Xcode/Android SDK; do this first.
9. **LOW — known accepted trade-offs in the referral redesign** (from adversarial code review of this branch): (a) a brand-new referral code is resolvable only after the server registers its `referralCodes` lookup (seconds); a code shared and redeemed inside that window reads as invalid — retrying succeeds; (b) the client returns "attributed" optimistically after writing its own doc; the server may still clear an attribution that fails validation (commission integrity is unaffected — the server is authoritative); (c) captures over the 1 GB inline ceiling are blocked-with-artifacts and depend on the segmented/Cloud Run ingest path being operational.
10. **MEDIUM — recommendations not done here** (deliberately, to keep the diff verifiable): bounded auto-retry for failed in-session iOS uploads; excising the compiled-but-unreachable legacy UI (`MainTabView`, legacy Wallet/Settings — only UI tests reference it); enabling R8 minification with keep-rule validation; App Check on the public demand/proxy endpoints (they remain unauthenticated — quota/cost abuse surface); Firestore composite-index manifest (`firestore.indexes.json`).

## Suggested go/no-go sequence

1. Merge this branch after iOS/Android test + build passes.
2. Deploy rules + both function codebases (`firebase deploy`); set `CAPTURE_STATUS_UPDATE_SECRET`; coordinate the WebApp caller.
3. Verify referral loop end-to-end in staging: sign-up with code → `referralCodes` lookup + referral record created server-side → approve a test capture via authenticated `updateCaptureStatus` → commission + first-capture bonus land exactly once in `stats.*`.
4. Close the external blockers (1–4) from the WebApp repo with `ops/launch-readiness/` evidence.
5. Green both release-gate scripts, then run the private-alpha cohort before widening to public beta.
