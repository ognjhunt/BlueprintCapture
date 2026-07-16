# Public Beta Closure Pass (2026-07-16, post-PR-#52)

Status: point-in-time engineering closure record for the integration pass that
followed the merged audit remediation (PR #52). Nothing here is launch,
provider, payout, store, device, or buyer proof — those remain governed by
`ops/launch-readiness/` and the fail-closed release-gate scripts.

## What this pass fixed (verified in this environment)

### P0 — capture-submission contract (rules ↔ clients)

1. **Android registration writes were rules-incompatible.** The Android
   payload builder serialized `capture_start_epoch_ms`, `capture_duration_ms`,
   `motion_sample_count`, `motion_provenance`, `priority_weight`,
   `reservation_id`, and `imu_samples_available`; none are permitted by
   `captureSubmissionClientCreateKeys()` in `firestore.rules`, so every
   Android create/registration write was rejected. Those keys are now removed
   from the Firestore payload — the canonical raw bundle (manifest +
   motion files) remains the authoritative carrier of capture timing and
   motion truth, and nothing downstream read them from `capture_submissions`.
2. **iOS over-limit failures were rules-incompatible.**
   `UploadError.uploadLimitExceeded` maps to QA state
   `blocked_local_capture_limits`, which the rules did not allow; the rules
   enum now includes it.
3. **Monotonic client upload transitions.** Once a client reports
   `operational_state.upload_state == "uploaded"`, the only client write still
   permitted is an idempotent re-assertion of the uploaded/submitted terminal
   state (replayed completion write). Regression to `uploading`/`failed` or a
   failure status is denied; retry-after-failure stays allowed.
4. **Android now records documented failure transitions** (`upload_failed` +
   `upload_error` + `lifecycle.upload_failed_at`) on permanent failure,
   mirroring iOS, best-effort and never masking the locally preserved bundle.
5. **Contract test coverage:**
   - `cloud/firestore-rules-tests` — Firebase-emulator suite (23 tests)
     exercising the deployed ruleset with iOS-shaped and Android-shaped
     payloads: unauthenticated/wrong-owner denial, valid creates, upload
     start/completion/failure transitions, retry, replay idempotency,
     creator/raw-prefix immutability, payout/QA escalation denial,
     arbitrary-field denial, backend-owned record protection.
   - `CaptureSubmissionPayloadTest` (Android) and
     `CaptureSubmissionPayloadContractTests` (iOS) prove the builders emit
     only rules-permitted keys and states.

### CI and release governance

6. The `LaunchCityGateViewModelTests` fixed 50 ms sleep (red pre-merge Swift
   job on PR #52) is replaced with a deterministic await of the evaluation
   task; the two remaining polling loops got generous deadline-based bounds.
7. Swift unit tests and UI tests run as separate xcodebuild invocations so UI
   test app launches no longer contend with unit tests on one simulator.
8. CI no longer runs duplicate branch+PR builds for the same head (push runs
   are main-only; PR runs cancel superseded attempts; main runs never cancel).
9. Android lint is now blocking (`lintDebug`), and it caught a real defect:
   `AndroidXrProjectedCaptureManager` enabled audio without a `RECORD_AUDIO`
   permission check (now fail-closed with a diagnosable error).
   `assembleRelease` runs in CI and stays unsigned without release secrets.
10. New CI jobs: `cloud/referral-earnings` tests (previously not in CI),
    Firestore rules emulator contract suite, and the Python release-gate
    validators.

### Telemetry (one authoritative sink)

11. The iOS client's direct Firestore telemetry sink
    (`captureClientTelemetry`) was removed: `firestore.rules` default-denies
    it, so it silently failed on every event and duplicated the authoritative
    sinks. Crashlytics is the baseline client sink; the backend forward
    targets `POST /v1/creator/client-telemetry`, which exists in
    `Blueprint-WebApp` (`server/routes/creator.ts`) and persists server-side
    to `creatorClientTelemetry`. Redaction (tokens, authorization, passwords,
    secrets, email, phone, coordinates, addresses, filesystem paths,
    oversized values) and uncaught-crash caching are covered by
    `CaptureCrashTelemetryServiceTests`.

### Upload resilience

12. Bounded in-session iOS auto-retry (max 2, exponential backoff, transient
    failure classes only — `uploadFailed`, `submissionRegistrationFailed`);
    deterministic failures still surface immediately. The locally preserved
    bundle is never touched by a retry. Policy is unit-tested
    (`CaptureUploadAutoRetryPolicyTests`).

### Firestore indexes

13. Checked-in `firestore.indexes.json` (wired into `firebase.json`): the
    Android capture-history query (`creator_id ==` + `submitted_at DESC`)
    requires a composite index that was previously undeclared, plus the
    WebApp's existing `agentRuns` index so an indexes deploy from either repo
    does not drop the other's (deploys replace the full index set).

### Storage retention (ported from PR #51)

14. `storage.lifecycle.json` + `scripts/validate_storage_lifecycle.py` (+
    tests) + `docs/STORAGE_RETENTION_POLICY_2026-07-09.md`: committed,
    deployable lifecycle policy (raw captures tier to NEARLINE at 90 d,
    COLDLINE at 365 d, delete at 3650 d). Applying it to the bucket is an
    external ops step; the validator is wired into
    `scripts/archive_external_alpha.sh`.

## Decisions recorded

- **Wallet/earnings source of truth:** iOS reads the REST
  `v1/creator/earnings` endpoint and that endpoint is the authoritative
  earnings display for any public money claim. Android beta is explicitly
  capture-only: its wallet shows server-written `stats.*` sync history with
  honest "payout onboarding stays off-device" copy and no provider claims.
  Unifying Android onto the REST endpoint is the post-beta follow-up; nothing
  in this repo writes `stats.totalEarnings`/`availableBalance` from clients.
- **Capture preflight:** no `POST /v1/creator/captures/preflight` route exists
  in `Blueprint-WebApp` and no client on `main` calls one. Any future
  preflight client work must stay fail-closed until the authoritative route
  exists and is deployed.
- **Large-video ingest:** captures above the 1 GB inline ceiling remain
  fail-closed (`blocked_large_video_requires_segmented_ingest` +
  `large_video_ingest_blocked.json`, no fabricated frames/handoff/QA/success).
  The segmented/Cloud Run consumer and its deployment are unproven from this
  repo: `BLOCKED_LARGE_VIDEO_CONSUMER_PROOF`.
- **R8/minification:** stays disabled; enabling requires tested keep rules
  plus real-device smoke, which this environment cannot provide.
- **Legacy compiled-but-unreachable iOS UI** (`MainTabView`, legacy
  Wallet/Settings): deliberately not excised in this pass to keep the diff
  verifiable; tracked as P2.
- **App Check** on public demand/proxy endpoints: requires console
  provisioning plus client attestation rollout; external, staged follow-up.
- **PR #51 reconciliation:** rules/scenes lockdown, extract-frames size guard,
  crash telemetry, capture-quality safeguards, and site-type declaration are
  superseded by current `main`; the storage lifecycle cluster is ported here;
  the in-app VenuePermission authorization form is intentionally excluded
  (main evolved job-derived venue permissions; the stale form conflicts with
  that model).

## Still external (unchanged from `docs/PUBLIC_BETA_READINESS_2026-07-16.md`)

Money backend deployment + `CAPTURE_STATUS_UPDATE_SECRET` coordination,
payout provider proof, buyer demand seeding, release configs/signing/store
gates, Meta glasses hardware validation, physical-device smokes, and the
firestore rules/indexes parity deploy with `Blueprint-WebApp` (the rules and
indexes in this repo must land byte-identically there before either repo
deploys).
