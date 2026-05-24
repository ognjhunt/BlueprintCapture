# Android XR On-Device QA Checklist

Status: operator checklist for physical Android XR hardware. Use one copy per device, per app build, per capture target.

This checklist verifies the current projected Android XR glasses path in the Android app. It is intentionally practical: every checked item should leave a screenshot, log line, raw file, or explicit blocker.

## Run Header

| Field | Value |
| --- | --- |
| QA run id |  |
| Operator |  |
| Date/time and timezone |  |
| App build |  |
| Branch/SHA |  |
| Host phone model/build |  |
| Android XR device model/build |  |
| Device type | audio glasses / display glasses / emulator / other |
| Capture target |  |
| `scene_id` |  |
| `capture_id` |  |
| Result | pass / blocked / fail |

## 1. Repo And Build Preflight

- [ ] Record `git status --short --branch --untracked-files=all`.
- [ ] Record current branch and commit SHA.
- [ ] Confirm dirty files are understood and not unrelated regressions.
- [ ] Run Android unit tests or record why they were skipped.
- [ ] Build or install the tested APK.
- [ ] Confirm the app build does not enable mock jobs or mock glasses unless this is a mock-only run.
- [ ] Confirm the tested build is not presented as external-alpha ready unless `./scripts/android_alpha_readiness.sh --validate-config-only` passes with real config.

Recommended commands:

```bash
git status --short --branch --untracked-files=all
```

```bash
cd /Users/nijelhunt_1/workspace/BlueprintCapture/android
ANDROID_HOME=/Users/nijelhunt_1/Library/Android/sdk ./gradlew testDebugUnitTest
```

```bash
cd /Users/nijelhunt_1/workspace/BlueprintCapture/android
ANDROID_HOME=/Users/nijelhunt_1/Library/Android/sdk ./gradlew assembleDebug
```

## 2. Device Pairing And Availability

- [ ] Host phone is signed into the intended test account.
- [ ] Android XR device is charged above 50 percent or connected to power.
- [ ] Host phone and glasses are on the expected network state.
- [ ] Pairing completes through the supported Android XR pairing flow.
- [ ] Reconnecting after closing/reopening the app works.
- [ ] App Android XR panel changes from waiting state to connected state.
- [ ] Panel text does not claim world tracking, payout, provider, launch, or hosted-review readiness.

Evidence:

- [ ] Device Manager or pairing screenshot.
- [ ] Host app Android XR panel screenshot.
- [ ] Logcat excerpt for projected connection state.

## 3. Projected Activity Launch

- [ ] Select a real capture target when testing upload/bundle truth.
- [ ] Select readiness mode only when no capture target is available.
- [ ] Tap the Android XR launch action.
- [ ] Projected activity opens on the connected glasses path.
- [ ] Failure to launch produces a visible, specific error.
- [ ] Closing the projected activity resets runtime capabilities in the phone UI.

Evidence:

- [ ] Pre-launch phone screenshot.
- [ ] Projected activity screenshot or screen recording when display is available.
- [ ] Logcat excerpt for launch success or failure.

## 4. Permissions

- [ ] Camera permission is requested for the projected device path.
- [ ] Microphone permission is requested for the projected device path.
- [ ] Granting both permissions initializes the projected experience.
- [ ] Denying either permission leaves a retry path.
- [ ] The run records where the permission prompt appeared.

Evidence:

- [ ] Permission prompt screenshot or video.
- [ ] Logcat excerpt for permission result.
- [ ] Note if permission was inherited from a previous run.

## 5. Display And Audio Modes

For display glasses:

- [ ] Visual UI is readable on the glasses display.
- [ ] UI remains legible on additive/transparent display backgrounds.
- [ ] `XR mode` copy names display-glasses mode and does not overclaim tracking.
- [ ] Turning visuals off or letting the display time out does not leave stale display-ready state.
- [ ] Turning visuals back on recovers without relaunching the app, or the exact blocker is recorded.

For audio-only glasses or visuals-off state:

- [ ] No misleading visual-only instruction is required to proceed.
- [ ] Voice guidance starts.
- [ ] Start/stop capture can be reached by the available control path.
- [ ] The app does not claim a display UI exists.

Evidence:

- [ ] Display screenshot/recording, if available.
- [ ] Audio-only behavior note.
- [ ] Logcat excerpt for display capability and presentation mode changes.

## 6. Camera And Recording Smoke

- [ ] Projected camera prepares successfully.
- [ ] Start capture button is enabled only after camera readiness.
- [ ] Tapping start begins recording and displays/announces recording state.
- [ ] Elapsed recording status advances.
- [ ] Record at least 30 seconds for smoke.
- [ ] Record at least 3 minutes for thermal sanity when the hardware allows it.
- [ ] Stop capture finalizes without `VideoRecordEvent` error.
- [ ] Repeating start -> stop twice in one app session does not break camera binding.

Evidence:

- [ ] Recording start/stop screen recording or log.
- [ ] Final `walkthrough.mp4` size and metadata.
- [ ] Duration, width, height, and FPS.
- [ ] Battery and thermal notes before/after the 3-minute run.

## 7. Voice And Guidance Truth

- [ ] Voice session starts on activity start or via restart voice.
- [ ] If Gemini connectivity succeeds, the app labels it only as Gemini text/model connectivity unless full Live audio is implemented and proven.
- [ ] If Gemini is unavailable, the app clearly falls back to on-device ASR/TTS.
- [ ] Partial transcript appears only when speech is actually detected.
- [ ] Recognition errors do not stop the capture flow unless the user cannot recover.
- [ ] Voice prompts do not claim geometry, readiness, payout, or buyer access.

Evidence:

- [ ] Voice state screenshot or logcat.
- [ ] Spoken prompt notes.
- [ ] Any Gemini/Firebase error text.

## 8. Raw Bundle Verification

After stopping capture, verify local raw bundle contents.

- [ ] App reports upload queued or a specific finalization/upload error.
- [ ] `files/capture_bundles/scenes/{scene_id}/captures/{capture_id}/raw/` exists in app-private storage.
- [ ] `walkthrough.mp4` exists and is non-empty.
- [ ] `manifest.json` exists.
- [ ] `capture_context.json` exists.
- [ ] `recording_session.json` exists.
- [ ] `video_track.json` exists.
- [ ] `provenance.json` exists.
- [ ] `rights_consent.json` exists.
- [ ] `hashes.json` exists.
- [ ] `capture_upload_complete.json` exists.
- [ ] `hashes.json` includes every final raw file except itself.

Debug commands:

```bash
adb shell run-as Public.BlueprintCapture.Android find files/capture_bundles -type f
```

```bash
adb exec-out run-as Public.BlueprintCapture.Android tar -C files/capture_bundles -cf - . > /tmp/android-xr-capture-bundles.tar
```

Expected current video-only values:

- [ ] `manifest.capture_source == "glasses"`
- [ ] `manifest.capture_tier_hint == "tier2_glasses"`
- [ ] `manifest.capture_profile_id == "android_xr_glasses"`
- [ ] `manifest.capture_modality == "android_xr_video_only"`
- [ ] `manifest.capture_capabilities.camera_pose == false`
- [ ] `manifest.capture_capabilities.camera_intrinsics == false`
- [ ] `manifest.capture_capabilities.depth == false`
- [ ] `manifest.capture_capabilities.motion == false`
- [ ] `manifest.capture_capabilities.geometry_expected_downstream == false`
- [ ] `manifest.capture_evidence.pose_authority == "not_available"`
- [ ] `manifest.capture_evidence.depth_authority == "not_available"`
- [ ] `manifest.capture_evidence.motion_authority == "not_available"`
- [ ] `recording_session.world_frame_definition == "unavailable_no_public_world_tracking"`
- [ ] `recording_session.gravity_aligned == false`

## 9. Upload Queue And Retry Behavior

- [ ] Upload queue id is visible in app state/logs.
- [ ] Offline mode leaves a retryable queued item instead of losing the bundle.
- [ ] Network restoration resumes upload or produces a specific retryable error.
- [ ] Remote raw prefix is recorded when upload succeeds.
- [ ] `capture_upload_complete.json` lands after all other raw files when remote upload succeeds.

Evidence:

- [ ] Queue id.
- [ ] Remote raw prefix.
- [ ] Upload log excerpt.
- [ ] Offline/retry observation if tested.

## 10. Bridge And Pipeline Follow-Through

Mark this section `blocked_not_run` for hardware-only QA. Do not mark Android XR downstream-ready unless it passes for the same capture id.

- [ ] Bridge reads the same remote raw prefix.
- [ ] Bridge emits `capture_descriptor.json`.
- [ ] Bridge emits `qa_report.json`.
- [ ] Bridge emits `pipeline_handoff.json`.
- [ ] Handoff points to the same `scene_id` and `capture_id`.
- [ ] Pipeline consumes the handoff.
- [ ] Pipeline output path or blocker is recorded.
- [ ] WebApp has real upstream ids before hosted-review, buyer, payout, or launch claims.

Evidence:

- [ ] Bridge output paths.
- [ ] Pipeline output paths.
- [ ] WebApp request/job/hosted-review links.
- [ ] Blocker codes.

## 11. Regression Sweep

- [ ] Android phone capture still launches after the Android XR run.
- [ ] Meta DAT panel still reports real private SDK or disabled-stub truth honestly.
- [ ] Scan target selection still passes target metadata into glasses launch.
- [ ] Open capture still requires rights acknowledgment before capture.
- [ ] Wallet/payout copy remains informational unless provider readiness is proven.
- [ ] No user-facing copy says Android XR is public-ready.

## 12. Negative Claim Checklist

Each item must remain unchecked unless independently proven by same-capture evidence.

- [ ] Android XR external alpha readiness proven.
- [ ] Android XR public launch readiness proven.
- [ ] Native glasses pose proven.
- [ ] Native glasses IMU proven.
- [ ] Android XR depth proven.
- [ ] Calibrated glasses-to-phone extrinsics proven.
- [ ] Hosted review proven.
- [ ] Buyer access proven.
- [ ] Payout eligibility proven.
- [ ] Pipeline package quality proven.

If any item is checked, attach the exact proof path and reviewer.

## Closeout

Final status:

- [ ] `pass_internal_video_first`
- [ ] `blocked_hardware`
- [ ] `blocked_permissions`
- [ ] `blocked_camera`
- [ ] `blocked_bundle`
- [ ] `blocked_upload`
- [ ] `blocked_bridge_pipeline`
- [ ] `fail_regression`

Closeout notes:

```text
Summary:

Evidence paths:

Blockers:

Next input needed:
```

## Related Docs

- [Hardware Validation Packet](ANDROID_XR_HARDWARE_VALIDATION_PACKET_2026-05-23.md)
- [Capture-to-Pipeline Android XR Proof Map](CAPTURE_TO_PIPELINE_ANDROID_XR_PROOF_MAP.md)
- [Android XR AI-Glasses Readiness](ANDROID_XR_AI_GLASSES_READINESS.md)
- [Capture Raw Contract V3](CAPTURE_RAW_CONTRACT_V3.md)
