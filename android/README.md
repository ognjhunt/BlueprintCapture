# BlueprintCapture Android

Native Android app scaffold for BlueprintCapture.

## Current Scope

- Kotlin + Jetpack Compose app shell
- Firebase app registration wired through `app/google-services.json`
- onboarding, auth, scan, wallet, and profile shell screens
- Android phone capture bundle writer with canonical `android` contract output
- target-scoped Meta glasses capture that queues the same canonical bundle/upload pipeline when a real target is selected
- cloud bridge contract updated to normalize legacy `android_phone` into `android`

## Alpha Truthfulness Rules

- Production-like builds must not inject demo marketplace targets when live discovery is empty.
- Mock glasses are dev-only and must stay behind explicit mock config.
- Android payout onboarding is informational only until a real provider flow is wired; do not present fake live setup.
- The 2026-03-26 external 100-user rollout is iOS-only. Android remains internal-only until `../scripts/android_alpha_readiness.sh` passes with real release config and device/App Distribution smoke is signed off.

## Local Setup

1. Install Android SDK Command-line Tools from Android Studio SDK Manager.
2. Create `android/local.properties` with your SDK path if Android Studio has not done it yet:

```properties
sdk.dir=/Users/nijelhunt_1/Library/Android/sdk
```

3. Add developer config values to `~/.gradle/gradle.properties` or a local untracked Gradle properties file:

```properties
# Direct Firebase routing can use:
# https://us-central1-your-project.cloudfunctions.net/api
BLUEPRINT_BACKEND_BASE_URL=https://your-backend.example.com
BLUEPRINT_DEMAND_BACKEND_BASE_URL=https://your-backend.example.com
BLUEPRINT_ALLOW_MOCK_JOBS_FALLBACK=false
BLUEPRINT_ENABLE_OPEN_CAPTURE_HERE=true
BLUEPRINT_STRIPE_PUBLISHABLE_KEY=pk_test_replace_me
BLUEPRINT_MAIN_WEBSITE_URL=https://www.tryblueprint.io
BLUEPRINT_HELP_CENTER_URL=https://www.tryblueprint.io/help
BLUEPRINT_BUG_REPORT_URL=https://www.tryblueprint.io/support/bug-report
BLUEPRINT_TERMS_OF_SERVICE_URL=https://www.tryblueprint.io/terms
BLUEPRINT_PRIVACY_POLICY_URL=https://www.tryblueprint.io/privacy
BLUEPRINT_CAPTURE_POLICY_URL=https://www.tryblueprint.io/capture-policy
BLUEPRINT_ACCOUNT_DELETION_URL=https://www.tryblueprint.io/account/delete
BLUEPRINT_SUPPORT_EMAIL_ADDRESS=support@blueprint.app
# Nearby/provider requests are proxied through BLUEPRINT_DEMAND_BACKEND_BASE_URL.
# Do not ship Places or Gemini client keys in the Android app.
```

`BLUEPRINT_ENABLE_OPEN_CAPTURE_HERE=true` keeps the explicit location-based open-capture flow visible in the scan feed. This is distinct from approved marketplace jobs and requires a rights acknowledgement before capture starts.

If you do enable `BLUEPRINT_ALLOW_MOCK_JOBS_FALLBACK`, treat that build as dev-only. Alpha/release builds should keep it `false`.

4. Use the Android Studio bundled JBR or a Java 17 runtime when running Gradle from the terminal.

## Build

```bash
cd /Users/nijelhunt_1/workspace/BlueprintCapture/android
./gradlew assembleDebug
```

## Release Validation

Use the repo-local Android alpha validator before any App Distribution release candidate:

```bash
cd /Users/nijelhunt_1/workspace/BlueprintCapture
./scripts/android_alpha_readiness.sh
```

Config-only validation:

```bash
cd /Users/nijelhunt_1/workspace/BlueprintCapture
./scripts/android_alpha_readiness.sh --validate-config-only
```

The validator fails closed when release-safe values are missing:

- `BLUEPRINT_BACKEND_BASE_URL`
- `BLUEPRINT_DEMAND_BACKEND_BASE_URL`
- support/legal URLs and support email
- `BLUEPRINT_ALLOW_MOCK_JOBS_FALLBACK=false`
- `BLUEPRINT_NEARBY_DISCOVERY_PROVIDER=places_nearby`
- `BLUEPRINT_ENABLE_GEMINI_MAPS_GROUNDING_FALLBACK=false`
- `app/google-services.json` present
- `POST_NOTIFICATIONS` still declared in the manifest

## Firebase

- Registered package name: `Public.BlueprintCapture.Android`
- Firebase project: `blueprint-8c1ca`
- `google-services.json` is expected at `android/app/google-services.json`

## Distribution

Use Firebase App Distribution for internal Android installs. Gmail blocks direct APK attachments.

Android is not part of the staged external 10 -> 25 -> 100 rollout until the validator above, release artifact build, and device notification/upload smoke are all green.
