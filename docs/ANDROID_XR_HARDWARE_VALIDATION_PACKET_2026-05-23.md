# Android XR Hardware Validation Packet

Status: runbook and evidence packet template. This is not a completed hardware proof artifact.

Use this packet for one physical Android XR projected-glasses validation run. The current repo path is a phone-hosted projected activity for Android XR audio glasses and display glasses. Passing this packet can prove internal video-first capture readiness for the tested hardware. It does not prove launch readiness, payout readiness, hosted-review readiness, native pose/depth readiness, or downstream Pipeline quality unless the same capture id also clears those downstream gates.

## Doctrine Boundary

Raw capture truth is authoritative. The client can only claim what the hardware actually recorded and what the raw bundle actually contains.

For the current no-sidecar Android XR path, the claim ceiling is:

- `capture_source = "glasses"`
- `capture_tier_hint = "tier2_glasses"`
- `capture_profile_id = "android_xr_glasses"`
- `capture_modality = "android_xr_video_only"`
- `recording_session.world_frame_definition = "unavailable_no_public_world_tracking"`
- no pose, depth, native IMU, geospatial, payout, provider, buyer-access, or hosted-review claim

Generated artifacts, local tests, emulator behavior, and queued uploads are not raw hardware proof by themselves.

## Web Research Snapshot

Last checked during this run: 2026-05-23 America/Chicago.

- Android XR SDK Developer Preview 4 introduced updated audio/display glasses terminology and continued unifying headset, wired-glasses, and intelligent-eyewear development. Source: [Android Developers Blog - Developer Preview 4](https://android-developers.googleblog.com/2026/05/android-xr-sdk-developer-preview-4-updates.html).
- Android XR device categories have different capabilities. Headsets use passthrough cameras and opaque displays; wired XR glasses use additive see-through displays; AI/audio/display glasses are lightweight projected experiences with camera, mic, touchpad, and optional display capabilities. Source: [Understand Android XR device types](https://developer.android.com/develop/xr/devices).
- The Android XR Emulator is useful for early testing, but physical hardware remains required for Blueprint capture proof. The headset/wired-glasses emulator has specific workstation requirements and does not support Unity or OpenXR apps in the Android Studio emulator path. Source: [Create virtual XR headset and XR glasses devices](https://developer.android.com/develop/xr/jetpack-xr-sdk/run/create-avds/xr-headsets-glasses).
- Audio/display glasses AVDs require a phone AVD host and pairing. Source: [Create virtual devices for audio glasses and display glasses](https://developer.android.com/develop/xr/jetpack-xr-sdk/run/create-avds/glasses).
- Emulator controls can test movement, passthrough simulation, screenshots, and screen recordings, but not actual projected camera/mic hardware behavior. Source: [Run immersive experiences on the Android XR emulator](https://developer.android.com/develop/xr/jetpack-xr-sdk/run/emulator/xr-headsets-glasses).
- For audio/display glasses hardware access, code must use a projected context to access glasses hardware instead of the phone hardware. The docs also call out battery and thermal limits on glasses devices and recommend conservative resolution/frame-rate choices by use case. Source: [Use a projected context to access glasses hardware](https://developer.android.com/develop/xr/jetpack-xr-sdk/access-hardware-projected-context).
- Display capability must be checked at runtime because not every glasses device has a display and display state can change. Source: [Check device capabilities at runtime for audio glasses and display glasses](https://developer.android.com/develop/xr/jetpack-xr-sdk/glasses/check-capabilities).
- Android XR supports OpenXR 1.1 and Android vendor extensions for depth, anchors, hand/eye/face tracking, raycasts, trackables, and light estimation. These are platform capabilities, not Blueprint capture evidence until the app records and validates those signals. Source: [Build with supported OpenXR extensions](https://developer.android.com/develop/xr/openxr/extensions).
- ARCore raw depth can be incomplete per pixel and requires confidence handling. Depth support must be checked and represented conservatively. Source: [ARCore Raw Depth](https://developers.google.com/ar/develop/java/depth/raw-depth).

## Required Run Inputs

Fill this section before the device run starts.

| Field | Value |
| --- | --- |
| Run id |  |
| Operator |  |
| Date/time and timezone |  |
| Repo path | `/Users/nijelhunt_1/workspace/BlueprintCapture` |
| Git branch |  |
| Git commit SHA |  |
| Dirty worktree summary |  |
| Android app build type | debug / internal / release candidate |
| Android app version/build |  |
| Host phone model |  |
| Host phone Android version/build |  |
| Android XR device type | audio glasses / display glasses / headset / wired XR glasses |
| Android XR device model |  |
| Android XR OS/build |  |
| Pairing method | physical / AVD / other |
| Network | Wi-Fi / cellular / offline |
| Test account/user id |  |
| Capture target label |  |
| `scene_id` |  |
| `capture_id` |  |
| `site_submission_id` |  |
| `buyer_request_id` |  |
| `capture_job_id` |  |
| Rights basis | open capture / documented permission / buyer request / unknown |
| Downstream Pipeline/WebApp validation planned | yes / no |

## Preflight Commands

Run from the repo root unless noted.

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

```bash
cd /Users/nijelhunt_1/workspace/BlueprintCapture
./scripts/android_alpha_readiness.sh --validate-config-only
```

Expected behavior:

- Unit/build checks should pass before hardware conclusions are trusted.
- `android_alpha_readiness.sh --validate-config-only` may fail closed on missing local release config. Treat that as an alpha/release blocker, not as a reason to weaken the hardware packet.
- Do not edit `android/local.properties`, `android/app/google-services.json`, ignored release config, or secret files to force a green result.

## Hardware Gates

### HW-P0: Environment And Install

Pass criteria:

- Git state, app build, host phone, and Android XR hardware are recorded above.
- App installs on the host phone.
- The Android XR device pairs with the host phone.
- `adb devices -l` or Android Studio Device Manager shows the host phone and, when applicable, the XR/emulator endpoint.
- No mock/stub hardware path is used unless the run is explicitly labeled emulator-only or mock-only.

Evidence to attach:

- `git status --short --branch --untracked-files=all`
- Gradle command outputs
- device list screenshot or command output
- app install artifact path or build output path

### HW-P1: Projected Activity Launch

Pass criteria:

- Android XR panel reports connected hardware or a controlled emulator pairing state.
- Launching the projected activity succeeds through `ProjectedContext.createProjectedActivityOptions(...)`.
- Runtime display capability is detected, not assumed.
- The activity renders display-glasses UI only when visual UI is supported and visuals are on.
- Audio-only or visuals-off mode does not claim display UI readiness.

Evidence to attach:

- host app screenshot before launch
- projected activity screenshot or screen recording for display glasses
- logcat entries for projected context launch and display capability
- note whether visual UI was available, unavailable, or turned off

### HW-P2: Projected Permissions

Pass criteria:

- Projected-device camera and microphone permissions are requested and resolved for the projected device.
- Permission denial leaves the app recoverable through the retry action.
- Permission success triggers projected camera initialization.
- The run records whether permission dialogs were shown on host phone, glasses, or both.

Evidence to attach:

- permission screenshots
- logcat lines for permission result
- manual note for denied -> retry behavior if tested

### HW-P3: Camera, Mic, Voice, And Thermal Smoke

Pass criteria:

- Projected camera prepares successfully on the tested hardware.
- Starting capture produces `VideoRecordEvent.Start`.
- Status updates report elapsed recording time.
- Stopping capture produces `VideoRecordEvent.Finalize` without error.
- Audio is either recorded with the projected camera path or explicitly recorded as unavailable.
- Voice UX truthfully reports Gemini availability or on-device fallback. A Firebase AI connectivity check is not full voice-to-voice Gemini Live proof.
- A 3-minute capture does not hit severe thermal, battery, or app lifecycle failure.

Evidence to attach:

- output `walkthrough.mp4` metadata
- logcat filtered for `AndroidXr`, `GlassesProjectedActivity`, `CameraX`, `VideoRecordEvent`, `Gemini`, and `VoiceSession`
- note actual resolution, FPS, duration, and audio state
- battery and thermal observation before/after the run

### HW-P4: Raw Bundle Finalization

Pass criteria:

- Capture finalization writes the raw bundle under `files/capture_bundles/scenes/{scene_id}/captures/{capture_id}/raw/`.
- `walkthrough.mp4` is present and non-empty.
- `manifest.json`, `capture_context.json`, `recording_session.json`, `video_track.json`, `provenance.json`, `rights_consent.json`, `hashes.json`, and `capture_upload_complete.json` are present.
- `hashes.json` covers all final raw files except itself.
- Current video-only Android XR captures do not claim pose, depth, motion authority, or geometry source.

Debug extraction helper:

```bash
adb shell run-as Public.BlueprintCapture.Android find files/capture_bundles -type f
```

```bash
adb exec-out run-as Public.BlueprintCapture.Android tar -C files/capture_bundles -cf - . > /tmp/android-xr-capture-bundles.tar
```

Expected current manifest values:

```json
{
  "capture_source": "glasses",
  "capture_tier_hint": "tier2_glasses",
  "capture_profile_id": "android_xr_glasses",
  "capture_modality": "android_xr_video_only",
  "capture_capabilities": {
    "camera_pose": false,
    "camera_intrinsics": false,
    "depth": false,
    "motion": false,
    "geometry_expected_downstream": false
  }
}
```

Expected current `recording_session.json` value:

```json
{
  "world_frame_definition": "unavailable_no_public_world_tracking",
  "gravity_aligned": false
}
```

### HW-P5: Upload Queue And Remote Raw Prefix

Pass criteria:

- App queues the finalized raw bundle for upload.
- Upload queue id is visible in app state/logs.
- Remote raw prefix is known or explicitly blocked by offline/backend config.
- `capture_upload_complete.json` is uploaded last when remote upload runs.
- Upload errors are specific and recoverable.

Evidence to attach:

- queued upload id
- local raw bundle path
- remote storage prefix or exact upload blocker
- logcat lines for enqueue, upload progress, and completion/failure

### HW-P6: Bridge, Pipeline, And WebApp Chain

This gate is required before downstream readiness claims. It may be marked `blocked_not_run` for a hardware-only run.

Pass criteria:

- Bridge accepts the same raw prefix and capture id.
- Bridge writes `capture_descriptor.json`, `qa_report.json`, and `pipeline_handoff.json`.
- Pub/Sub handoff uses the same capture id.
- Pipeline consumes the same capture id and emits package/proof/readiness artifacts or a precise blocker.
- WebApp has real upstream ids and artifact links before hosted-review, buyer-access, payout, or launch statements.

Evidence to attach:

- bridge output paths
- Pipeline output paths
- WebApp request/job/hosted-review links
- exact blocker codes if not complete

## Failure Codes

Use these codes in the closeout so repeated device runs can be compared.

| Code | Meaning | First triage target |
| --- | --- | --- |
| `xr_pairing_blocked` | Glasses cannot pair or reconnect | Android Studio Device Manager, Bluetooth, host phone state |
| `projected_launch_blocked` | Projected activity does not launch | `AndroidXrViewModel.launchProjectedExperience` |
| `projected_permission_blocked` | Camera/mic permissions fail or cannot be retried | `GlassesProjectedActivity.requestHardwarePermissions` |
| `display_capability_mismatch` | UI mode does not match runtime display capability | `AndroidXrUxState`, `ProjectedDeviceController` |
| `projected_camera_bind_failed` | CameraX cannot bind in projected context | `AndroidXrProjectedCaptureManager.prepare` |
| `recording_finalize_failed` | Recording starts but finalize has an error | `VideoRecordEvent.Finalize` logs |
| `voice_truth_mismatch` | Gemini/on-device fallback state is misleading | `VoiceSessionOrchestrator`, `AndroidXrVoiceGuidancePolicy`, `UnavailableGeminiLiveConnector` |
| `bundle_validation_failed` | Raw bundle is malformed or overclaims | `AndroidCaptureBundleBuilder`, raw V3 validator |
| `hash_coverage_missing` | `hashes.json` misses final raw files | bundle finalization |
| `upload_queue_blocked` | Bundle writes but cannot enqueue/upload | `CaptureUploadRepository` |
| `bridge_handoff_blocked` | Raw upload exists but bridge output is missing | `cloud/extract-frames` |
| `pipeline_materialization_blocked` | Pipeline cannot package same capture id | `BlueprintCapturePipeline` |
| `upstream_truth_blocked` | Hosted-review/buyer/payout claims lack real ids | WebApp/request/job bootstrap |
| `thermal_or_battery_blocked` | Hardware cannot sustain capture duration | resolution/FPS/thermal policy |

## Closeout Template

Use this exact shape in a run-specific note or issue comment.

```text
Android XR hardware validation closeout

Run id:
Date/time:
Operator:
Repo branch/SHA:
App build:
Host phone:
Android XR hardware:
Capture target:
scene_id:
capture_id:

Gate results:
- HW-P0 environment/install:
- HW-P1 projected activity:
- HW-P2 permissions:
- HW-P3 camera/mic/voice/thermal:
- HW-P4 raw bundle:
- HW-P5 upload queue:
- HW-P6 bridge/pipeline/webapp:

Current claim ceiling:

Evidence paths:
- local raw bundle:
- pulled bundle archive:
- upload queue id:
- remote raw prefix:
- bridge outputs:
- Pipeline outputs:
- WebApp links:

Blockers:

Next input needed:
```

## Negative Claim Audit

Before marking a run done, confirm each statement remains false unless the same capture id has hard evidence:

- Android XR is public or external-alpha ready.
- Android XR is launch ready.
- Android XR provides native pose, native IMU, depth, or calibrated extrinsics.
- A projected CameraX recording is a world model.
- A local Gradle pass proves hardware capture readiness.
- A queued upload proves bridge/Pipeline/WebApp readiness.
- A hosted-review, buyer-access, payout, provider, or launch state exists without real upstream ids.

## Related Repo Artifacts

- [Android XR AI-Glasses Readiness](ANDROID_XR_AI_GLASSES_READINESS.md)
- [Capture-to-Pipeline Android XR Proof Map](CAPTURE_TO_PIPELINE_ANDROID_XR_PROOF_MAP.md)
- [On-Device QA Checklist](ANDROID_XR_ON_DEVICE_QA_CHECKLIST_2026-05-23.md)
- [Capture Raw Contract V3](CAPTURE_RAW_CONTRACT_V3.md)
