# Refactor Hotspots

This is a low-risk future split plan only. Do not split these files unless the change is mechanical, covered by focused tests, and preserves raw-capture and upload behavior.

## `BlueprintCapture/VideoCaptureManager.swift`

Current responsibility:
- Owns iPhone capture lifecycle across AVFoundation, ReplayKit, ARKit, CoreMotion, depth/confidence/mesh extraction, AR frame logs, semantic anchor marks, screen recording, manifests, and packaging.

Risk:
- Sensor timing, coordinate frames, depth cadence, screen-recording fallback, ARKit reset behavior, motion logs, and manifest fields are tightly coupled. Small changes can silently weaken raw evidence or break V3 sidecars.

Safe future split:
- Extract an `ARKitEvidenceRecorder` for AR session/frame/depth/mesh logs.
- Extract a `MotionLogWriter` for IMU sampling and JSONL output.
- Extract a `VideoRecordingAdapter` for AVFoundation/ReplayKit fallback behavior.
- Extract a `CaptureManifestWriter` for manifest persistence.
- Keep `VideoCaptureManager` as the orchestration facade until contract tests cover the split.

## `BlueprintCapture/Services/CaptureBundleSupport.swift`

Current responsibility:
- Defines capture intake/task metadata, evidence summaries, bundle context helpers, bundle finalization, V3 validation, manifest patching, supplemental sidecar writing, hashes/provenance, local export, and intake resolution.

Risk:
- This file is central to raw bundle truth. It decides world-model candidate reasoning, upstream handoff blockers, evidence counters, rights metadata, and hashes. Splitting without parity tests can change contract output.

Safe future split:
- Extract `RawBundleValidator` from `validateRawBundle`.
- Extract `EvidenceInspector` from evidence counting and alignment inspection.
- Extract `ManifestPatchWriter` for manifest/capture context/topology/mode patching.
- Extract `ProvenanceHashWriter` for hashes and provenance.
- Extract `ARKitDerivedSidecarWriter` for derived V3 sidecars.
- Keep `CaptureBundleFinalizer` behavior stable and covered by raw-contract tests.

## `BlueprintCapture/GlassesCaptureManager.swift`

Current responsibility:
- Owns Meta glasses setup, MWDAT/mock device handling, discovery/connection, streaming, video writer, frame metadata, motion logging, companion-phone AR tracking, manifest/package creation, and simulator/physical-device gating.

Risk:
- Real SDK availability, simulator guards, mock-vs-real behavior, companion-phone pose truth, and public-readiness copy are easy to blur. Mock support must not become public proof.

Safe future split:
- Extract `MetaWearablesAdapter` for real MWDAT registration, discovery, and stream state.
- Extract `MockGlassesAdapter` for dev-only mock behavior.
- Extract `GlassesArtifactWriter` for frames/video/stream metadata.
- Extract `CompanionPhoneTracker` for ARSession pose/intrinsics/calibration sidecars.
- Keep physical-device and mock boundaries explicit in tests and UI.

## `BlueprintCapture/Services/CaptureUploadService.swift`

Current responsibility:
- Manages iOS upload queue state, bundle finalization handoff, Firebase Storage uploads, completion-marker ordering, Firestore lifecycle/submission registration, upload failure recording, retries, cancellation, and error classification.

Risk:
- Upload ordering is contract-sensitive because `capture_upload_complete.json` triggers bridge work. Registration writes mutate external state. Error handling must distinguish retryable upload failures from invalid bundles and already-finalized storage.

Safe future split:
- Extract `UploadQueueStateStore` for local queue persistence and state transitions.
- Extract `FirebaseBundleUploader` for file upload and completion-marker-last behavior.
- Extract `CaptureSubmissionRegistrar` for Firestore lifecycle/submission payloads.
- Extract `UploadFailureReporter` for failure payloads.
- Keep `CaptureUploadService` as the public facade until upload integration tests cover ordering and idempotency.

## `android/app/src/main/kotlin/app/blueprint/capture/ui/screens/ScanScreen.kt`

Current responsibility:
- Owns Compose scan feed UI, search/submit flow, target detail modal, capture method picker, rights acknowledgement, glasses launch entry, refresh controls, and large UI helper components.

Risk:
- The screen mixes public-facing copy with capture launch decisions. It can accidentally make open capture look like approved paid work or glasses support look launch-ready.

Safe future split:
- Extract `ScanFeedContent` for feed rendering.
- Extract `SearchAndSubmitFlow` for autocomplete/current-location submission.
- Extract `TargetDetailDialog` and target card components.
- Extract `RightsAcknowledgementDialog`.
- Extract `GlassesLaunchCoordinator` UI wrapper.
- Keep `ScanViewModel` launch conversion behavior unchanged during UI-only splits.

## `android/app/src/main/kotlin/app/blueprint/capture/ui/screens/CaptureSessionScreen.kt`

Current responsibility:
- Owns Android capture session UI, CameraX binding, ARCore recording path, runtime permissions, IMU start/flush, recording lifecycle, post-capture review, export/share, upload/save actions, and site-world capture prompts.

Risk:
- Compose lifecycle, CameraX/ARCore session state, local file cleanup, permission state, and IMU timing are intertwined. Refactors can leak files, drop motion samples, or enqueue incomplete bundles.

Safe future split:
- Extract `CameraXRecorderHost` for CameraX preview/recording.
- Extract `ARCoreRecorderHost` for ARCore capture start/stop.
- Extract `CapturePermissionGate`.
- Extract `PostCaptureReviewSurface`.
- Extract `SiteWorldPromptPanel`.
- Keep `CaptureSessionViewModel.prepareRecordedCapture` inputs stable and covered by Android bundle tests.

## `cloud/extract-frames/src/index.ts`

Current responsibility:
- Handles Firebase Storage triggers, capture path parsing, object waiting/loading, manifest/sidecar merge, validation, ffmpeg frame extraction, pose matching, artifact availability checks, quality gate, descriptor/QA construction, Pipeline handoff writing, and Pub/Sub publish.

Risk:
- The file combines external trigger behavior with contract validation and downstream handoff. A small change can cause duplicate bridge runs, premature handoff, weakened blockers, or broken legacy compatibility.

Safe future split:
- Extract `capture-paths.ts` for path parsing and object-kind routing.
- Extract `raw-loader.ts` for manifest/sidecar/loading and object existence checks.
- Extract `frame-extraction.ts` for ffmpeg/ffprobe work.
- Extract `descriptor-builder.ts` for descriptor/QA/handoff payload construction.
- Extract `handoff-publisher.ts` for Pub/Sub and storage writes.
- Keep trigger behavior unchanged and covered by bridge tests before splitting.

## `cloud/referral-earnings/src/index.ts`

Current responsibility:
- Owns referral bonus processing, capture lifecycle operating-graph sync, `updateCaptureStatus`, demand request APIs, opportunity feed, nearby/places proxies, scheduled demand research, and weekly strategic weighting.

Risk:
- Referral/payout mutations, capture status updates, demand APIs, and provider proxies are different domains in one file. Tests need to protect idempotency, Firestore writes, and API routing before moving code.

Safe future split:
- Extract `referral-bonuses.ts` for `onCaptureApproved`.
- Extract `capture-lifecycle.ts` for operating-graph sync and canonical foreign keys.
- Extract `capture-status-api.ts` for `updateCaptureStatus`.
- Extract `demand-api.ts` for demand submissions and opportunity feed.
- Extract `nearby-api.ts` for nearby/autocomplete/details proxy handlers.
- Extract `demand-schedules.ts` for daily/weekly scheduled jobs.
