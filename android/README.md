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

## Firebase

- Registered package name: `Public.BlueprintCapture.Android`
- Firebase project: `blueprint-8c1ca`
- `google-services.json` is expected at `android/app/google-services.json`

## Distribution

Use Firebase App Distribution for tester installs. Gmail blocks direct APK attachments.
