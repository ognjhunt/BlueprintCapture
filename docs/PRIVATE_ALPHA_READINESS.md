# Private Alpha Readiness

## Required local config
- Set `BLUEPRINT_DEMAND_BACKEND_BASE_URL` to the live demand backend.
- Set `BLUEPRINT_BACKEND_BASE_URL` only when the creator notification/device routes are live and tested on hardware.
- Enable Firebase Anonymous Auth for the active project before running real capture discovery/claim/upload flows.
- Do not restore `Secrets.plist` or `Secrets.local.plist` to the app target.
- Do not ship Places or Gemini client keys in iOS or Android builds. Nearby/provider requests must go through the demand backend proxy routes.
- Treat any values previously stored in `BlueprintCapture/Support/Secrets.plist` as compromised and rotate them before distribution.

## Current launch posture
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
- Use `./scripts/archive_external_alpha.sh` with an untracked release xcconfig copied from `ConfigTemplates/BlueprintCapture.release.xcconfig.example` before any external archive/export.
- `alpha_readiness.sh` preboots a simulator, runs the cloud tests, runs the focused iOS unit/UI suite, builds the release app bundle, and fails if the bundle contains `Secrets*.plist`, provider keys, mock-job fallback, internal test space, missing remote notifications, or missing backend URLs.

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
