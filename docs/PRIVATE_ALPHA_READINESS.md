# Private Alpha Readiness

## Required local config
- Set `BLUEPRINT_BACKEND_BASE_URL` via a local `.xcconfig` override or Xcode scheme environment.
- Do not restore `Secrets.plist` or `Secrets.local.plist` to the app target.
- Treat any values previously stored in `BlueprintCapture/Support/Secrets.plist` as compromised and rotate them before distribution.

## Automated verification
- Run `./scripts/alpha_readiness.sh`.
- The script preboots a simulator, runs the cloud tests, runs the focused iOS unit/UI suite, builds the app, and fails if the bundle contains `Secrets*.plist`.

## Core-path manual checklist
- Launch a release-like build and confirm the app opens without a secret/config crash.
- Confirm onboarding, auth entry, and scan home render without empty or broken states.
- Confirm at least one approved job can open, start capture, and reach the upload overlay.
- Confirm wallet loads and payout setup either works through the backend or shows the alpha-safe unavailable banner.
- Confirm capture upload/export flows fall back safely when AI intake is disabled.
- Confirm no live feature silently depends on bundled third-party API keys.
