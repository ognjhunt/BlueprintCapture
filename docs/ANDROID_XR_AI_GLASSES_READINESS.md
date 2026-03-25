# Android XR AI-Glasses Readiness

This repo now includes an Android XR projected-glasses path alongside the existing Meta DAT integration.

## What was added

- `GlassesProjectedActivity`:
  - Android XR projected activity launched from the phone app.
  - Uses projected permission requests for `CAMERA` and `RECORD_AUDIO`.
  - Starts a voice session with Gemini Live as the preferred entry point and on-device ASR/TTS fallback in this build.
  - Records projected-camera video and bundles it into the existing upload pipeline.

- `AndroidXrViewModel`:
  - Tracks projected-device connection state.
  - Launches the projected activity with `ProjectedContext.createProjectedActivityOptions(...)`.
  - Finalizes projected captures into the same capture-bundle/upload flow used elsewhere in the app.

- Provider split in `GlassesConnectionSheet`:
  - `Android XR AI glasses`
  - `Meta smart glasses`

## Current limitations

- Gemini Live:
  - The code now has a `GeminiLiveConnector` seam and a voice-state orchestrator.
  - This build ships with `UnavailableGeminiLiveConnector`, so runtime behavior falls back to on-device ASR/TTS until a concrete Gemini Live adapter is wired in.

- Emulator camera capture:
  - Android XR emulator camera capture is still blocked by platform limitations.
  - The projected capture code path exists, but validation should be done on physical Android XR glasses hardware once available.

- ARCore for AI glasses:
  - Capability modeling assumes future support for device pose and geospatial.
  - This repo does not yet persist Android XR glasses ARCore sidecars the way the phone ARCore flow does.

## How to test

1. Install the latest Android Studio Canary.
2. Create a phone AVD and an AI-glasses AVD.
3. Run the app on the phone AVD.
4. Open the glasses connection sheet.
5. Choose `Android XR AI glasses`.
6. Launch the projected activity.
7. Grant projected camera and microphone permissions.
8. Verify:
   - Voice session starts.
   - On-device ASR/TTS fallback activates.
   - Projected capture starts and stops cleanly.
   - A bundle is queued into the existing upload queue.

## Files to extend next

- `android/app/src/main/kotlin/app/blueprint/capture/data/glasses/voice/VoiceSessionOrchestrator.kt`
- `android/app/src/main/kotlin/app/blueprint/capture/GlassesProjectedActivity.kt`
- `android/app/src/main/kotlin/app/blueprint/capture/ui/screens/AndroidXrViewModel.kt`
- `android/app/src/main/kotlin/app/blueprint/capture/data/capture/AndroidCaptureBundleBuilder.kt`
