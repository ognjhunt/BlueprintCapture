# Mobile Release Proof Gap Analyzer - 2026-05-31

Scope: `BlueprintCapture` iOS and Android release proof. This report is repo-local and validate-only. It does not release builds, upload to Firebase App Distribution, submit to TestFlight/App Store, run live capture uploads, invoke live backend mutation routes, deploy Firebase functions, publish Pub/Sub messages, or edit ignored release config.

## Bottom Line

Public/internal alpha posture and operational release proof are not the same thing.

- iOS remains the only external staged-alpha track described by the repo, but the current local release gate is blocked before archive/export because `BLUEPRINT_PAYOUT_PROVIDER` is missing from the ignored release xcconfig.
- Android has passing local unit tests and a repo-local internal release validator, but it remains internal-only. The current validate-only gate is blocked because `BLUEPRINT_BACKEND_BASE_URL` is missing for Android external alpha builds.
- Local bundle, upload, bridge, and demand tests are useful repo proof. They do not prove TestFlight/App Store readiness, Firebase App Distribution readiness, physical-device smoke, APNs/FCM registration, live upload, Pipeline materialization, WebApp hosted-review linkage, rights clearance, payout readiness, or provider readiness.

## Safe Command Evidence

| Command | Result | Proof meaning |
| --- | --- | --- |
| `git status --short` | Clean before and after the run | No unrelated worktree changes were present or introduced. |
| `PYTHONDONTWRITEBYTECODE=1 python3 scripts/validate_launch_readiness_tests.py` | Pass, 23 tests | Local launch-proof validator tests pass. Not live launch proof. |
| `PYTHONDONTWRITEBYTECODE=1 python3 scripts/android_xr_release_readiness_tests.py` | Pass, 5 tests | Local Android XR release-readiness validator tests pass. Not hardware proof. |
| `./scripts/archive_external_alpha.sh --validate-config-only` | Fail | Stage `release_config_blocked`; next input is `BLUEPRINT_PAYOUT_PROVIDER` in `Config/BlueprintCapture.release.xcconfig`. |
| `./scripts/android_alpha_readiness.sh --validate-config-only` | Fail | Stage `android_release_config_blocked`; Gradle reports `BLUEPRINT_BACKEND_BASE_URL must be set for Android external alpha builds.` |
| `cd android && ANDROID_HOME=/Users/nijelhunt_1/Library/Android/sdk ./gradlew testDebugUnitTest` | Pass | Android local unit tests pass. Not release build, App Distribution, or device proof. |
| `cd cloud/extract-frames && npm test` | Pass, 45 tests | Bridge/raw-contract local tests pass. Not deployed bridge proof or live Pub/Sub proof. |
| `cd cloud/referral-earnings && npm test` | Pass, 16 tests | Demand/referral local tests pass. Not live backend or payout-provider proof. |

Not run by design: archive/export, `alpha_readiness.sh`, `android_alpha_readiness.sh` without `--validate-config-only`, `assembleRelease`, Firebase App Distribution upload, TestFlight/App Store submission, live launch-city checks, live Firebase uploads/writes, Pub/Sub publishes, provider/payout routes, and production deploys.

## Current Public/Internal Alpha Posture

iOS public/internal alpha posture:

- The repo allows polished capture-first presentation and iOS staged-alpha framing, but only when real proof links iPhone capture, upstream request/job records, raw upload, bridge handoff, Pipeline package, and WebApp sync.
- The current local release config cannot pass validate-only, so no operational iOS release or launch-ready claim is supported from this run.
- iOS scan/capture copy keeps open capture and payout language review-gated. `RuntimeConfig` keeps payouts unavailable unless backend and backend-verified Stripe readiness exist.

Android public/internal alpha posture:

- Android is internal-only. Local unit tests passed and the app has phone capture, ARCore-aware bundle shaping, Android XR projected-glasses scaffolding, upload queueing, and fail-closed copy.
- Android cannot leave internal-only status until release config validation, unit tests, release artifact build, Android XR proof, physical-device smoke, Firebase App Distribution smoke, and downstream proof are all satisfied.
- Android XR projected glasses are video-first. Current repo proof must not claim pose, depth, geospatial, payout, provider, hosted-review, buyer-access, or launch readiness.

## Operational Release Gaps

### iOS Release Config

Current first blocker:

- `scripts/archive_external_alpha.sh --validate-config-only` failed at `release_config_blocked`.
- Missing current input: `BLUEPRINT_PAYOUT_PROVIDER` in the ignored release xcconfig.

Required config before iOS release/archive proof:

- Live backend and demand backend URLs.
- Main website, help center, bug report, terms, privacy, capture policy, account deletion, and support email.
- `BLUEPRINT_NEARBY_DISCOVERY_PROVIDER=places_nearby`.
- `BLUEPRINT_ALLOW_MOCK_JOBS_FALLBACK=NO`.
- `BLUEPRINT_ENABLE_INTERNAL_TEST_SPACE=NO`.
- `BLUEPRINT_ENABLE_REMOTE_NOTIFICATIONS=YES`.
- `APS_ENVIRONMENT=production`.
- `BLUEPRINT_PAYOUT_PROVIDER=stripe`.
- Explicit `BLUEPRINT_PAYOUT_PROVIDER_READY` value. The config flag is not live provider proof by itself.

Additional iOS gates still unproven:

- Release archive/export bundle lint with no bundled provider keys or `Secrets*.plist`.
- TestFlight/App Store install evidence on hardware.
- APNs and FCM registration on hardware.
- Real approved-job capture from release-like build.
- Raw upload and `capture_submissions/{captureId}` write for the same capture id.
- Bridge descriptor, QA, and handoff for that capture.
- Pipeline package/readiness artifact and WebApp upstream/request/job ids.
- Real launch proof with concrete evidence references, not `ops/launch-readiness/example.launch-proof.json`.

### Android Release Config

Current first blocker:

- `scripts/android_alpha_readiness.sh --validate-config-only` failed at `android_release_config_blocked`.
- Missing current input: `BLUEPRINT_BACKEND_BASE_URL` for Android external alpha builds.

Required config before Android release proof:

- `BLUEPRINT_BACKEND_BASE_URL`.
- `BLUEPRINT_DEMAND_BACKEND_BASE_URL`.
- Support/legal URLs and support email.
- `BLUEPRINT_ALLOW_MOCK_JOBS_FALLBACK=false`.
- `BLUEPRINT_NEARBY_DISCOVERY_PROVIDER=places_nearby`.
- `BLUEPRINT_ENABLE_GEMINI_MAPS_GROUNDING_FALLBACK=false`.
- `BLUEPRINT_PAYOUT_PROVIDER_READY=false` for Android external alpha until live backend provider proof is wired.
- `android/app/google-services.json` present.
- `POST_NOTIFICATIONS` declared.
- Android XR manifest track gating: mobile track uses `android.software.xr.api.spatial` with `required=false`; dedicated XR track requires `required=true`.

Additional Android gates still unproven:

- `assembleRelease`.
- Android XR release proof JSON with passing `device_smoke`, `app_distribution_smoke`, and `quality_guidelines_review`.
- Firebase App Distribution install smoke.
- Device notification/upload smoke.
- Real raw upload plus `capture_submissions/{captureId}` registration.
- Bridge, Pipeline, and WebApp same-capture proof.

## Bundle Proof Requirements

Required raw bundle proof for both platforms:

- Canonical prefix: `scenes/{scene_id}/captures/{capture_id}/raw/`.
- Required files include `manifest.json`, `provenance.json`, `rights_consent.json`, `capture_context.json`, `intake_packet.json`, `task_hypothesis.json`, `recording_session.json`, `capture_topology.json`, `video_track.json`, `hashes.json`, `capture_upload_complete.json`, video, `sync_map.jsonl`, `motion.jsonl`, and modality sidecars only when truthfully available.
- `hashes.json` must cover final raw files.
- `capture_upload_complete.json` must be uploaded last.
- `capture_profile_id` and `capture_capabilities` must match actual evidence.

iOS evidence found:

- `VideoCaptureManager.persistManifest` writes V3 manifest basics from actual device/app/ARKit state.
- `CaptureBundleFinalizer.finalize` patches the manifest, writes supplemental files, validates the materialized raw bundle, and only then returns a finalized bundle.
- iOS finalization records upstream blockers when WebApp/request/job ids are missing and keeps rights conservative by default.

Android evidence found:

- `AndroidCaptureBundleBuilder` writes canonical Android raw files, sidecars, hashes, upstream handoff, rights consent, and capture capabilities.
- Android phone ARCore evidence can be represented when sidecars exist.
- Android XR projected glasses deletes ARCore sidecars, emits `android_xr_glasses` / `android_xr_video_only`, treats phone IMU as diagnostic only, and prevents contributor payout eligibility.

## Upload And Handoff Proof Requirements

Upload proof requires all of the following for the same `scene_id` / `capture_id`:

1. Client uploads all raw files under the canonical raw prefix.
2. `capture_upload_complete.json` lands after all other raw files.
3. Client writes `capture_submissions/{captureId}` before reporting upload success.
4. Bridge writes `capture_descriptor.json`, `qa_report.json`, and `pipeline_handoff.json`.
5. Bridge publishes the Pipeline handoff.
6. Pipeline consumes the handoff and emits the downstream package/proof/readiness artifact being claimed.
7. WebApp has real `site_submission_id`, `buyer_request_id`, and `capture_job_id` before hosted-review, buyer-access, payout, or launch claims.

Current repo proof:

- iOS upload service refuses upload without Firebase guest auth, writes lifecycle state before upload, uploads the completion marker last, then requires `capture_submissions/{captureId}` registration before marking upload complete.
- Android upload repository removes the completion marker from the normal file list, uploads it last, and defers completion if Firebase auth/submission registration is unavailable.
- Cloud bridge local tests cover canonical path parsing, V3/V3.1 validation, Android ARCore acceptance, Android XR overclaim rejection, hash coverage, and upstream-id blocker preservation.

Current missing proof:

- No live same-capture raw upload was run.
- No live `capture_submissions/{captureId}` document was inspected.
- No live bridge descriptor/QA/handoff artifacts were inspected.
- No live Pub/Sub handoff or Pipeline/WebApp consumption was proven.

## Rights, Payout, And Provider Exclusions

Do not claim from this run:

- Rights-cleared capture.
- Buyer-ready or hosted-review-ready package access.
- Payout onboarding, payout settlement, instant payout, cashout readiness, or provider readiness.
- Stripe/live provider readiness from local config, UI copy, wallet history, or local tests.
- Android XR native pose, native IMU, depth, calibrated extrinsics, geospatial tracking, Gemini Live, Meta DAT production readiness, or public glasses readiness.
- App Store, TestFlight, Firebase App Distribution, device notification, or device upload readiness.

Allowed claim ceiling from this run:

- Repo-local validators and unit tests listed above pass.
- Current release config is fail-closed for both platforms.
- Android is internal-only.
- iOS operational release proof is blocked at release config before archive/export.

## Safe Next Edits

1. Add a repo-local `scripts/mobile_release_proof_gap_analyzer.py` that runs only the safe commands in this report, redacts config values, and emits a timestamped Markdown/JSON gap packet.
2. Add unit tests for that analyzer using recorded command-output fixtures for `release_config_blocked` and `android_release_config_blocked`.
3. Add a short `docs/mobile-release-proof-gap-analyzer.md` runbook pointing release owners to the safe analyzer and the required human/device/distribution artifacts.
4. Add an Android XR no-hardware blocked packet with `PYTHONDONTWRITEBYTECODE=1 python3 scripts/author_android_xr_no_hardware_packet.py --operator "$USER"` when an operator handoff artifact is needed.
5. After release owners fill ignored local config, rerun validate-only first; only then consider the broader local unit/release checks. Keep App Distribution, TestFlight/App Store, live upload, provider, payout, and production mutation commands out of autonomous runs unless explicitly scoped.
