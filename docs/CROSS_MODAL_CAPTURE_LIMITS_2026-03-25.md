# Cross-Modality Capture Limits

This note records the current runtime boundary for the additive raw-evidence V3.1 rollout.

The governing rule remains:

- raw first-party capture truth is authoritative
- downstream geometry is useful but not equivalent to raw evidence
- missing capability must stay explicit

## Android ARCore Runtime

What is implemented now:

- Android can start an ARCore-first recording session on supported devices.
- The canonical output remains `walkthrough.mp4`.
- `arcore/*` sidecars are only emitted when the live ARCore session actually writes them.
- Bundle packaging reads those sidecars truthfully and does not relabel plain camera capture as ARCore evidence.

What is not implemented yet:

- There is still no live shared-camera preview once ARCore recording takes over.
- The current UI uses CameraX only as a preflight preview before recording starts.
- When recording begins, CameraX is unbound and ARCore owns the camera session, so the on-screen preview pauses.

Why this remains a real blocker:

- A truthful live preview requires `Session.createForSharedCamera(context)` plus ARCore `SharedCamera`.
- That in turn requires a Camera2-owned session, explicit app surfaces, and a rendering pipeline tied to the same active camera stream.
- Reusing the old CameraX preview while ARCore records would be misleading, because that would not be the live ARCore capture path.

Required follow-up for true parity:

- replace the current CameraX-only preview handoff with a Camera2 + `SharedCamera` pipeline
- bind ARCore and preview surfaces to the same session
- keep lifecycle, pause/resume, and recording failure handling aligned with the shared session

## Glasses Public SDK Boundary

Signals available on the current public app paths:

- video stream frames
- stream/session lifecycle state
- limited linked-device metadata on the Android `Wearables` surface such as device name, device type, firmware info, compatibility, and link state
- timestamps and stream errors
- companion-phone ARKit pose scaffolding on iOS when the phone path is explicitly enabled

Signals that are still not publicly available on the current path:

- glasses-native IMU
- glasses-native camera pose or head pose
- calibrated glasses-to-phone extrinsics
- glasses-native depth
- glasses-native point cloud
- glasses-native plane detection
- glasses-native light estimation

Truth rules that stay in force:

- phone IMU remains diagnostic-only for glasses captures
- `companion_phone/*` remains an uncalibrated scaffold unless real extrinsics are established
- device metadata or stream state must not be relabeled as geometry truth
- downstream geometry lanes remain derived and non-authoritative

## Platform-Specific Notes

iOS Meta DAT path:

- the live capture path exposes stream state, video frames, stream errors, and photo capture
- it does not expose public glasses-native pose, IMU, or calibrated extrinsics on the path currently used in-app

Android Meta DAT path:

- the public SDK exposes `Wearables` registration/device metadata and `StreamSession` state/video/photo surfaces
- internal health/device listener plumbing exists in the installed AARs, but it is not surfaced as a stable public raw-evidence stream on the app path currently used here

Until those boundaries change in the real SDK surface, cross-modality parity must stay explicit rather than faked.
