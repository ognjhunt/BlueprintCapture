# Command Safety Matrix

Use this matrix before running commands in `BlueprintCapture`. Default to local, read-only, or test-only commands. Do not run live upload, App Distribution, Firebase mutation, payout, provider, or external send flows unless the user explicitly asks for that run and the needed live proof/credentials are in scope.

## Safe Local Checks

| Command | Scope | Safety notes |
| --- | --- | --- |
| `git status --short --branch` | Worktree snapshot | Safe and expected before edits. |
| `git diff --stat` | Worktree snapshot | Safe. Use before touching dirty repos. |
| `git diff -- <path>` | Local diff inspection | Safe. Preserve user dirty work. |
| `rg ...` / `rg --files` | Local search | Safe. Prefer over broad slow scans. |
| `xcodebuild -list -project BlueprintCapture.xcodeproj` | iOS project introspection | Safe; no external mutation. |
| `PYTHONDONTWRITEBYTECODE=1 python3 scripts/validate_launch_readiness_tests.py` | Local Python validator tests | Safe; avoids `__pycache__`. |
| `cd cloud/extract-frames && npm test` | Local cloud bridge tests | Safe; no deploy. |
| `cd cloud/referral-earnings && npm test` | Local cloud backend tests | Safe; no deploy. |

## iOS Simulator And Build Commands

| Command | Scope | Safety notes |
| --- | --- | --- |
| `xcodebuild -project BlueprintCapture.xcodeproj -scheme BlueprintCapture -derivedDataPath build/DerivedData` | Local iOS build | Safe local build. It may be slow and may touch `build/DerivedData`. |
| `BLUEPRINT_IOS_SIMULATOR_NAME="iPhone 17 Pro" xcodebuild test -project BlueprintCapture.xcodeproj -scheme BlueprintCapture -destination "platform=iOS Simulator,name=${BLUEPRINT_IOS_SIMULATOR_NAME}" -derivedDataPath build/DerivedData` | Local simulator tests | Safe if simulator runtime exists. Use targeted tests when behavior changes are narrow. |
| `xcodebuild build -project BlueprintCapture.xcodeproj -scheme BlueprintCapture -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData-codex-sim` | Simulator build without app launch | Safe for compile verification. Useful when simulator launch is flaky. |

Do not assume simulator success proves Meta glasses, provider, push notification, App Store, TestFlight, or physical-device readiness.

## Android Gradle Commands

| Command | Scope | Safety notes |
| --- | --- | --- |
| `cd android && ./gradlew tasks` | Local Gradle introspection | Safe. |
| `cd android && ANDROID_HOME=/Users/nijelhunt_1/Library/Android/sdk ./gradlew testDebugUnitTest` | Local unit tests | Safe when SDK is installed. |
| `cd android && ANDROID_HOME=/Users/nijelhunt_1/Library/Android/sdk ./gradlew assembleDebug` | Local debug build | Safe. |
| `cd android && ./gradlew validateExternalAlphaReleaseConfig` | Local config validation | Safe; should fail closed if release-safe properties are missing. |

`android/local.properties` is ignored and should remain local. If Android tooling cannot find the SDK, prefer setting `ANDROID_HOME=/Users/nijelhunt_1/Library/Android/sdk` in the command instead of editing local config.

## Cloud Function Tests

| Command | Scope | Safety notes |
| --- | --- | --- |
| `cd cloud/extract-frames && npm test` | Local bridge tests | Safe. Does not deploy functions or mutate Firebase. |
| `cd cloud/referral-earnings && npm test` | Local backend tests | Safe. Does not deploy functions or mutate Firebase. |
| `cd cloud/extract-frames && npm run build` | Local TypeScript build if configured | Safe if source changed and package has the script. |
| `cd cloud/referral-earnings && npm run build` | Local TypeScript build if configured | Safe if source changed and package has the script. |

Do not run `firebase deploy`, production function invocations, live HTTP mutation requests, or Pub/Sub publishes as verification unless explicitly asked.

## Release-Config Validators

| Command | Expected behavior | Safety notes |
| --- | --- | --- |
| `./scripts/archive_external_alpha.sh --validate-config-only` | Fails closed if ignored release xcconfig is missing, placeholder, or incomplete | Treat missing config as `release_config_blocked`, not a code bug. Do not edit `Config/*.xcconfig` during repo orientation work. |
| `./scripts/android_alpha_readiness.sh --validate-config-only` | Fails closed if Android release properties are missing, placeholders, or unsafe | Treat missing Android release properties as `android_release_config_blocked`, not a code bug. |
| `./scripts/launch_city_readiness.sh` | Requires real launch proof path, auth token, city slug, lat/lng, release config, and cross-repo proof | Not a generic local smoke test. Run only when live launch-proof verification is requested. |
| `./scripts/alpha_readiness.sh` | Broad release-like gate | Can build and run many checks. Use when release validation is in scope, not for small doc-only edits. |

Validator failures are often the point: the repo should not proceed when release config, live proof, provider proof, App Distribution smoke, or device proof is absent.

## Restricted Or Live Commands

Do not run these for ordinary local verification:

- real capture upload flows against Firebase Storage
- Firebase App Distribution upload or release commands
- `firebase deploy` or production function deploys
- direct writes to `capture_submissions`, `users`, `referrals`, `capture_jobs`, `demand_signals`, or operating-graph collections
- live `updateCaptureStatus` HTTP calls
- provider onboarding, payout, Stripe Connect, or cashout flows
- Pub/Sub publishes to `blueprint-capture-pipeline-handoff`
- device proof flows for Meta glasses, Android XR, APNs/FCM, or physical-device capture unless explicitly requested
- edits to `Config/*.xcconfig`, `android/local.properties`, Firebase plist/json secrets, provider secrets, or release config files

When a restricted command would be needed to prove readiness, report the missing proof as a blocker and name the exact gate.
