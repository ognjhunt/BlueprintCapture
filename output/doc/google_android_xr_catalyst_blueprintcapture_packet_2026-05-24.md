# Google Android XR Catalyst Application Packet - BlueprintCapture

Status: prepared local packet only. No application was opened, submitted, or transmitted.

Prepared: 2026-05-24
Repo: `/Users/nijelhunt_1/workspace/BlueprintCapture`

Audience note: external-draft answer bank for a possible Google Catalyst submission. Do not treat it as public marketing copy or proof of Android XR, payout, provider, buyer, or launch readiness.

## Submission Recommendation

Submit one Catalyst application for **audio glasses / display glasses** first.

Reason: the current BlueprintCapture Android path is a phone-hosted projected Android XR experience for glasses, with projected camera, microphone, audio-led guidance, optional display UI, bundle finalization, and upload queueing. A wired XR / Project Aura application can be a later separate application if Blueprint wants an immersive review or route-planning experience; Google's FAQ says distinct wired-glasses and audio/display-glasses ideas should be submitted separately.

Primary vertical: **Productivity & Learning**
Secondary vertical: **Discovery & Navigation**
Application title: **BlueprintCapture XR - Hands-free field evidence capture for real sites**

Recommended hardware request:

- Primary: Android XR display glasses development kit.
- Secondary: Android XR audio glasses development kit.
- Optional later/separate: XREAL Project Aura wired XR glasses for immersive route review and spatial package inspection.

Recommended grant ask if the form requires a number: **USD 50,000**. Treat this as editable before submission.

Suggested grant breakdown:

| Use | Amount |
| --- | ---: |
| Android XR hardware validation, device lab, test phones, field accessories | USD 8,000 |
| Projected camera/mic capture hardening, audio/display UX, accessibility, thermal/battery QA | USD 18,000 |
| Raw-bundle, bridge, Pipeline, and WebApp proof-chain integration for Android XR captures | USD 12,000 |
| Google Play closed testing, privacy/safety review, pilot operator support, documentation | USD 12,000 |
| Total | USD 50,000 |

## Web Research Snapshot

Research was done from public web sources on 2026-05-24.

Key Catalyst facts:

- The [Android XR Developer Catalyst Program](https://developer.android.com/develop/xr/catalyst) is open for applications, with applications closing **June 30, 2026 at 11:59 PM PDT** and selection notifications due no later than **July 15, 2026**.
- The program is for developers looking to publish Android XR apps in the next **6-12 months**.
- Google says the program may provide development kits, technical resources/support, and non-recoupable grant opportunities.
- Core verticals include media and entertainment, gaming, productivity and learning, discovery and navigation, messaging and social, health and wellness, and commerce/payments.
- For form factor choice, Google distinguishes wired XR glasses from audio/display glasses. Audio/display glasses are described as glanceable, hands-free, daily utility experiences using voice and touchpad inputs.
- Developer kits for XREAL Project Aura can currently ship only to developers in the United States, Japan, the United Kingdom, and the European Union.
- The Android Developers Blog announcement says Catalyst is intended to accelerate Android XR apps ready to launch within the next year: [Build for the future with the Android XR Developer Catalyst Program](https://developer.android.com/blog/posts/build-for-the-future-with-the-android-xr-developer-catalyst-program-apply-now?hl=en).

Relevant Android XR technical sources:

- [Develop with the Jetpack XR SDK](https://developer.android.com/develop/xr/jetpack-xr-sdk?authuser=00): Jetpack XR supports immersive and augmented experiences across headsets, wired XR glasses, and AI/audio/display glasses; Compose Glimmer and Jetpack Projected support glasses experiences.
- [AI Glasses design guidance](https://developer.android.com/design/ui/ai-glasses): audio/display glasses should provide hands-free utility, context-aware assistance, faster comprehension, visual assistance, and hands-free capture without obstructing the user's real-world focus.
- [Android XR app quality guidelines](https://developer.android.com/docs/quality-guidelines/android-xr?hl=en): differentiated Android XR apps should add XR-specific features/content and meet comfort, privacy, input, performance, and accessibility expectations.
- [Run augmented experiences on the Android XR emulator for glasses](https://developer.android.com/develop/xr/jetpack-xr-sdk/run/emulator/glasses): emulator testing can cover touchpad, voice, audio-only mode, custom photo environments, and screenshots, but it does not replace physical hardware proof.
- Public coverage of XREAL Project Aura says early developer access is tied to the Catalyst program and that Project Aura is expected before the end of 2026: [9to5Google](https://9to5google.com/2026/05/19/xreal-project-aura-android-xr-developers-2026-launch/). Use this only as secondary context; application claims should rely on official Google pages.

## Repo-Grounded Product Framing

BlueprintCapture is the evidence-capture client for Blueprint. It records real site walkthrough evidence, preserves raw sensor/video/timing/device truth, packages canonical capture bundles, and uploads them for bridge/Pipeline processing into site-specific world-model packages and hosted access.

Android XR is valuable because field capture is an in-world, hands-busy workflow:

- Capturers can keep their phone down and follow voice/glanceable guidance while walking a real site.
- The app can show capture status, route prompts, privacy reminders, and upload/finalization state without pulling attention away from the environment.
- Audio/display glasses are a better fit than a flat phone for long walkthroughs, site constraints, safety reminders, and "do not capture this" privacy moments.
- The captured raw bundle remains authoritative; downstream world-model packages are derived products and do not rewrite capture truth.

Current local repo claim ceiling:

- Android XR is an internal, video-first projected-glasses path.
- Current projected Android XR bundles can truthfully preserve `capture_source = "glasses"`, `capture_tier_hint = "tier2_glasses"`, `capture_profile_id = "android_xr_glasses"`, and `capture_modality = "android_xr_video_only"`.
- Current no-sidecar Android XR output must not claim pose, depth, geospatial, native IMU, payout readiness, provider readiness, hosted-review readiness, buyer access, or launch readiness.
- Physical Android XR hardware validation is still required before claiming runtime readiness.

Relevant local evidence files:

- `/Users/nijelhunt_1/workspace/BlueprintCapture/README.md`
- `/Users/nijelhunt_1/workspace/BlueprintCapture/PLATFORM_CONTEXT.md`
- `/Users/nijelhunt_1/workspace/BlueprintCapture/WORLD_MODEL_STRATEGY_CONTEXT.md`
- `/Users/nijelhunt_1/workspace/BlueprintCapture/docs/CAPTURE_RAW_CONTRACT_V3.md`
- `/Users/nijelhunt_1/workspace/BlueprintCapture/docs/ANDROID_XR_AI_GLASSES_READINESS.md`
- `/Users/nijelhunt_1/workspace/BlueprintCapture/docs/ANDROID_XR_HARDWARE_VALIDATION_PACKET_2026-05-23.md`
- `/Users/nijelhunt_1/workspace/BlueprintCapture/docs/ANDROID_XR_ON_DEVICE_QA_CHECKLIST_2026-05-23.md`
- `/Users/nijelhunt_1/workspace/BlueprintCapture/docs/CAPTURE_TO_PIPELINE_ANDROID_XR_PROOF_MAP.md`

## Form-Ready Answer Bank

### One-line description

BlueprintCapture XR is a hands-free Android XR field-capture app that helps operators record truthful real-site evidence for downstream site-specific world-model packages.

### Short project summary

BlueprintCapture XR turns Android XR audio/display glasses into a hands-free field evidence capture tool. A capturer walks a real site while Blueprint provides voice and glanceable guidance, records projected camera/mic evidence, packages a conservative raw bundle, and uploads it for downstream bridge and Pipeline processing into site-specific world-model products. The app is built to preserve provenance, rights, privacy, timestamps, and device truth without overstating world-tracking or launch readiness.

### Problem

Real-world robot teams need site-specific world-model packages, but high-quality site capture is still operationally hard. Phone-based capture forces operators to look down, manage instructions manually, and remember privacy/coverage constraints while moving through real environments. Generic photos or generated scenes are not enough: buyers need evidence provenance, repeatable capture structure, and rights-safe packages tied to exact sites.

### Solution

BlueprintCapture XR gives field operators a hands-free capture workflow on Android XR glasses. The app guides the operator through a capture route, records video/audio evidence, tracks capture state, reminds the user about privacy and coverage constraints, and finalizes a canonical raw bundle for upload. Downstream Blueprint systems convert those bundles into site-specific packages and hosted access for robot teams.

### Why Android XR

Android XR fits this use case because the capture workflow happens in the physical world. Audio/display glasses let the operator keep attention on the site while receiving just-in-time guidance, status, and safety/privacy prompts. Jetpack Projected and Compose/Glimmer-style UI patterns map well to Blueprint's need for a lightweight, glanceable, voice-led field tool rather than a fully immersive entertainment experience.

### Why Catalyst

Catalyst support would close the current gap between a compiler-verified projected-glasses implementation and physical Android XR hardware proof. Blueprint needs early hardware access, technical guidance on projected camera/mic behavior, audio/display UX, Play readiness, and milestone-based support to harden the capture-to-upload proof chain before publishing.

### Form factor choice

Primary choice: audio glasses / display glasses.

Rationale: BlueprintCapture is an all-day, contextual field utility. The operator should stay present in the physical space, receive concise guidance, and record evidence without holding or constantly checking a phone. Display glasses add glanceable status and warnings when available; audio glasses still support a voice-led workflow.

If the form allows a note: wired XR glasses / XREAL Project Aura are interesting for a future separate application focused on immersive route planning and package review, but the current application should stay focused on the projected audio/display capture workflow already present in the Android repo.

### Current development stage

Prototype / internal alpha.

Current repo state:

- Android phone capture and raw-bundle plumbing already exist.
- Android XR projected activity exists for audio/display glasses.
- The app requests projected camera/mic permissions, records projected video through CameraX, finalizes the raw bundle, and queues upload.
- Android XR output is intentionally video-first and conservative: no pose/depth/geospatial authority is claimed without validated sidecars.
- Physical Android XR hardware validation is the next hard gate.

### Technical stack

- Kotlin and Jetpack Compose.
- Android XR projected APIs.
- CameraX video capture in projected context.
- Voice session orchestration with on-device ASR/TTS fallback.
- Firebase Auth, Firestore, Storage, and WorkManager-backed upload queue.
- Blueprint raw capture contract V3/V3.1 for video, metadata, rights, provenance, hashes, and upload completion.
- Downstream bridge and BlueprintCapturePipeline for frame extraction, package materialization, QA, handoff, and hosted product artifacts.

### XR-specific experience

The Android XR experience is not just a flat mobile screen. It adds:

- projected camera/mic capture from glasses hardware
- audio-first capture guidance
- display-glasses status UI when visual UI is available
- runtime display/audio capability handling
- hands-free capture start/stop and status feedback
- conservative raw evidence labeling for Android XR modality
- field-safe prompts that keep privacy, rights, and capture coverage visible to the operator

### Privacy and safety

BlueprintCapture is designed around truthful evidence and conservative rights handling.

- Raw capture, timestamps, device metadata, rights, consent, and provenance remain authoritative.
- The app does not infer payout readiness, provider readiness, buyer access, hosted review, or launch readiness from capture alone.
- Privacy prompts are part of the capture workflow; operators are guided to avoid private people, screens, paperwork, and non-consented areas.
- Missing upstream request/job/site ids remain blockers for buyer access, hosted-review, payout, and launch claims.
- Android XR no-sidecar captures do not claim pose, depth, geospatial, native IMU, or metric world tracking.

### AI/Gemini posture

BlueprintCapture has a voice orchestration seam and on-device speech fallback. The application should describe this as "voice guidance and optional Gemini/Firebase AI connectivity under development," not as production-proven Gemini Live voice-to-voice capture. Full Gemini Live audio integration and hardware QA remain future work.

Suggested form wording:

Blueprint currently uses a voice-session orchestration layer with on-device ASR/TTS fallback. We plan to use Gemini-powered guidance where it can improve capture coaching, site constraint recall, and hands-free operator support, but we will not ship AI guidance as authoritative site truth. Raw capture artifacts and explicit metadata remain the source of truth.

### Publishing plan

Blueprint expects to publish an Android XR-compatible capture experience through Google Play within 6-12 months after Catalyst selection, subject to hardware validation and Play review.

Milestone plan:

| Period | Milestone |
| --- | --- |
| July 2026 | Catalyst onboarding, dev kit setup, projected camera/mic smoke on physical hardware |
| August 2026 | Hardware validation packet completed for one display/audio glasses device; raw bundle finalization and upload proof recorded |
| September 2026 | Bridge and Pipeline consume the same Android XR capture id; proof map updated with blockers or outputs |
| October 2026 | Closed internal field pilot with conservative video-first Android XR capture |
| November-December 2026 | Google Play closed testing, accessibility/comfort pass, privacy/safety review, crash/ANR/vitals checks |
| January-March 2027 | Broader beta or launch candidate if Capture, bridge, Pipeline, WebApp, and Play gates are green |

### Technical milestones for grant

1. Physical device validation for projected camera, microphone, display/audio mode, permissions, thermal behavior, and battery impact.
2. Android XR raw-bundle proof pack with manifest, recording session, provenance, rights/consent, hashes, and upload completion.
3. Bridge and Pipeline preservation of Android XR modality for the same capture id.
4. Google Play closed testing build with Android XR-specific QA checklist and non-overclaiming UX.
5. Field pilot with real capturers and real site targets, gated by rights/privacy workflows.

### Team / developer readiness

Suggested answer:

Blueprint already has a working Android codebase, an iOS reference capture app, a raw capture contract, cloud bridge tests, and a downstream Pipeline/WebApp architecture. The team has implemented the Android XR projected activity and conservative raw-bundle path, and needs Catalyst hardware and technical support to validate the implementation on real Android XR devices and prepare it for Google Play.

Replace with exact team details before submission:

- Applicant name: `[fill]`
- Company/legal entity: `[fill]`
- Website: `https://tryblueprint.io` or `[fill]`
- Contact email: `[fill]`
- Google Play developer account status: `[fill]`
- Country/shipping region: United States, if accurate

### Funding requirement answer

Suggested answer:

We are requesting USD 50,000 in non-recoupable grant support plus Android XR development hardware. The funds will be used for physical device validation, projected camera/mic capture hardening, audio/display UX, raw-bundle and upload proof-chain work, bridge/Pipeline integration, Google Play closed testing, privacy/safety QA, and field pilot operations. The milestone target is a conservative video-first Android XR capture release that can publish through Google Play without overstating pose, depth, payout, provider, or launch readiness.

### Requested Google support

- Access to Android XR display/audio glasses hardware.
- Technical guidance on projected camera and microphone behavior.
- Guidance on Compose Glimmer / display-glasses readability and audio-only fallback patterns.
- Android XR Emulator and physical-device QA guidance.
- Google Play closed testing and XR quality-review expectations.
- Advice on Jetpack Projected, ARCore for Jetpack XR, and when Android XR pose/depth APIs are mature enough for capture-evidence claims.

### Differentiation

Most capture tools collect media; BlueprintCapture turns field evidence into a provenance-preserving supply chain for site-specific world-model products. The Android XR version is differentiated because it treats glasses as a truthful capture surface rather than a demo renderer: it preserves raw evidence, labels missing signals explicitly, and ties capture to downstream package and buyer workflows.

### Success metrics

- Percentage of Android XR captures that finalize a valid raw bundle.
- Upload completion rate and retry recovery rate.
- Time from capture stop to queued upload.
- Number of privacy/coverage prompts completed during capture.
- Bridge acceptance rate for Android XR capture ids.
- Pipeline package success/blocker rate for the same capture ids.
- Capturer completion rate and recapture rate compared with phone-only capture.
- Crash/ANR/vitals performance in Play closed testing.

## Non-Claims To Keep Out Of The Application

Do not claim:

- Android XR path is public launch ready.
- Android XR path is external-alpha ready.
- Current Android XR glasses provide native pose, native IMU, depth, geospatial, or calibrated extrinsics.
- A projected CameraX recording is a site-specific world model.
- Queued upload proves Pipeline package quality.
- Local tests prove hardware readiness.
- Blueprint has live payout/provider readiness on Android XR.
- Gemini Live voice-to-voice integration is production proven.

Safe wording:

- "Internal video-first Android XR projected-glasses path."
- "Physical hardware validation is the next gate."
- "Current raw bundles preserve Android XR modality without claiming pose/depth authority."
- "Downstream world-model products are derived from capture evidence through the bridge and Pipeline."

## Verification Notes From This Session

No Google application was submitted.

Local verification attempted:

1. Initial command failed because `ANDROID_HOME` and `android/local.properties` were absent:

```bash
./gradlew :app:compileDebugKotlin :app:testDebugUnitTest --tests ...
```

2. SDK exists at `/Users/nijelhunt_1/Library/Android/sdk`; rerun with `ANDROID_HOME` passed:

```bash
ANDROID_HOME=/Users/nijelhunt_1/Library/Android/sdk ./gradlew :app:compileDebugKotlin :app:testDebugUnitTest --tests app.blueprint.capture.data.glasses.GlassesPlatformRegistryTest --tests app.blueprint.capture.data.glasses.voice.VoiceSessionOrchestratorTest --tests app.blueprint.capture.data.capture.AndroidCaptureSourceSerializationTest --tests app.blueprint.capture.data.capture.AndroidCaptureBundleBuilderTest
```

Result at that point: `BUILD SUCCESSFUL in 1m 2s`, `36 actionable tasks: 12 executed, 24 up-to-date`.

3. A later targeted test run against the current dirty worktree failed during unit-test compilation:

```bash
ANDROID_HOME=/Users/nijelhunt_1/Library/Android/sdk ./gradlew :app:testDebugUnitTest --tests app.blueprint.capture.data.glasses.AndroidXrUxStateTest
```

Latest failure:

- `android/app/src/test/kotlin/app/blueprint/capture/data/capture/AndroidCaptureBundleBuilderTest.kt:444`
- `android/app/src/test/kotlin/app/blueprint/capture/data/capture/AndroidCaptureBundleBuilderTest.kt:447`
- `android/app/src/test/kotlin/app/blueprint/capture/data/capture/AndroidCaptureBundleBuilderTest.kt:450`

The test references unresolved `geospatial`, `geospatialRows`, and `geospatialAuthority` fields. Treat the current worktree as needing that local test/model mismatch resolved before claiming a fresh all-tests-green state.

## Submission Checklist Before Opening The Form

- [ ] Confirm applicant/legal entity/contact email.
- [ ] Confirm the Google account that should own the application.
- [ ] Confirm Google Play developer account status.
- [ ] Confirm shipping address is in an eligible region.
- [ ] Decide whether to request USD 50,000 or adjust grant amount.
- [ ] Choose audio/display glasses as the primary form factor.
- [ ] Keep wired XR / Project Aura as a separate future application unless the form allows a secondary hardware note.
- [ ] Resolve or explicitly ignore the current local `geospatial*` test/model mismatch before using fresh test claims.
- [ ] Do not attach screenshots or videos as Android XR hardware proof until physical device validation exists.
- [ ] Do not submit until the final form preview has been reviewed manually.

## Copy-Paste Final Narrative

BlueprintCapture XR is a hands-free Android XR field-capture app for building truthful, provenance-preserving real-site evidence packages. Capturers walk physical sites while Android XR audio/display glasses provide concise voice and glanceable guidance, projected camera/mic capture, privacy reminders, capture status, and upload/finalization feedback. The resulting raw bundle preserves video, timestamps, device metadata, rights, provenance, hashes, and explicit missing-signal semantics, then uploads to Blueprint's bridge and Pipeline for site-specific world-model products and hosted access for robot teams.

The project is a strong fit for Android XR because capture is an in-world workflow. Operators need to stay focused on the physical environment, not a phone screen. Audio/display glasses can guide coverage, reduce missed steps, and preserve privacy constraints while keeping the operator present in the space. Blueprint's implementation is intentionally conservative: current Android XR captures are video-first, do not claim pose/depth/geospatial authority without validated sidecars, and do not infer payout, provider, hosted-review, or launch readiness from capture alone.

Catalyst support would help Blueprint move from compiler-verified internal implementation to hardware-validated Android XR release. We are requesting Android XR audio/display glasses development hardware, technical support for projected camera/mic and display/audio UX, Google Play readiness guidance, and USD 50,000 in milestone-based support for hardware validation, raw-bundle proof-chain hardening, bridge/Pipeline integration, privacy/safety QA, and closed field testing. Our target is a Google Play closed-test release within 6-12 months of selection, followed by broader beta only after physical hardware, upload, bridge, Pipeline, WebApp, and Play quality gates are proven.
