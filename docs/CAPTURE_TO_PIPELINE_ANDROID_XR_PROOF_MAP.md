# Capture-to-Pipeline Android XR Proof Map

This map defines what must be proven before Android XR capture can be treated as a downstream-ready Blueprint evidence path.

It is intentionally stricter than "the app can record video" or "the bundle compiles." The proof standard is the same doctrine used across the repo: raw capture truth is authoritative, generated or downstream artifacts are derived, and buyer/hosted-review/launch claims require real upstream and downstream evidence.

Use these companion runbooks for physical-device validation:

- [Android XR Hardware Validation Packet](ANDROID_XR_HARDWARE_VALIDATION_PACKET_2026-05-23.md)
- [Android XR On-Device QA Checklist](ANDROID_XR_ON_DEVICE_QA_CHECKLIST_2026-05-23.md)

## Current Position

Android XR is a video-first internal path today.

The repo has a compiler-covered Android XR projected-glasses path that can launch a projected activity, request camera and microphone permissions, record projected video, package a canonical raw bundle, and queue upload. That is not the same as proving world-tracking, depth, site-world readiness, hosted-review readiness, payout readiness, or launch readiness.

Current claim ceiling:

- `capture_source = "glasses"` in Capture bundle/upload registration for projected Android XR glasses.
- `capture_profile_id = "android_xr_glasses"` and `capture_modality = "android_xr_video_only"` for the current no-sidecar path.
- `world_frame_definition = "unavailable_no_public_world_tracking"` when no validated XR/ARCore pose sidecars exist.
- projected camera and microphone support are app-path capabilities, not geometry proof.

Current hard blockers before public or launch-facing claims:

- physical Android XR device smoke for projected permission, camera, microphone, display/audio-only behavior, bundle finalization, upload, and queueing
- bridge acceptance and handoff proof for the same capture id
- Pipeline package/proof/readiness artifacts for the same capture id
- WebApp request/job/hosted-review ids when making hosted-review, buyer-access, payout, or launch claims
- contract alignment for any future Android XR ARCore/device-pose/depth profile names

## Evidence Lanes

| Lane | Current status | Capture proof | Bridge proof | Pipeline proof | Claim ceiling |
| --- | --- | --- | --- | --- | --- |
| Android phone camera-only | Implemented internal path | `walkthrough.mp4`, `manifest.json`, `capture_capabilities.depth=false`, explicit `missing_depth_reason`, no `arcore/*` claims | base V3 files validate; bridge can extract frames and emit descriptor/QA/handoff | video/scaffolding lanes only unless downstream validated metric evidence exists | internal pre-screen video |
| Android phone ARCore | Implemented internal path, device-dependent | `arcore/poses.jsonl`, `frames.jsonl`, `session_intrinsics.json`, `tracking_state.jsonl`; optional `point_cloud`, `planes`, `light_estimates`, depth/confidence manifests and files | bridge requires ARCore sidecars when Android profile/capabilities claim them; validates identities, frame series, transforms, referenced depth/confidence paths, and sync rows | materialization reads ARCore poses/intrinsics/depth references and can expose `geometry_source = "arcore"` | internal metric capture candidate, not launch proof by itself |
| Android XR projected glasses video-only | Implemented path, hardware smoke still required | projected `walkthrough.mp4`; bundle says `android_xr_glasses` / `android_xr_video_only`; no pose/depth/geospatial authority; phone IMU remains diagnostic only; world frame unavailable | bridge should treat it as glasses/video evidence because `capture_source = "glasses"`; no ARCore geometry should be claimed | Pipeline currently normalizes `android_*` profiles toward Android source, so same-capture package proof is required before asserting downstream readiness | internal video-first XR proof only |
| Android XR projected + validated ARCore/device-pose sidecars | Not proven in this repo | would require real projected/XR pose stream, intrinsics, tracking state, sync map, coordinate-frame semantics, and optional depth/planes | bridge must explicitly recognize `android_xr_*` geometry profiles and require `arcore/*` or XR-specific sidecars when capabilities claim them | Pipeline must preserve Android XR modality instead of silently degrading to generic Android/video/scaffolding | future XR metric evidence lane |
| Android XR AI-glasses audio/display UX | Implemented as advisory UX | display/audio-only capability state, projected permission results, voice fallback status | no geometry or world-model effect | no geometry or site-world effect | capture guidance only |

## Required Proof Chain

Every Android XR proof packet should be tied to one `scene_id` and one `capture_id`.

1. Capture created the raw bundle under `scenes/{scene_id}/captures/{capture_id}/raw/`.
2. The client uploaded all raw files and wrote `capture_upload_complete.json` last.
3. The bridge validated raw truth and produced:
   - `capture_descriptor.json`
   - `qa_report.json`
   - `pipeline_handoff.json`
4. The bridge published the same handoff payload to `blueprint-capture-pipeline-handoff`.
5. Pipeline consumed the handoff and produced the site-specific package, proof, readiness, privacy, hosted-session, or trust artifacts being claimed.
6. WebApp has real upstream ids and downstream artifact links before any hosted-review, buyer-access, payout, or launch statement is made.

Missing upstream ids are allowed for raw evidence. They are blockers for hosted-review, buyer access, payout, and launch-ready claims.

## Raw Bundle Evidence Map

| Evidence field or file | Proof meaning | Must not be used to claim |
| --- | --- | --- |
| `walkthrough.mp4` | A real Android/XR video recording exists | camera pose, metric scale, depth, site-world readiness |
| `glasses/stream_metadata.json` and `glasses/frame_timestamps.jsonl` | glasses/video stream metadata and timing exist | native glasses pose, IMU, depth, or calibrated extrinsics |
| `motion.jsonl` | phone/device IMU samples exist when present | glasses-native IMU or authoritative XR motion unless provenance and authority explicitly say so |
| `arcore/poses.jsonl` | ARCore pose rows exist | launch readiness, buyer access, or hosted-review readiness |
| `arcore/session_intrinsics.json` | camera calibration exists for the ARCore coordinate frame | depth or plane evidence by itself |
| `arcore/depth_manifest.json` and `arcore/confidence_manifest.json` | depth/confidence frames are declared and paired | full-scene metric completeness |
| `capture_capabilities` | what the device truthfully captured | downstream inference summary or provider readiness |
| `upstream_handoff.blockers` | explicit missing WebApp/request/job linkage | a reason to invent placeholder ids |
| `recording_session.world_frame_definition` | coordinate-frame truth for the raw bundle | world tracking when set to unavailable |
| `hashes.json` | bundle file integrity at finalization | proof that downstream artifacts exist |

## Android XR Web Research Implications

Official Android XR/ARCore sources support the following proof boundaries:

- Android XR supports OpenXR apps and includes trackable features such as planes, anchors, and raycasting, but those are platform capabilities that still require app wiring and device proof before Blueprint can call them capture evidence. Source: [Android XR OpenXR](https://developer.android.com/develop/xr/openxr).
- ARCore for Jetpack XR can retrieve device pose relative to a world origin after enabling device tracking; the docs warn that positional accuracy varies by device sensors and capabilities. Source: [Track device pose](https://developer.android.com/develop/xr/jetpack-xr-sdk/arcore/device-pose).
- Jetpack XR depth can expose raw and smooth depth plus confidence modes, but depth requires `android.permission.SCENE_UNDERSTANDING_FINE` and device capability checks. Source: [Retrieve depth with ARCore for Jetpack XR](https://developer.android.com/develop/xr/jetpack-xr-sdk/arcore/depth).
- ARCore for Jetpack XR on mobile devices is still marked developer preview and some mobile runtime features may require using the underlying ARCore runtime directly. Source: [Run ARCore for Jetpack XR on mobile](https://developer.android.com/develop/xr/jetpack-xr-sdk/arcore/mobile).
- Android XR projected audio/display glasses hardware access depends on a projected context; projected camera/microphone access is a hardware-context proof, not a pose/depth proof. Source: [Projected context hardware access](https://developer.android.com/develop/xr/jetpack-xr-sdk/access-hardware-projected-context).
- XR permissions are dangerous permissions that must be declared and requested at runtime; scene-understanding fine maps to depth texture, while scene-understanding coarse maps to plane tracking, raycasts, light estimation, and related trackables. Source: [XR permissions](https://developer.android.com/develop/xr/permissions).
- ARCore raw depth on Android may not cover every pixel and requires paired confidence handling; confidence values distinguish usable from weak depth evidence. Source: [ARCore Raw Depth](https://developers.google.com/ar/develop/java/depth/raw-depth).
- Android `SensorEvent.timestamp` uses nanoseconds and should be monotonically increasing on a shared elapsed-realtime timebase for a given sensor, which matches the raw contract preference for monotonic nanosecond joins. Source: [SensorEvent](https://developer.android.com/reference/android/hardware/SensorEvent).

## Contract Drift To Resolve Before XR Geometry Claims

The current repo state intentionally keeps Android XR projected glasses in a video-first lane:

- `AndroidCaptureBundleBuilder` emits `android_xr_glasses` for projected glasses and refuses to promote accidental `arcore/*` files into pose, depth, geospatial, or payout proof.
- `docs/CAPTURE_RAW_CONTRACT_V3.md` lists `android_xr_glasses` as the current Android XR profile and states that future projected-glasses geometry requires a new explicit Blueprint contract.
- `cloud/extract-frames/src/raw-contract-v3.ts` rejects Android XR glasses bundles that claim ARCore pose, intrinsics, depth, point cloud, planes, tracking-state, light-estimate, geospatial evidence, or capture-contributor payout eligibility.
- `BlueprintCapturePipeline` source inference still needs same-capture package proof before any downstream Android XR readiness claim. Local raw-bundle validity is not enough to claim Pipeline, hosted-review, buyer-access, payout, or launch readiness.

Resolution requirement before any future XR geometry lane:

- define a new explicit Android XR geometry profile and sidecar contract instead of reusing the video-only `android_xr_glasses` profile
- decide whether Android XR projected captures are downstream source `glasses`, source `android`, or a normalized subtype under one source
- update bridge validation so future XR geometry/depth claims require the right sidecars regardless of top-level `capture_source`
- update Pipeline modality normalization so any future XR geometry modality is preserved or intentionally downgraded with an explicit reason
- add same-capture negative tests proving Android XR cannot claim pose, depth, geospatial, payout, hosted-review, buyer-access, or launch readiness without the relevant upstream and downstream evidence

## Minimum Proof Pack For Android XR Internal Readiness

For one physical Android XR capture:

- device model, Android XR build, app version/build, capture start time
- screen or log evidence that the projected activity launched on hardware
- permission result for projected camera and microphone
- `walkthrough.mp4` under the raw bundle
- `manifest.json` with `capture_profile_id`, `capture_modality`, `capture_capabilities`, and `upstream_handoff.blockers`
- `recording_session.json` world-frame definition
- `hashes.json` covering all raw files
- upload queue id and remote raw prefix
- storage proof that `capture_upload_complete.json` landed after all raw files
- bridge `capture_descriptor.json`, `qa_report.json`, and `pipeline_handoff.json`
- Pipeline output path or explicit Pipeline blocker for the same capture id

Passing local Gradle tests alone is not enough for this proof pack.

## Minimum Proof Pack For Android XR Geometry Readiness

For one physical Android XR capture with real geometry sidecars:

- everything from the internal readiness pack
- app code path and device proof for the pose/depth provider used
- runtime permissions for the relevant XR features, especially head/device tracking and scene understanding
- `arcore/poses.jsonl` or an explicitly documented XR pose sidecar with:
  - monotonic `t_capture_sec`
  - `t_monotonic_ns` when available
  - `coordinate_frame_session_id`
  - row-major `T_world_camera`
  - tracking state per frame
- `arcore/session_intrinsics.json` or equivalent intrinsics sidecar
- `sync_map.jsonl` joining video frames to pose/depth rows
- depth/confidence manifests and referenced files when `capture_capabilities.depth=true`
- bridge validation showing zero missing-required-sidecar blockers
- Pipeline materialization showing `geometry_source` and pose/depth availability for the same capture id

If any item is missing, the capture can remain valid raw video evidence but must not be labeled world-tracking-authoritative.

## Negative Claims

Do not claim any of the following from current Android XR evidence alone:

- Android XR is external-alpha ready.
- Android XR is launch ready.
- Android XR glasses provide native pose, native IMU, depth, or calibrated extrinsics.
- A projected CameraX recording is a site-specific world model.
- A local bundle/test pass proves Pipeline package quality.
- A queued upload proves WebApp hosted review, buyer access, payout, provider readiness, or launch readiness.

## Next Implementation Hooks

Priority order:

1. Add contract tests around `android_xr_*` bridge validation before adding XR pose/depth sidecars.
2. Add Pipeline tests preserving Android XR modality and source normalization.
3. Run physical projected-glasses smoke and attach the proof pack to this doc or a run-specific output.
4. Only then wire Jetpack XR device pose/depth sidecars into Capture.
5. Keep Android XR public status internal-only until the same capture id proves Capture upload, bridge handoff, Pipeline materialization, WebApp linkage, and device/App Distribution smoke.
