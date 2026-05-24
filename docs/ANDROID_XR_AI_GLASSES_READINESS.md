# Android XR AI-Glasses Readiness

This repo has an Android XR projected-glasses path alongside the existing Android phone capture flow and Meta DAT flow. The path is truth-scoped: it can be video-first, projected-camera/mic capable, and raw-bundle compatible, but it must not claim world tracking, geospatial authority, ARCore pose/depth, payout readiness, public launch readiness, or hardware launch readiness without direct proof.

Note on current terminology: Android XR Developer Preview 4 documentation now uses "audio glasses" and "display glasses" for the projected glasses form factors. This repo still has some Android XR AI-glasses naming in historical files and class names, but new validation should use the audio/display distinction unless a code symbol requires the older wording.

## Official Source Truth

- [Android XR SDK Developer Preview 4](https://developer.android.com/blog/posts/updates-to-the-android-xr-sdk-introducing-developer-preview-4) was published May 19, 2026. It introduced projected device availability APIs, `ProjectedTestRule`, updated naming for audio/display glasses, and early geospatial preview language for wired XR glasses.
- [Google's I/O 2026 eyewear update](https://blog.google/products-and-platforms/platforms/android/android-xr-io-2026/) says audio glasses launch first later in fall 2026 and display glasses are a separate form factor.
- [Android XR Catalyst](https://developer.android.com/develop/xr/catalyst) opened May 19, 2026 and applications close June 30, 2026.
- [XR Runtime](https://developer.android.com/jetpack/androidx/releases/xr-runtime) and [ARCore for Jetpack XR](https://developer.android.com/jetpack/androidx/releases/xr-arcore) are at `1.0.0-alpha14`.
- [XR Projected](https://developer.android.com/jetpack/androidx/releases/xr-projected) is at `1.0.0-alpha08` and exposes `projected-testing`, including `ProjectedTestRule`; this repo cannot consume it yet because the installed local SDK/toolchain is still `compileSdk 36` / AGP 8.9.1.

Related validation artifacts:

- [Android XR Hardware Validation Packet](ANDROID_XR_HARDWARE_VALIDATION_PACKET_2026-05-23.md)
- [Android XR On-Device QA Checklist](ANDROID_XR_ON_DEVICE_QA_CHECKLIST_2026-05-23.md)
- [Capture-to-Pipeline Android XR Proof Map](CAPTURE_TO_PIPELINE_ANDROID_XR_PROOF_MAP.md)
- [Android XR Release Proof Example](ANDROID_XR_RELEASE_PROOF.example.json)

## State Split

### Compile-Verified

The Android module pins the DP4-safe artifacts that fit the current repo toolchain:

- `androidx.xr.runtime:runtime:1.0.0-alpha14`
- `androidx.xr.arcore:arcore:1.0.0-alpha14`
- `androidx.xr.projected:projected:1.0.0-alpha06`

`xr.projected` / `projected-testing` `1.0.0-alpha08` and Glimmer `1.0.0-alpha13` stay blocked until the repo moves to the Android 17 platform and AGP 9.2.0. The installed local SDK currently has `android-36` and `android-36.1`, so this pass does not force `compileSdk 37`.

The app-level Glimmer dependency is intentionally omitted for now. Display-glasses UI uses local Compose tokens in `GlassesProjectedActivity.kt` until the DP4 Glimmer artifact can be compiled safely.

### Emulator/Test-Verified

Unit coverage now checks:

- Android XR UX separates audio-only glasses from display glasses.
- Projected camera/mic capability bits do not become world-tracking or geospatial authority.
- Android XR raw bundle output drops accidental ARCore sidecars, keeps pose/depth/geospatial unavailable, and keeps payout false.
- DP4 compatibility logic reports runtime/arcore alpha14 as safe while `ProjectedTestRule` remains blocked on the current toolchain.

`ProjectedTestRule` is represented as a blocked readiness state, not an active test dependency. Add a real `ProjectedTestRule` test only after `compileSdk 37`, AGP 9.2.0, and the Android 17 SDK platform are installed and compile-verified in this repo.

### Release-Config-Blocked

`./scripts/android_alpha_readiness.sh --validate-config-only` must remain fail-closed if release config is missing. Do not satisfy it with placeholders or tracked secrets. The expected real inputs still include:

- `BLUEPRINT_BACKEND_BASE_URL`
- `BLUEPRINT_DEMAND_BACKEND_BASE_URL`
- public policy/help URLs and support email
- `android/app/google-services.json`
- `BLUEPRINT_ANDROID_XR_RELEASE_TRACK=mobile` unless a dedicated XR APK is intentionally created

Passing config validation still does not mean Android XR is public-ready. Full release validation also requires `BLUEPRINT_ANDROID_XR_RELEASE_PROOF_PATH` with passing device smoke, App Distribution smoke, and quality-review evidence.

### Hardware-Blocked

Hardware validation is a checklist, not a completed state. Before claiming Android XR runtime readiness, test on the actual target class:

- audio glasses when fall 2026 hardware access exists
- display glasses when display prototypes are available
- XREAL Project Aura / wired XR glasses if Blueprint pursues that form factor

Each hardware pass must prove projected camera permission UX, projected mic permission UX, recording start/stop, upload queueing, display on/off behavior, and generated bundle contents. Do not mark world tracking, ARCore pose/depth, geospatial authority, launch readiness, or payout readiness complete unless the raw bundle contains the corresponding validated evidence.

## Release-Readiness Gates

Android XR release checks now run through `scripts/android_alpha_readiness.sh` without requiring edits to `android/gradle.properties`, `android/local.properties`, Firebase config, or other secret/release config files.

Config-only validation checks that the current Jetpack XR app path declares `android.software.xr.api.spatial` in `android/app/src/main/AndroidManifest.xml`. The default track is the existing mobile track, so the manifest keeps `android:required="false"` and does not filter out non-XR installs. If Blueprint later publishes a separate APK on the dedicated Android XR track, run with `BLUEPRINT_ANDROID_XR_RELEASE_TRACK=dedicated` and change the manifest to `android:required="true"` in the same release-track change.

Full release validation now also requires `BLUEPRINT_ANDROID_XR_RELEASE_PROOF_PATH` to point at a local, non-secret JSON proof file. That proof must record passing device smoke, App Distribution smoke, and review against current Android XR quality guidance. The validator also keeps `public_distribution_claims.audio_display_glasses_ready=false`, because Google currently documents Play distribution for immersive XR headset and wired-glasses experiences while augmented audio/display-glasses distribution is still future-facing.

## What Changed In This Pass

- Upgraded Android XR Runtime and ARCore for Jetpack XR to DP4 alpha14.
- Kept `xr.projected` at alpha06 because alpha08 / `ProjectedTestRule` is blocked by the current compile/toolchain floor.
- Removed the stale Glimmer implementation dependency until the Android 17 / AGP 9.2 toolchain is available.
- Added explicit DP4 compatibility tests for safe artifacts and blocked `ProjectedTestRule` readiness.
- Hardened Android XR UX copy so display/audio capability states never imply world tracking or geospatial authority.
- Hardened Android XR bundle output so accidental ARCore sidecars do not create false pose/depth/geospatial evidence or payout eligibility.

## Current Output Contract For Android XR

Android XR projected captures remain downstream-compatible with the existing raw-contract expectations:

- manifest `capture_source` remains `glasses`
- manifest `capture_tier_hint` remains `tier2_glasses`

Android XR-specific identity is preserved in the more detailed fields:

- `capture_profile_id = "android_xr_glasses"`
- `capture_modality = "android_xr_video_only"`

Current no-sidecar Android XR output is intentionally conservative:

- no pose evidence is claimed
- no geometry source is claimed
- no motion provenance is claimed unless motion samples are actually present
- no geospatial evidence is claimed
- no contributor payout eligibility is claimed
- world frame remains `unavailable_no_public_world_tracking`

This keeps Android XR honest until public projected ARCore / device-pose evidence is available in this repo.

## Gemini Live Status

Gemini Live is not integrated in production form in this app.

What exists today:

- `GeminiLiveConnector` seam
- `UnavailableGeminiLiveConnector`
- `VoiceSessionOrchestrator`
- `AndroidXrVoiceGuidancePolicy.default()`, which keeps Gemini Live disabled by default
- on-device ASR/TTS fallback via `SpeechRecognizer` and `TextToSpeech`

What does not exist yet:

- Firebase AI Logic `LiveModel` usage
- a Gemini Live native-audio model configured with audio response modality
- app/backend wiring for a real Gemini Live session
- authenticated network connector for live conversational turn handling
- production-tested voice UX on Android XR hardware

The previous text-generation probe has been removed. A standard Gemini `GenerativeModel` call is
not a Gemini Live session. The current build is honest about this and uses on-device speech only.
Current Android/Firebase guidance for real Gemini Live requires a `LiveModel`, a Live-capable
native-audio model such as `gemini-2.5-flash-native-audio-preview-12-2025`, audio response
modality, and a persistent bidirectional session.

## Remaining Blockers And Limits

- Physical Android XR device testing is still required.
- Projected camera capture, projected permissions UX, and projected display behavior have not been hardware-validated in this session.
- Android XR projected ARCore remains unverified and gated.
- The shared bundle builder can represent XR pose/depth sidecars if they ever exist, but this repo does not currently produce validated Android XR projected ARCore evidence comparable to the phone ARCore path.
- Until public projected APIs and hardware validation exist, Android XR remains video-first, not world-tracking-authoritative.
- Android XR Catalyst applications close June 30, 2026; applying would be a business/hardware-access decision, not proof that Blueprint Android XR is launch-ready.
- Real Meta DAT verification on this machine still requires private credentials.
- To re-enable the real Meta path for Android builds, provide valid GitHub Packages credentials and run with `-PMWDAT_ENABLE_PRIVATE_SDK=true`.

## Physical Android XR Validation Checklist

Use this on actual Android XR hardware before claiming runtime readiness:

1. Connect the glasses and confirm the app reports `Android XR glasses detected`.
2. Launch the projected activity and verify the prompt flow for `CAMERA` and `RECORD_AUDIO`.
3. Confirm the projected screen reflects display on/off changes without stale capability state after closing the activity.
4. Start a short capture and verify the UI reports projected camera readiness, active recording, and non-Gemini on-device voice guidance.
5. Stop the capture and confirm the app queues an upload instead of failing during bundle finalization.
6. Inspect the generated bundle under app-private storage and verify `manifest.json` keeps `capture_source = "glasses"` and `capture_tier_hint = "tier2_glasses"`.
7. Verify `manifest.json` sets `capture_profile_id = "android_xr_glasses"` and `capture_modality = "android_xr_video_only"`.
8. Verify `manifest.json` leaves `motion_provenance`, `geometry_source`, pose/depth/geospatial counts, and payout eligibility unset or false when no validated XR sidecars exist.
9. Verify `raw/recording_session.json` keeps `world_frame_definition = "unavailable_no_public_world_tracking"`.

If any step fails, capture the exact device model, Android XR build, failure step, and whether the issue reproduces after relaunching the projected activity.

## Practical Test Commands

### Required Verification Commands

```bash
cd /Users/nijelhunt_1/workspace/BlueprintCapture/android
ANDROID_HOME=/Users/nijelhunt_1/Library/Android/sdk ./gradlew :app:compileDebugKotlin
ANDROID_HOME=/Users/nijelhunt_1/Library/Android/sdk ./gradlew :app:testDebugUnitTest
cd /Users/nijelhunt_1/workspace/BlueprintCapture
./scripts/android_alpha_readiness.sh --validate-config-only
```

### Real Meta DAT Verification Command

```bash
cd /Users/nijelhunt_1/workspace/BlueprintCapture/android
ANDROID_HOME=/Users/nijelhunt_1/Library/Android/sdk ./gradlew :app:compileDebugKotlin -PMWDAT_ENABLE_PRIVATE_SDK=true
```

Requirements:

- valid `gpr.user`
- valid `gpr.token`
- access to `https://maven.pkg.github.com/facebook/meta-wearables-dat-android`

## Recommended Next Work

- Validate the projected activity on physical Android XR hardware.
- Decide and implement a real Firebase AI Logic `LiveModel` Gemini Live connector only after app/backend requirements, API-key handling, and Android XR hardware validation are available.
- Revisit Android XR pose/geospatial claims only when a public, testable projected evidence path exists.
