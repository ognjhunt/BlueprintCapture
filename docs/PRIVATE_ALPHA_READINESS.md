# Private Alpha Readiness

## Required local config
- Set `BLUEPRINT_DEMAND_BACKEND_BASE_URL` to the live demand backend.
- Set `BLUEPRINT_BACKEND_BASE_URL` only when the creator notification/device routes are live and tested on hardware.
- Set the external support/legal config so testers do not hit dead ends:
  - `BLUEPRINT_MAIN_WEBSITE_URL`
  - `BLUEPRINT_HELP_CENTER_URL`
  - `BLUEPRINT_BUG_REPORT_URL`
  - `BLUEPRINT_TERMS_OF_SERVICE_URL`
  - `BLUEPRINT_PRIVACY_POLICY_URL`
  - `BLUEPRINT_CAPTURE_POLICY_URL`
  - `BLUEPRINT_ACCOUNT_DELETION_URL`
  - `BLUEPRINT_SUPPORT_EMAIL_ADDRESS`
- Enable Firebase Anonymous Auth for the active project before running real capture discovery/claim/upload flows.
- Do not restore `Secrets.plist` or `Secrets.local.plist` to the app target.
- Do not ship Places or Gemini client keys in iOS or Android builds. Nearby/provider requests must go through the demand backend proxy routes.
- Treat any values previously stored in `BlueprintCapture/Support/Secrets.plist` as compromised and rotate them before distribution.

## Current launch posture
- External 100-user rollout posture on 2026-03-26: iOS only.
- Android has a repo-local release validator/build lane, but it remains internal-only until `./scripts/android_alpha_readiness.sh` passes with real release config and device/App Distribution smoke is signed off.
- Demand/opportunity ranking runs against the direct Firebase router.
- Nearby discovery, autocomplete, and details are proxied through the demand backend:
  - `POST /v1/nearby/discovery`
  - `POST /v1/places/autocomplete`
  - `POST /v1/places/details`
- Mobile should not assume the public `tryblueprint.io` gateway forwards the new demand POST routes.
- Release/TestFlight builds must keep `BLUEPRINT_ALLOW_MOCK_JOBS_FALLBACK=NO` and `BLUEPRINT_ENABLE_INTERNAL_TEST_SPACE=NO`.
- Remote push is part of the alpha release gate, so release/TestFlight builds must also keep `BLUEPRINT_ENABLE_REMOTE_NOTIFICATIONS=YES`.

## Automated verification
- Run `./scripts/alpha_readiness.sh`.
- `alpha_readiness.sh` now fails closed unless both cloud packages are tested:
  - `cloud/extract-frames`
  - `cloud/referral-earnings`
- Use `./scripts/archive_external_alpha.sh` with an untracked release xcconfig copied from `ConfigTemplates/BlueprintCapture.release.xcconfig.example` before any external archive/export.
- `alpha_readiness.sh` preboots a simulator, runs the cloud tests, runs the focused iOS unit/UI suite, builds the release app bundle, and fails if the bundle contains `Secrets*.plist`, provider keys, mock-job fallback, internal test space, missing remote notifications, missing backend URLs, or missing support/legal config.
- Use `./scripts/android_alpha_readiness.sh` for Android internal release validation. It validates release-safe config, runs `testDebugUnitTest`, and builds `assembleRelease`.

## Core-path manual checklist
- Launch a release-like build and confirm the app opens without a secret/config crash.
- Confirm onboarding, auth entry, and scan home render without empty or broken states or fake/demo cards.
- Confirm guest launch establishes a Firebase-authenticated user before any real upload attempt.
- Confirm the home feed is loading live jobs and/or live nearby proxy results rather than mock jobs or the internal current-location test space.
- Confirm at least one approved job can open, start capture, and reach the upload overlay.
- Confirm a completed upload also writes `capture_submissions/{captureId}` instead of stopping at raw storage only.
- Confirm APNs registration succeeds, FCM token registration succeeds, and the creator device/preferences backend calls return actionable results.
- Confirm wallet loads and payout setup either works through the backend or shows the alpha-safe unavailable banner.
- Confirm capture upload/export flows fall back safely when AI intake is disabled.
- Confirm no live feature silently depends on bundled third-party API keys.

## Observability hooks
- Firebase Analytics events:
  - `blueprint_ops_event`
  - `blueprint_ops_error`
- Firestore `sessionEvents` now carries explicit operational events for:
  - upload file failures
  - submission registration success/failure
  - APNs/device sync failures
  - notification preference sync failures
- Android mirrors those hooks through `blueprint_ops_event` for:
  - capture upload completion/failure
  - submission registration
  - push token fetch and device sync
  - notification preference refresh/sync
- Cloud Logging for `cloud/extract-frames` now emits explicit handoff markers:
  - `Saved pipeline handoff payload`
  - `Published pipeline handoff payload`
  - `Pipeline handoff publish failed`

Launch-week monitor minimum:

- Watch Firebase Analytics for `blueprint_ops_event` / `blueprint_ops_error` spikes by operation.
- Watch Firestore `sessionEvents` for `eventType == "error"` or `eventType == "operational"` with failed statuses.
- Watch Cloud Logging for `Pipeline handoff publish failed`.
- Keep simulator evidence separate from device-required smoke before widening the rollout from 10 -> 25 -> 100 users.
