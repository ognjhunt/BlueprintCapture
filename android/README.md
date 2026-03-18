# BlueprintCapture Android

Native Android app scaffold for BlueprintCapture.

## Current Scope

- Kotlin + Jetpack Compose app shell
- Firebase app registration wired through `app/google-services.json`
- onboarding, auth, scan, wallet, and profile shell screens
- Android phone capture bundle writer with canonical `android` contract output
- cloud bridge contract updated to normalize legacy `android_phone` into `android`

## Local Setup

1. Install Android SDK Command-line Tools from Android Studio SDK Manager.
2. Create `android/local.properties` with your SDK path if Android Studio has not done it yet:

```properties
sdk.dir=/Users/nijelhunt_1/Library/Android/sdk
```

3. Add developer config values to `~/.gradle/gradle.properties` or a local untracked Gradle properties file:

```properties
BLUEPRINT_BACKEND_BASE_URL=https://your-backend.example.com
BLUEPRINT_STRIPE_PUBLISHABLE_KEY=pk_test_replace_me
BLUEPRINT_GOOGLE_PLACES_API_KEY=replace_me
BLUEPRINT_GEMINI_API_KEY=replace_me
```

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
