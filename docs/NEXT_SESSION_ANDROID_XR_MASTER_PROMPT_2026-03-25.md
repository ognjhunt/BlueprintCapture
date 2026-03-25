# Next Session Master Prompt: Finish Android XR AI Glasses Integration

You are continuing Android XR AI-glasses work inside the `BlueprintCapture` repo.

## Mission

Finish and verify the Android XR AI-glasses integration that was partially implemented on **March 25, 2026**.

The goal is to turn the current Android XR readiness pass into a verified, production-credible integration for this repo, without breaking the existing Meta DAT glasses path or the current Android phone capture flow.

Do not restart from scratch. Build on the existing implementation already pushed to `main`.

## Current Git Context

- Repo: `https://github.com/ognjhunt/BlueprintCapture`
- Branch pushed: `main`
- Android XR commit already pushed to `main`: `55955998`
- Earlier local commit hash that contained the same work before replay: `e94abae3`

Important:
- The repo may still be locally dirty from unrelated user/build changes.
- Do not revert unrelated user changes.
- Focus only on Android XR-related files unless verification forces a narrower compatibility fix.

## What Was Already Implemented

The following Android XR structure now exists in the repo:

- Projected Android XR activity:
  - `android/app/src/main/kotlin/app/blueprint/capture/GlassesProjectedActivity.kt`

- Phone-side Android XR launch / orchestration:
  - `android/app/src/main/kotlin/app/blueprint/capture/ui/screens/AndroidXrViewModel.kt`
  - `android/app/src/main/kotlin/app/blueprint/capture/ui/screens/GlassesConnectionSheet.kt`
  - `android/app/src/main/kotlin/app/blueprint/capture/ui/screens/OnboardingGlassesScreen.kt`

- Android XR platform/capability abstractions:
  - `android/app/src/main/kotlin/app/blueprint/capture/data/glasses/GlassesPlatform.kt`
  - `android/app/src/main/kotlin/app/blueprint/capture/data/glasses/AndroidXrCapabilityRepository.kt`

- Android XR projected capture helpers:
  - `android/app/src/main/kotlin/app/blueprint/capture/data/glasses/androidxr/AndroidXrProjectedCaptureManager.kt`
  - `android/app/src/main/kotlin/app/blueprint/capture/data/glasses/androidxr/AndroidXrProjectedLaunch.kt`

- Voice/session scaffolding:
  - `android/app/src/main/kotlin/app/blueprint/capture/data/glasses/voice/VoiceSessionOrchestrator.kt`
  - `android/app/src/main/kotlin/app/blueprint/capture/data/glasses/voice/AndroidVoiceAdapters.kt`

- Shared capture pipeline updates:
  - `android/app/src/main/kotlin/app/blueprint/capture/data/capture/CaptureContracts.kt`
  - `android/app/src/main/kotlin/app/blueprint/capture/data/capture/AndroidCaptureBundleBuilder.kt`
  - `android/app/src/main/kotlin/app/blueprint/capture/data/capture/CaptureUploadRepository.kt`

- Android toolchain/deps updates:
  - `android/app/build.gradle.kts`
  - `android/gradle/libs.versions.toml`
  - `android/gradle/wrapper/gradle-wrapper.properties`
  - `android/app/src/main/AndroidManifest.xml`

- Added tests/docs:
  - `android/app/src/test/kotlin/app/blueprint/capture/data/glasses/GlassesPlatformRegistryTest.kt`
  - `android/app/src/test/kotlin/app/blueprint/capture/data/glasses/voice/VoiceSessionOrchestratorTest.kt`
  - `android/app/src/test/kotlin/app/blueprint/capture/data/capture/AndroidCaptureSourceSerializationTest.kt`
  - `docs/ANDROID_XR_AI_GLASSES_READINESS.md`

## What Is NOT Finished

This integration is not complete. The previous session explicitly called it a strong first pass only.

### 1. Compile/build verification is still missing

The previous session could not complete:

```bash
./gradlew :app:compileDebugKotlin
```

Reason:
- Existing private Meta dependencies failed to resolve:
  - `com.meta.wearable:mwdat-core:0.5.0`
  - `com.meta.wearable:mwdat-camera:0.5.0`
- Error was `401 Unauthorized` from GitHub Packages.

You must treat the Android XR code as **not compiler-verified** until you solve or work around this.

### 2. Gemini Live is only scaffolded, not truly integrated

Current state:
- The code uses `UnavailableGeminiLiveConnector`.
- Voice UX currently falls back to on-device ASR/TTS.

You need to decide and implement one of:
- A real Gemini Live adapter integrated into this app.
- Or, if that is blocked by missing product/backend context, tighten the fallback path and clearly wall off the Gemini seam without pretending it is complete.

### 3. Android XR emulator camera validation is still blocked

Per the docs, AI-glasses emulator camera capture is not available yet.

Current code includes projected camera capture plumbing, but this is not hardware-validated.

### 4. ARCore-on-glasses is not fully implemented

The previous session only modeled Android XR glasses as device-pose/geospatial capable.

There is not yet a true Android XR projected ARCore evidence path comparable to the existing Android phone ARCore path.

You need to inspect whether:
- projected/device-pose/geospatial APIs can be wired now in this repo, or
- the code should remain capability-gated and explicitly limited.

### 5. Android file conflict resolution needs review

To push the commit, the previous session replayed the Android XR commit on top of `origin/main` and resolved some drift by taking the Android XR versions of several conflicted Android files.

You must re-review these files carefully:
- `android/app/build.gradle.kts`
- `android/gradle/libs.versions.toml`
- `android/app/src/main/kotlin/app/blueprint/capture/data/capture/CaptureContracts.kt`
- `android/app/src/main/kotlin/app/blueprint/capture/data/capture/AndroidCaptureBundleBuilder.kt`
- `android/app/src/main/kotlin/app/blueprint/capture/ui/screens/GlassesConnectionSheet.kt`

Do not assume those merged states are perfect.

## Required Work In This Session

Do the following in order.

### A. Re-ground in repo state

1. Inspect current `main`.
2. Read the Android XR files listed above.
3. Read the current Android phone capture flow and Meta glasses flow to ensure nothing regressed.

Prioritize these existing files for comparison:
- `android/app/src/main/kotlin/app/blueprint/capture/ui/screens/GlassesViewModel.kt`
- `android/app/src/main/kotlin/app/blueprint/capture/data/glasses/GlassesCaptureManager.kt`
- `android/app/src/main/kotlin/app/blueprint/capture/ui/screens/CaptureSessionScreen.kt`
- `android/app/src/main/kotlin/app/blueprint/capture/data/capture/ARCoreCaptureManager.kt`

### B. Make the Android build verifiable

Your first practical goal is to get Android compilation/test feedback.

Try to run:

```bash
cd /Users/nijelhunt_1/workspace/BlueprintCapture/android
./gradlew :app:compileDebugKotlin
```

If Meta credentials are still blocked:
- Do not break the Meta path permanently.
- Find the least risky way to make the Android module compile for local verification.
- If you introduce a temporary compile workaround, keep it explicit and easy to revert.
- Prefer compatibility-safe build gating over ripping out Meta support.

Then run relevant tests:

```bash
./gradlew :app:testDebugUnitTest
```

If the full test suite is too broad, run at least the new XR-related tests and any affected capture tests.

### C. Fix code-level issues surfaced by real compilation

The prior session had no real compile signal. Expect API mismatch cleanup.

Things most likely to need correction:
- `androidx.xr.projected` API signatures
- `ProjectedPermissionsRequestParams`
- `ProjectedDisplayController` listener APIs
- `SpeechRecognizer.createOnDeviceSpeechRecognizer(...)`
- CameraX projected-context behavior
- Any Compose state/import issues in `GlassesConnectionSheet.kt`
- Any serialization/model breakage caused by `AndroidCaptureSource.AndroidXrGlasses`

### D. Review and harden the Android XR architecture

Keep the current architectural direction:
- Android-hosted projected activity
- Android XR as a second provider beside Meta DAT
- Shared bundle/upload pipeline
- Gemini Live first, fallback to ASR/TTS

But improve anything weak or misleading:
- Tighten capability modeling
- Tighten error handling
- Avoid pretending unsupported features are complete
- Make emulator limitations explicit in code/docs where appropriate

### E. Decide what to do about Gemini Live

Investigate whether this repo already has any Gemini/Gemini Live infrastructure on Android.

Search for:
- `Gemini`
- `Live API`
- `Google AI`
- `AI session`
- `speech`

Then do one of:

1. If there is enough app/backend context, implement a real connector for `GeminiLiveConnector`.
2. If there is not enough context, leave the seam but:
   - improve naming/docs/comments,
   - make the fallback UX clean,
   - make it obvious that production Gemini Live integration is still pending.

Do not fake a production integration.

### F. Review bundle/output correctness

Verify that Android XR projected captures produce sane bundle metadata and don’t regress the current manifest/output contract.

Specifically re-check:
- `capture_source`
- `capture_profile_id`
- `capture_modality`
- `captureTierHint`
- motion/geometry metadata
- any assumptions around glasses vs phone capture

### G. Update handoff docs

When finished, update:
- `docs/ANDROID_XR_AI_GLASSES_READINESS.md`

Include:
- what is now verified,
- what remains blocked,
- exact commands that passed,
- whether Gemini Live is truly integrated or still pending,
- whether physical device testing is still required.

## Non-Negotiable Constraints

- Do not remove or break the existing Meta DAT flow.
- Do not revert unrelated user changes.
- Do not commit build artifacts, DerivedData, or generated churn.
- Do not claim Android XR is finished unless:
  - it compiles,
  - tests pass or are clearly scoped,
  - the remaining limitations are explicitly documented.

## Success Criteria

A successful session ends with:

1. Android XR code compiling successfully, or a precise documented blocker that is narrower than before.
2. XR-related tests passing.
3. The Android XR path reviewed and corrected for upstream drift.
4. Gemini Live status made honest and explicit.
5. Shared capture pipeline compatibility preserved.
6. Docs updated with exact remaining gaps.

## Useful Commands

```bash
cd /Users/nijelhunt_1/workspace/BlueprintCapture
git status --short

cd /Users/nijelhunt_1/workspace/BlueprintCapture/android
./gradlew :app:compileDebugKotlin
./gradlew :app:testDebugUnitTest
```

Useful searches:

```bash
rg -n "Gemini|Live API|speech|TextToSpeech|SpeechRecognizer|androidx.xr|Projected" android/app/src/main/kotlin
rg -n "AndroidXr|GlassesProjectedActivity|AndroidXrViewModel" android/app/src/main/kotlin
```

## Final Instruction

Do not give a plan-only answer. Continue from the current codebase, make the missing fixes, run verification, and leave the repo in a cleaner and more truthful Android XR state than it is now.
