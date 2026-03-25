# Next Session Master Prompt: BlueprintCapture Alpha Readiness

Use this prompt at the start of the next session.

---

You are working on `BlueprintCapture` and your goal is to get the app to true alpha readiness, not just improve docs.

Primary repo:

- `/Users/nijelhunt_1/workspace/BlueprintCapture`

Related repos:

- `/Users/nijelhunt_1/workspace/BlueprintCapturePipeline`
- `/Users/nijelhunt_1/workspace/Blueprint-WebApp`

Read these first:

- `/Users/nijelhunt_1/workspace/BlueprintCapture/PLATFORM_CONTEXT.md`
- `/Users/nijelhunt_1/workspace/BlueprintCapture/WORLD_MODEL_STRATEGY_CONTEXT.md`
- `/Users/nijelhunt_1/workspace/BlueprintCapture/docs/PRIVATE_ALPHA_READINESS.md`
- `/Users/nijelhunt_1/workspace/BlueprintCapture/docs/ALPHA_GO_NO_GO_CHECKLIST_2026-03-22.md`
- `/Users/nijelhunt_1/workspace/BlueprintCapture/README.md`
- `/Users/nijelhunt_1/workspace/Blueprint-WebApp/docs/alpha-launch-checklist.md`
- `/Users/nijelhunt_1/workspace/Blueprint-WebApp/docs/openclaw-deployment.md`
- `/Users/nijelhunt_1/workspace/Blueprint-WebApp/docs/ops-automation-analysis-2026.md`
- `/Users/nijelhunt_1/workspace/BlueprintCapturePipeline/scripts/run_external_alpha_launch_gate.py`

Platform context you must preserve:

- `BlueprintCapture` is the capture client and evidence collection tool.
- It is capture-first and world-model-product-first.
- The app owns capture coaching and truthful bundle creation.
- The app does not own final readiness decisions, rights/compliance interpretation, payout approval, or buyer-trust decisions.
- Downstream handoff to pipeline is required for alpha truth.

Current known status as of 2026-03-22:

- `BlueprintCapture` is not alpha-ready yet.
- `./scripts/alpha_readiness.sh` currently fails.
- the immediate blocker is a compile failure in:
  - `/Users/nijelhunt_1/workspace/BlueprintCapture/BlueprintCaptureTests/ScanHomeOpenCaptureTests.swift`
- exact failure:
  - non-`@MainActor` tests call main-actor-isolated APIs on `ScanHomeViewModel`
  - `ScanHomeViewModel` is `@MainActor`
  - `ScanHomeViewModel.nearbyItemsWithOpenCapture(...)` is actor-isolated
  - `ScanHomeViewModel.alphaCurrentLocationJobID` is actor-isolated
- the same issue also causes the cross-repo external alpha gate to fail

Relevant code references:

- `/Users/nijelhunt_1/workspace/BlueprintCapture/BlueprintCapture/ViewModels/ScanHomeViewModel.swift`
- `/Users/nijelhunt_1/workspace/BlueprintCapture/BlueprintCaptureTests/ScanHomeOpenCaptureTests.swift`
- `/Users/nijelhunt_1/workspace/BlueprintCapture/BlueprintCapture/Services/CaptureUploadService.swift`
- `/Users/nijelhunt_1/workspace/BlueprintCapture/cloud/extract-frames/src/index.ts`
- `/Users/nijelhunt_1/workspace/BlueprintCapture/BlueprintCapture/Services/PushNotificationManager.swift`
- `/Users/nijelhunt_1/workspace/BlueprintCapture/BlueprintCapture/Support/RuntimeConfig.swift`

Important implementation truths already verified:

- upload completion is fail-closed in the app:
  - upload is not considered complete unless `capture_submissions/{captureId}` is written
- cloud bridge tests are passing
- cloud bridge emits `capture_descriptor.json`, `qa_report.json`, and `pipeline_handoff.json`, then publishes the pipeline handoff topic
- release config checks in `scripts/alpha_readiness.sh` enforce:
  - no `Secrets*.plist` in bundle
  - no bundled Places/Gemini/provider keys
  - `BLUEPRINT_ALLOW_MOCK_JOBS_FALLBACK=NO`
  - `BLUEPRINT_ENABLE_INTERNAL_TEST_SPACE=NO`
  - `BLUEPRINT_ENABLE_REMOTE_NOTIFICATIONS=YES`
  - backend base URLs are set
  - nearby provider is `places_nearby`

What is still unproven and must be addressed:

1. Fix the current compile/test failure so `./scripts/alpha_readiness.sh` passes.
2. Rerun `./scripts/alpha_readiness.sh` and report exact results.
3. Rerun:
   - `python /Users/nijelhunt_1/workspace/BlueprintCapturePipeline/scripts/run_external_alpha_launch_gate.py`
4. Identify any additional red tests or release-bundle failures after the compile fix.
5. Verify whether the current UI/integration coverage is sufficient for alpha.
6. If coverage is not sufficient, add the smallest high-signal tests or scripts needed for alpha confidence.
7. Produce a concrete remaining manual smoke checklist for real-device verification.

Constraints and decision rules:

- Do not assume the app is ready just because cloud tests pass.
- Do not assume simulator coverage proves launch readiness.
- Do not move business-ops authority into the capture app.
- Do not treat OpenClaw as a capture-app runtime dependency unless the code actually requires it.
- Keep the capture app focused on truthful capture, upload, submission registration, and downstream handoff.
- Preserve fail-closed behavior.
- Do not weaken release gating just to make the checklist pass.

What I want from this session:

1. Fix the actual blocking compile/test issue.
2. Run the enforced launch gates.
3. Tell me exactly what is still red after the fix.
4. If there are additional blockers, categorize them as:
   - code blocker
   - release-config blocker
   - backend integration blocker
   - hardware/manual verification blocker
   - downstream pipeline blocker
5. Give me a final go/no-go answer based on the actual rerun results.

Success condition:

- I can trust the answer as the real alpha-readiness state of `BlueprintCapture`, with the next blockers listed in priority order.

---
