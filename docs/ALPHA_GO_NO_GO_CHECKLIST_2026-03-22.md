# BlueprintCapture Alpha Go / No-Go Checklist

Last updated: 2026-03-26

This checklist is the concrete launch gate for `BlueprintCapture`.

It is based on:

- the current app contract in `README.md`
- the current private alpha guide in `docs/PRIVATE_ALPHA_READINESS.md`
- the enforced launch script in `scripts/alpha_readiness.sh`
- the cross-repo launch gate in `BlueprintCapturePipeline/scripts/run_external_alpha_launch_gate.py`
- the current implementation state observed on 2026-03-22

## Rollout Scope On 2026-03-26

- External staged rollout remains iOS-only for the 10 -> 25 -> 100 tester ramp.
- Android now has a repo-local release validator (`./scripts/android_alpha_readiness.sh`) and release build lane, but it is still gated out of the external rollout until:
  - real release config is present locally
  - the validator passes
  - Firebase App Distribution release smoke is recorded on hardware

Release rule:

- Do not launch while `./scripts/alpha_readiness.sh` is red.
- Do not launch while `python /Users/nijelhunt_1/workspace/BlueprintCapturePipeline/scripts/run_external_alpha_launch_gate.py` is red.

## 1. Code Gate

- [ ] `./scripts/alpha_readiness.sh`
- [ ] `python /Users/nijelhunt_1/workspace/BlueprintCapturePipeline/scripts/run_external_alpha_launch_gate.py`

What `alpha_readiness.sh` must prove:

- boots the target simulator
- passes cloud bridge tests
- passes demand backend tests
- passes focused iOS unit tests
- passes focused iOS UI tests
- builds the Release app bundle
- verifies no forbidden secret packaging, forbidden release flags, or missing external support/legal config

Release rule:

- Do not launch while any compile, test, or release-bundle check in `alpha_readiness.sh` is failing.

## 2. Release Config Gate

These must be true in the real release/TestFlight config:

- [ ] `BLUEPRINT_BACKEND_BASE_URL` is set
- [ ] `BLUEPRINT_DEMAND_BACKEND_BASE_URL` is set
- [ ] `BLUEPRINT_MAIN_WEBSITE_URL` is set
- [ ] `BLUEPRINT_HELP_CENTER_URL` is set
- [ ] `BLUEPRINT_BUG_REPORT_URL` is set
- [ ] `BLUEPRINT_TERMS_OF_SERVICE_URL` is set
- [ ] `BLUEPRINT_PRIVACY_POLICY_URL` is set
- [ ] `BLUEPRINT_CAPTURE_POLICY_URL` is set
- [ ] `BLUEPRINT_ACCOUNT_DELETION_URL` is set
- [ ] `BLUEPRINT_SUPPORT_EMAIL_ADDRESS` is set
- [ ] `BLUEPRINT_NEARBY_DISCOVERY_PROVIDER=places_nearby`
- [ ] `BLUEPRINT_ALLOW_MOCK_JOBS_FALLBACK=NO`
- [ ] `BLUEPRINT_ENABLE_INTERNAL_TEST_SPACE=NO`
- [ ] `BLUEPRINT_ENABLE_REMOTE_NOTIFICATIONS=YES`
- [ ] `APS_ENVIRONMENT=production`
- [ ] `aps-environment` exists in `BlueprintCapture.entitlements`
- [ ] `GoogleService-Info.plist` is bundled correctly

Secrets and packaging constraints:

- [ ] `Secrets*.plist` is not bundled into the app
- [ ] Places keys are not bundled
- [ ] Gemini / Google AI keys are not bundled
- [ ] no live feature silently depends on bundled third-party provider keys

Release rule:

- Do not launch if the shipped app bundle contains secrets or provider keys.

## 3. Backend And Auth Gate

- [ ] Firebase Anonymous Auth is enabled for the active project
- [ ] guest launch establishes a Firebase-authenticated session before real upload
- [ ] Firestore access is valid for live discovery, claim, and upload flows
- [ ] creator notification/device routes are live if `BLUEPRINT_BACKEND_BASE_URL` is enabled
- [ ] demand backend proxy routes are live:
  - `POST /v1/nearby/discovery`
  - `POST /v1/places/autocomplete`
  - `POST /v1/places/details`

Release rule:

- Do not launch if the app only works with mock jobs, internal test space, or direct client provider keys.
- Run `./scripts/archive_external_alpha.sh --validate-config-only` before any city proof signoff.

## 4. Capture Flow Gate

These are the minimum truthful product flows for alpha:

- [ ] onboarding opens cleanly in a release-like build
- [ ] auth entry renders correctly
- [ ] scan home renders without fake/demo cards
- [ ] home feed loads live jobs and/or live nearby proxy results
- [ ] at least one approved job can open from scan home
- [ ] capture can start successfully
- [ ] capture can stop successfully
- [ ] upload overlay appears
- [ ] upload finishes successfully against live storage
- [ ] capture does not report success if submission registration fails

Implementation already supports fail-closed upload completion:

- raw upload success is not enough
- `capture_submissions/{captureId}` must also be written before completion is reported

Release rule:

- Do not launch unless at least one real approved-job capture reaches real upload completion end to end.

## 5. Pipeline Handoff Gate

The capture app is not launch-ready if downstream handoff is broken.

- [ ] uploaded bundle lands under canonical `scenes/{scene_id}/captures/{capture_id}/raw/...`
- [ ] `capture_upload_complete.json` is written
- [ ] cloud bridge emits:
  - `capture_descriptor.json`
  - `qa_report.json`
  - `pipeline_handoff.json`
- [ ] Pub/Sub handoff to `blueprint-capture-pipeline-handoff` succeeds
- [ ] downstream `BlueprintCapturePipeline` receives and processes the handoff

Cross-repo proof:

- [ ] external alpha gate passes from `BlueprintCapturePipeline/scripts/run_external_alpha_launch_gate.py`

Release rule:

- Do not launch if capture bundles upload but pipeline handoff is not proven live.

## 6. Notifications Gate

- [ ] APNs registration succeeds on hardware
- [ ] FCM token registration succeeds on hardware
- [ ] device registration sync to backend succeeds
- [ ] notification preferences sync succeeds
- [ ] remote notifications are enabled in the release build

Release rule:

- Do not launch if release/TestFlight builds ship with remote notifications disabled.

## 7. Wallet / Payout Gate

- [ ] wallet loads in a release-like build
- [ ] payout setup works through the backend, or
- [ ] the app shows the alpha-safe unavailable state truthfully

Important boundary:

- the app may surface payout state
- the app is not the authority for payout approval or funds movement

Release rule:

- Do not launch if payout UI implies readiness that the backend cannot actually support.

## 8. AI / Direct Provider Safety Gate

- [ ] capture upload/export flows fall back safely when AI intake is disabled
- [ ] recording-policy or intake AI features are either truly working or clearly disabled-for-alpha
- [ ] direct provider features are not accidentally required for the core capture path

Release rule:

- Do not launch if core capture success depends on direct AI/provider integrations that are not part of the alpha contract.

## 9. Hardware Manual Smoke Gate

Run these on a real device and record results:

- [ ] install release-like build
- [ ] cold launch
- [ ] onboarding/auth path
- [ ] live feed load
- [ ] approved job open
- [ ] start capture
- [ ] stop capture
- [ ] upload completes
- [ ] `capture_submissions/{captureId}` exists
- [ ] bridge artifacts appear in storage
- [ ] APNs + FCM registration succeeds
- [ ] wallet state is truthful
- [ ] support/legal links open the correct public pages or support mailbox
- [ ] in-app or support-routed account deletion path is reachable

Release rule:

- Do not launch on simulator evidence alone.

## 10. Monitoring And Ops Gate

Even if the app ships, it is not zero-touch.

Required launch-week ownership:

- [ ] someone watches failed uploads / submission registration failures
- [ ] someone watches push/device sync failures
- [ ] someone watches bridge/pipeline handoff failures
- [ ] someone watches payout-related exceptions downstream
- [ ] someone watches launch logs daily during the first week
- [ ] Firebase Analytics `blueprint_ops_event` and `blueprint_ops_error` are visible to the launch owner
- [ ] Firestore `sessionEvents` operational failures are queryable
- [ ] Cloud Logging alerts or saved queries exist for `Pipeline handoff publish failed`

Operational truth:

- `BlueprintCapture` automates upload and handoff
- downstream business ops, payout review, rights/privacy interpretation, and buyer-commitment decisions still remain human-supervised

## 11. Go / No-Go Rule

Go only when all of these are true:

- `./scripts/alpha_readiness.sh` passes
- `./scripts/launch_city_readiness.sh` passes with a real city proof artifact, not `ops/launch-readiness/example.launch-proof.json`
- cross-repo external alpha gate passes
- release bundle contains no secrets or provider keys
- live auth + live discovery + real approved-job capture flow works
- upload writes `capture_submissions/{captureId}` successfully
- bridge emits descriptor / QA / handoff artifacts successfully
- push registration works on hardware
- wallet/payout state is truthful
- launch-week monitoring ownership is assigned

If any one of those is false, the launch is not ready.
