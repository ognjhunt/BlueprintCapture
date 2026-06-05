# BlueprintCapture AI Onboarding Map

This is the repo orientation map for engineers and AI agents. It summarizes where the current implementation lives and which surfaces are authoritative. For product doctrine, read the root `AGENTS.md`, `PLATFORM_CONTEXT.md`, `WORLD_MODEL_STRATEGY_CONTEXT.md`, `README.md`, and `docs/CAPTURE_RAW_CONTRACT_V3.md` first.

BlueprintCapture is the capture client. It records truthful evidence, writes canonical raw bundles, and uploads them for bridge processing. It does not make final provider, payout, rights, buyer-trust, hosted-review, or launch-readiness decisions by itself.

## Repo Areas

- `BlueprintCapture/`: iOS app code, SwiftUI views, services, models, raw-bundle finalization, upload, wallet, profile, launch gating, and glasses capture.
- `android/`: Android app, Jetpack Compose UI, CameraX/ARCore capture, Android raw-bundle writing, upload queue, wallet/profile/auth/onboarding, launch gating, and glasses surfaces.
- `cloud/extract-frames/`: Firebase Storage bridge that consumes completed raw uploads, extracts frames, writes descriptor/QA/handoff artifacts, and publishes the Pipeline handoff.
- `cloud/referral-earnings/`: Firebase functions for capture submission status, referral earnings, demand/opportunity endpoints, nearby/place proxies, and demand research schedules.
- `scripts/`: local and release-readiness validation. These scripts should fail closed when release config, launch proof, device proof, or provider proof is missing.
- `docs/`: raw contracts, alpha/readiness constraints, bridge constraints, historical notes, and architecture maps.

## iOS App Map

### App shell and navigation

- `BlueprintCapture/BlueprintCaptureApp.swift`: app entrypoint, app delegate, and shared top-level app state wiring.
- `BlueprintCapture/MainTabView.swift`: main tab shell for scan, wallet, and profile surfaces.
- `BlueprintCapture/ContentView.swift`: top-level iOS view composition.

### Capture flow

- `BlueprintCapture/CaptureFlowViewModel.swift`: capture workflow state, permission flow, address/search resolution, post-recording metadata assembly, upload/export decisions, site-world route prompts, and recovery preservation.
- `BlueprintCapture/CaptureSessionView.swift`: SwiftUI capture session surface and user-facing recording workflow.
- `BlueprintCapture/VideoCaptureManager.swift`: iPhone recording engine. Owns AVFoundation/ReplayKit/ARKit session setup, video recording, AR frame logging, motion logging, depth/confidence/mesh artifacts, semantic anchors, manifest persistence, and artifact packaging.
- `BlueprintCapture/Views/Capture/PostCaptureSummaryView.swift`: post-capture review and action surface.
- `BlueprintCapture/Views/Capture/CaptureQualityOverlayView.swift`: capture-time quality/coaching overlay.

Keep capture coaching advisory. Do not turn local quality hints into qualification, buyer-trust, provider, payout, or launch-readiness decisions.

### Raw bundle and export

- `BlueprintCapture/Services/CaptureBundleSupport.swift`: canonical iOS raw-bundle finalization. It patches manifest fields, validates V3/V3.1 raw bundle requirements, writes supplemental sidecars, hashes/provenance, capture context, rights, intake, task hypothesis, route/topology files, and export packages.
- `BlueprintCapture/Services/CaptureRawContractV3Validator.swift`: contract validator support for raw bundles.
- `docs/CAPTURE_RAW_CONTRACT_V3.md`: authoritative raw contract for new bundles.

Raw bundle truth is first-party capture evidence: video, timestamps, poses, intrinsics, depth, motion, device metadata, sidecars, rights/provenance, and hashes. Generated media, bridge outputs, and downstream packages must not rewrite it.

### Upload

- `BlueprintCapture/Services/CaptureUploadService.swift`: iOS upload queue and Firebase Storage/Firestore registration. It uploads bundle files, holds `capture_upload_complete.json` until the end, registers capture lifecycle/submission state, records failures, and classifies retry/permanent errors.
- `BlueprintCapture/Services/UploadQueueStore.swift` and `BlueprintCapture/ViewModels/UploadQueueViewModel.swift`: local upload queue persistence and UI state.
- `BlueprintCapture/Views/Components/UploadProgressOverlayView.swift`: upload progress UI.

Uploading a raw bundle can make evidence available to the bridge. It is not proof that hosted review, buyer access, payout, provider status, or city launch is ready.

### Launch gating and discovery

- `BlueprintCapture/LaunchCityGateView.swift`: iOS launch-city gate UI.
- `BlueprintCapture/Services/LaunchCityGateService.swift`: backend-backed launch-city status resolution.
- `BlueprintCapture/Views/Scan/ScanHomeView.swift`: scan home, nearby/current-location capture entry, task rows, glasses entry, and open-capture surfaces.
- `BlueprintCapture/ViewModels/ScanHomeViewModel.swift`: scan feed state and nearby/job resolution.
- `BlueprintCapture/Services/NearbyProxyBackendService.swift`, `PlacesAutocompleteService.swift`, `PlacesDetailsService.swift`, and related discovery services: place/search and nearby discovery helpers.

Launch gating tells the app whether a user should see capture access in the current context. It does not certify downstream launch readiness unless the release/proof validators and downstream artifacts agree.

### Wallet and payouts

- `BlueprintCapture/Views/Wallet/WalletView.swift`: iOS wallet and ledger UI.
- `BlueprintCapture/ViewModels/WalletViewModel.swift`: wallet/profile state for balances, capture history, payout banners, and refresh.
- `BlueprintCapture/StripeOnboardingView.swift` and `BlueprintCapture/Services/StripeConnectService.swift`: payout-provider UI and backend API client.
- `BlueprintCapture/Models/PayoutVerificationSummary.swift` and `SkuPricing.swift`: payout state and local heuristic pricing support.

Wallet state and local pricing heuristics are not public compensation policy. Use backend-quoted payout values and provider-ready proof before presenting live payout readiness.

### Profile and referrals

- `BlueprintCapture/Views/Profile/ProfileTabView.swift`: iOS profile, level, achievements, referral, and device summary UI.
- `BlueprintCapture/ViewModels/ReferralViewModel.swift`, `Services/ReferralService.swift`, and `Services/PendingReferralStore.swift`: referral client state.
- `BlueprintCapture/Services/UserDeviceService.swift`: device registration and related user state.

Referral rewards remain review/provider gated. Do not imply instant, guaranteed, or public reward availability from client UI alone.

### Glasses

- `BlueprintCapture/GlassesCaptureManager.swift`: iOS Meta glasses manager, MWDAT/mock setup, device discovery, streaming, video writing, motion logging, companion-phone AR tracking, manifest writing, and package creation.
- `BlueprintCapture/GlassesCaptureView.swift` and `BlueprintCapture/Views/Scan/GlassesConnectSheet.swift`: iOS glasses UI.

Smart glasses are an internal or supported-path capture modality unless there is physical-device proof plus Pipeline/WebApp proof for the same capture/job chain.

## Android App Map

### App shell

- `android/app/src/main/kotlin/app/blueprint/capture/MainActivity.kt`: Android activity entry.
- `android/app/src/main/kotlin/app/blueprint/capture/BlueprintCaptureApplication.kt`: Hilt application entry.
- `android/app/src/main/kotlin/app/blueprint/capture/ui/BlueprintCaptureRoot.kt`: Compose root, tab shell, upload overlay, and capture session routing.
- `android/app/src/main/kotlin/app/blueprint/capture/ui/BlueprintCaptureRootViewModel.kt`: onboarding/auth/permissions/glasses-stage resolution, selected tab, active capture, and upload queue state.

### Auth

- `android/app/src/main/kotlin/app/blueprint/capture/ui/screens/AuthScreen.kt` and `AuthViewModel.kt`: sign-in/sign-up/Google auth UI and state.
- `android/app/src/main/kotlin/app/blueprint/capture/data/auth/AuthRepository.kt`: Firebase auth, profile bootstrap, referral-code helpers, and auth state.

Auth copy should stay alpha-safe: track capture reviews and eligible payouts, not guaranteed paid work.

### Onboarding

- `android/app/src/main/kotlin/app/blueprint/capture/ui/screens/OnboardingScreen.kt`: onboarding stage router.
- `OnboardingWalkthroughScreen.kt`: capture walkthrough and device capability framing.
- `OnboardingGlassesScreen.kt`: optional glasses setup entry.
- `PermissionsScreen.kt` and `InviteCodeScreen.kt`: permission and invite-code gates.
- `android/app/src/main/kotlin/app/blueprint/capture/data/permissions/StartupPermissionChecker.kt`: startup permission checks.

Onboarding should explain what the app can help capture. It must not imply public launch readiness, live payout readiness, or provider readiness from setup completion alone.

### Scan and discovery

- `android/app/src/main/kotlin/app/blueprint/capture/ui/screens/ScanScreen.kt`: scan feed, search/submit flow, target detail surface, capture method picker, rights acknowledgement, and glasses entry.
- `ScanViewModel.kt`: feed/search state and capture launch resolution.
- `android/app/src/main/kotlin/app/blueprint/capture/data/targets/ScanTargetsRepository.kt`: target/job feed loading and mock-fallback boundaries.
- `android/app/src/main/kotlin/app/blueprint/capture/data/places/PlacesRepository.kt`: places autocomplete/details through backend proxy.
- `android/app/src/main/kotlin/app/blueprint/capture/data/opportunities/DemandIntelligenceBackendApi.kt`: demand/opportunity backend client.

Open-capture and nearby discovery are not approved marketplace jobs. Keep rights acknowledgement and review-gated state explicit.

### Capture

- `android/app/src/main/kotlin/app/blueprint/capture/ui/screens/CaptureSessionScreen.kt`: CameraX/ARCore recording surface, permissions, recording lifecycle, IMU flush, post-capture review, export/share, and upload actions.
- `CaptureSessionViewModel.kt`: post-recording state, site-world workflow state, bundle preparation, IMU sampling, upload/export commands.
- `android/app/src/main/kotlin/app/blueprint/capture/data/capture/ARCoreCaptureManager.kt` and `ARCoreEvidenceRecorder.kt`: ARCore evidence capture.
- `AndroidCaptureBundleBuilder.kt`: Android raw-bundle writer for phone, Android XR, and glasses capture sources.
- `CaptureContracts.kt`: Android capture models and contract structures.

Android capture can produce canonical bundles, but Android remains internal-only until Android release config, build, device/App Distribution smoke, and downstream proof are explicitly satisfied.

### Upload

- `android/app/src/main/kotlin/app/blueprint/capture/data/capture/CaptureUploadRepository.kt`: Android upload queue, WorkManager scheduling, Firebase Storage upload, completion-marker ordering, capture lifecycle registration, and submission registration.
- `CaptureUploadWorker.kt`: WorkManager worker entry.
- `CaptureUploadNotifications.kt`: foreground upload notification support.
- `android/app/src/main/kotlin/app/blueprint/capture/ui/components/UploadQueueOverlay.kt`: upload queue UI.

The completion marker triggers bridge processing after raw files are uploaded. Do not move it earlier unless contract tests cover the change.

### Wallet and profile

- `android/app/src/main/kotlin/app/blueprint/capture/ui/screens/WalletScreen.kt` and `WalletViewModel.kt`: Android wallet, ledger, payout history, and payout banner state.
- `ProfileScreen.kt` and `ProfileViewModel.kt`: contributor profile, settings entry, referral/device surfaces.
- `android/app/src/main/kotlin/app/blueprint/capture/data/profile/ContributorProfileRepository.kt`: Firestore profile source.
- `CaptureHistoryRepository.kt`: capture submission history.

Wallet displays review/provider-gated state. It should not invent live provider or guaranteed payout claims.

### Glasses

- `android/app/src/main/kotlin/app/blueprint/capture/data/glasses/GlassesCaptureManager.kt`: Android glasses streaming/session lifecycle, frame capture, artifact packaging, companion-phone sidecars, and mock/stub boundaries.
- `GlassesConnectionSheet.kt`, `GlassesViewModel.kt`, and `AndroidXrViewModel.kt`: glasses and Android XR UI/state.
- `android/app/src/metaStub/`: stubbed Meta wearable classes used when real SDK wiring is unavailable.

Keep mock/stub modes dev-only and explicit. Public claims require real hardware proof plus downstream proof.

### Launch gating

- `android/app/src/main/kotlin/app/blueprint/capture/ui/screens/LaunchCityGateScreen.kt`: Android launch-city gate UI and view model.
- `android/app/src/main/kotlin/app/blueprint/capture/data/launch/LaunchCityRepository.kt`: backend launch status client.
- `android/app/src/main/kotlin/app/blueprint/capture/data/launch/LaunchCityModels.kt`: launch city models.

Supported-city display is app access state, not launch-readiness proof for a city.

## Cloud Bridge Map

### `cloud/extract-frames`

- Source of truth for bridge source is `cloud/extract-frames/src/`. `dist/` is runtime/build output and should not be treated as the design authority.
- `src/index.ts`: Firebase Storage `onObjectFinalized` trigger. It accepts canonical `scenes/{scene}/captures/{capture_id}/raw/...` paths, waits for the completion marker, loads manifest/sidecars, validates identity and claimed artifacts, extracts frames with ffmpeg, writes keyframe/frame index, writes `capture_descriptor.json`, `qa_report.json`, and `pipeline_handoff.json`, and publishes to `blueprint-capture-pipeline-handoff`.
- `src/bridge.ts`: pose parsing, quality gate, claimed-vs-actual artifact evaluation, and capture-bundle references.
- `src/raw-contract-v3.ts`: bridge-side V3 validation helpers.

The bridge is a compatibility and materialization layer. It can downgrade or block derived lanes, but it must preserve raw capture truth and explicit blockers.

### `cloud/referral-earnings`

- Source of truth for function source is `cloud/referral-earnings/src/`.
- `src/index.ts`: mixed function entrypoint for referral earnings, capture lifecycle sync, capture status updates, demand/opportunity APIs, nearby/place proxies, and scheduled demand research.
- `src/demand-opportunities.ts`: demand signal scoring and capture-job annotation.
- `src/nearby-proxy.ts`: Places/Gemini-backed nearby/autocomplete/details proxy logic.
- `src/autonomous-demand-research.ts`: scheduled demand research support.

Referral and payout-related writes are external-service mutations. Local tests are safe; deployed functions and live HTTP calls are not safe verification unless explicitly requested with real credentials and proof intent.

## Cross-Repo Handoff

1. `BlueprintCapture` records evidence and writes a canonical raw bundle under `scenes/{scene_id}/captures/{capture_id}/raw/`.
2. The client uploads raw files and writes `capture_upload_complete.json` last.
3. `cloud/extract-frames` sees the completion marker or supported legacy trigger, validates raw/sidecar truth, extracts frames, builds descriptor and QA artifacts, and publishes a Pipeline handoff.
4. `BlueprintCapturePipeline` consumes the descriptor/handoff to materialize Task Evaluation Run artifacts, Post-Training Data Package artifacts, hosted artifacts, generated/model-derived support assets, and optional trust outputs.
5. `Blueprint-WebApp` is the buyer, licensing, ops, and hosted-review surface. WebApp and Pipeline decide downstream buyer/hosted/review state; Capture does not.

Missing upstream ids (`site_submission_id`, `buyer_request_id`, `capture_job_id`) are hosted-review and launch blockers. The raw capture can still be valid evidence while buyer access, payout, hosted review, and launch-ready claims remain blocked.

## Glossary

- Raw bundle: the first-party evidence package under `raw/`, including video, motion, camera/pose/depth sidecars, manifest, capture context, rights/provenance, hashes, and completion marker.
- Bridge: the cloud materialization layer that reads raw bundles, extracts frames, validates bridge quality, writes descriptor/QA/handoff artifacts, and notifies Pipeline.
- Provider readiness: proof that a provider integration or SDK is actually configured, reachable, and validated for the intended release path. Client config flags or UI presence are not enough.
- Payout readiness: proof that payout provider setup, backend state, eligibility, and disbursement rules are live and verified. Local wallet copy or heuristic pricing is not enough.
- Hosted-review blockers: missing upstream WebApp/request/job ids, missing Pipeline descriptor/QA/handoff, blocked rights/provenance, missing runtime artifacts, or any downstream proof gap that prevents buyer-facing hosted review.
- Launch readiness: cross-repo, release-config, device, upload, bridge, Pipeline, WebApp, monitoring, and provider proof for a real launch path. Capture completion alone is not launch readiness.
