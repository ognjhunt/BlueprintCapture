# Android XR AI-Glasses Readiness

This repo now has a compiler-verified Android XR projected-glasses path alongside the existing Android phone capture flow and the existing Meta DAT flow.

## Verified on March 25, 2026

- Android compile passed:
  - `cd /Users/nijelhunt_1/workspace/BlueprintCapture/android`
  - `./gradlew :app:compileDebugKotlin`

- Android unit tests passed:
  - `cd /Users/nijelhunt_1/workspace/BlueprintCapture/android`
  - `./gradlew :app:testDebugUnitTest`

- The Android XR code was corrected against the currently resolved AndroidX public artifacts:
  - `androidx.xr.projected:projected:1.0.0-alpha05`
  - `androidx.xr.runtime:runtime:1.0.0-alpha12`

- Shared capture-pipeline verification now includes an Android XR-specific bundle contract test:
  - `android/app/src/test/kotlin/app/blueprint/capture/data/capture/AndroidCaptureBundleBuilderTest.kt`

## What changed in this pass

- Fixed Android XR API drift:
  - projected permission imports moved under `androidx.xr.projected.permissions`
  - experimental annotation import moved under `androidx.xr.projected.experimental`
  - projected capability and presentation-mode constants now use the nested alpha API symbols
  - `ProjectedContext.isProjectedDeviceConnected(...)` now passes the required coroutine context

- Fixed compile issues outside the XR code that were hidden by the earlier Meta dependency failure:
  - `GlassesConnectionSheet.kt` Compose import drift
  - `GlassesViewModel.kt` invalid lambda `return@launch`

- Hardened runtime behavior:
  - the Android XR projected activity resets runtime capability state on teardown
  - voice fallback messaging now explicitly says when on-device speech is in use
  - Android XR UI capability messaging stays video-first and no longer advertises pose/geospatial readiness before hardware validation

- Preserved Meta DAT support without forcing private-package access for local XR verification:
  - the app module now enables the private Meta SDK only when `-PMWDAT_ENABLE_PRIVATE_SDK=true` is supplied
  - when that flag is not supplied, the Android module compiles against local no-op Meta stubs under `android/app/src/metaStub/kotlin`
  - the Meta UI now reports that private DAT verification is disabled in this build instead of pretending the SDK is available

## Current output contract for Android XR

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
- world frame remains `unavailable_no_public_world_tracking`

This keeps Android XR honest until public projected ARCore / device-pose evidence is available in this repo.

## Gemini Live status

Gemini Live is not integrated in production form in this app.

What exists today:

- `GeminiLiveConnector` seam
- `UnavailableGeminiLiveConnector`
- `VoiceSessionOrchestrator`
- on-device ASR/TTS fallback via `SpeechRecognizer` and `TextToSpeech`

What does not exist yet:

- app/backend wiring for a real Gemini Live session
- authenticated network connector for live conversational turn handling
- production-tested voice UX on Android XR hardware

The current build is honest about this and falls back to on-device speech.

## Remaining blockers and limits

- Physical Android XR device testing is still required.
  - The projected activity compiles and the code path is in place, but projected camera capture, projected permissions UX, and projected display behavior have not been hardware-validated in this session.

- Android XR projected ARCore remains unverified and effectively gated.
  - The shared bundle builder can represent XR pose/depth sidecars if they ever exist.
  - This repo does not currently produce validated Android XR projected ARCore evidence comparable to the phone ARCore path.
  - Until public projected APIs and hardware validation exist, Android XR should be treated as video-first, not world-tracking-authoritative.

- Real Meta DAT verification on this machine still requires private credentials.
  - To re-enable the real Meta path for Android builds, provide valid GitHub Packages credentials and run with `-PMWDAT_ENABLE_PRIVATE_SDK=true`.
  - Repository credentials still come from `android/local.properties` (`gpr.user`, `gpr.token`) or Gradle properties.

## Physical Android XR validation checklist

Use this on actual Android XR hardware before claiming runtime readiness:

1. Connect the glasses and confirm the app reports `Android XR glasses detected`.
2. Launch the projected activity and verify the prompt flow for `CAMERA` and `RECORD_AUDIO`.
3. Confirm the projected screen reflects display on/off changes without stale capability state after closing the activity.
4. Start a short capture and verify the UI reports projected camera readiness, active recording, and non-Gemini on-device voice fallback messaging.
5. Stop the capture and confirm the app queues an upload instead of failing during bundle finalization.
6. Inspect the generated bundle under app-private storage and verify:
   - `manifest.json` keeps `capture_source = "glasses"` and `capture_tier_hint = "tier2_glasses"`
   - `manifest.json` sets `capture_profile_id = "android_xr_glasses"` and `capture_modality = "android_xr_video_only"`
   - `manifest.json` leaves `motion_provenance` and `geometry_source` unset when no validated XR sidecars exist
   - `raw/recording_session.json` keeps `world_frame_definition = "unavailable_no_public_world_tracking"`

If any step fails, capture the exact device model, Android XR build, failure step, and whether the issue reproduces after relaunching the projected activity.

## Practical test commands

### Verified commands

```bash
cd /Users/nijelhunt_1/workspace/BlueprintCapture/android
./gradlew :app:compileDebugKotlin
./gradlew :app:testDebugUnitTest
```

### Real Meta DAT verification command

```bash
cd /Users/nijelhunt_1/workspace/BlueprintCapture/android
./gradlew :app:compileDebugKotlin -PMWDAT_ENABLE_PRIVATE_SDK=true
```

Requirements:

- valid `gpr.user`
- valid `gpr.token`
- access to `https://maven.pkg.github.com/facebook/meta-wearables-dat-android`

## Recommended next work

- Validate the projected activity on physical Android XR hardware.
- Decide and implement a real Gemini Live connector only after app/backend requirements are available.
- Revisit Android XR pose/geospatial claims only when a public, testable projected evidence path exists.
