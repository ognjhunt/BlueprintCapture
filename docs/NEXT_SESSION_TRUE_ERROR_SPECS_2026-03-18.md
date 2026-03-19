# Next Session: True Error Specs

Date captured: March 18, 2026
Platform: iOS device
App state: phone capture flow, upload UX fixed, backend/auth setup still incomplete

## Purpose

This document isolates the real failures still present in the March 18, 2026 device logs after the upload UX fix landed. It is intended to let the next session start from concrete evidence instead of re-triaging noisy ARKit / RealityKit / Firebase console output.

The main conclusion is:

- Raw capture upload to Firebase Storage is succeeding.
- Firestore-backed app flows are still partially broken because Firebase Authentication is not established for guest users.
- Push/device-registration backend plumbing is also not fully configured.

## Confirmed non-failures

These showed up in the logs but are not the primary blockers for the capture submission pipeline:

- `✅ [UploadService] Directory upload completed ...`
- `📤 [Upload] completed ...`
- `Fig... err=-12710 / -12784 / -17281`
- `Attempting to enable an already-enabled session. Ignoring...`
- RealityKit `rematerial` / passthrough / texture allocator warnings
- `nw_path_necp_check_for_updates Failed to copy updated result (22)`
- `WatchStream ... Disconnecting idle stream. Timed out waiting for new targets.`
- `Skipping integration due to poor slam ...`

Those may still deserve cleanup, but they are not the reason the workflow remains backend-incomplete.

## True error list

### 1. Firebase anonymous auth is disabled, so guest Firestore access never becomes authenticated

Observed log lines:

- `⚠️ [Auth] Anonymous sign-in failed: This operation is restricted to administrators only.`

Relevant code:

- [`AppDelegate.swift`](/Users/nijelhunt_1/workspace/BlueprintCapture/BlueprintCapture/AppDelegate.swift)
- [`UserDeviceService.swift`](/Users/nijelhunt_1/workspace/BlueprintCapture/BlueprintCapture/Services/UserDeviceService.swift)
- [`firestore.rules`](/Users/nijelhunt_1/workspace/BlueprintCapture/firestore.rules)

Current flow:

1. App launch calls `UserDeviceService.ensureAnonymousFirebaseUserIfNeeded(...)`.
2. That calls `Auth.auth().signInAnonymously`.
3. Firebase rejects the call because Anonymous Auth is disabled or restricted in the Firebase project.
4. The app falls back to its local temp user only.
5. Firestore rules still require `request.auth != null` for key collections.

Why this matters:

- Any rule guarded by `isSignedIn()` fails for guest users.
- That directly causes the `capture_jobs` permission denial.
- It also causes `capture_submissions` writes to be skipped.
- Older `sessions` / `sessionEvents` writes will also fail if they depend on Firebase auth.

Current rules context:

- `capture_jobs` requires signed-in read.
- `capture_submissions` requires signed-in read and owner create.
- `sessions` and `sessionEvents` require signed-in access.

Spec decision required next session:

- Option A: enable Firebase Anonymous Auth and keep guest flow.
- Option B: require real sign-in before any Firestore-backed capture flow.

Recommended path:

- Enable Anonymous Auth first, because the app is already architected around guest capture and local temp users.

Acceptance criteria:

- Launching the app on device no longer logs `Anonymous sign-in failed`.
- `Auth.auth().currentUser` is non-nil for guest users.
- Firestore reads for `capture_jobs` no longer fail with permission denied.
- `capture_submissions` write path can proceed past the auth guard.

Open questions:

- Is Anonymous Auth disabled entirely in Firebase Auth, or blocked by project policy / App Check / Identity Platform settings?
- Are there any environment-specific Firebase projects where guest auth should remain disabled?

### 2. `capture_jobs` Firestore reads are failing under current rules

Observed log lines:

- `[FirebaseFirestore][I-FST000001] Listen for query at capture_jobs failed: Missing or insufficient permissions.`

Relevant code:

- [`JobsRepository.swift`](/Users/nijelhunt_1/workspace/BlueprintCapture/BlueprintCapture/Services/JobsRepository.swift)
- [`firestore.rules`](/Users/nijelhunt_1/workspace/BlueprintCapture/firestore.rules)

What the app does today:

- `JobsRepository.fetchActiveJobs()` queries `capture_jobs` with `whereField("active", isEqualTo: true)`.
- If Firestore returns permission denied (`FIRFirestoreErrorDomain`, code `7`), the repository silently returns `mockJobs()`.

Why this matters:

- The feed can look functional because mock jobs mask the permission failure.
- That can make the app appear healthy even when the production job feed is unavailable.

Probable root cause:

- Cascading effect from issue 1: no Firebase-authenticated user, but rules require signed-in reads.

Next-session tasks:

- Verify whether the denial disappears once Anonymous Auth is enabled.
- Decide whether the mock fallback should remain in production builds or only in explicitly flagged alpha/dev modes.
- Improve logging/UI so a production feed permission failure is not silently hidden.

Acceptance criteria:

- Real Firestore `capture_jobs` reads succeed for the guest flow.
- The scan feed loads real jobs without relying on `mockJobs()`.
- If the backend feed truly fails, the app surfaces a controlled alpha-safe error state instead of silently substituting fake data.

### 3. `capture_submissions` is not being written after upload because Firebase auth is unavailable

Observed log lines:

- `ℹ️ [UploadService] Skipping capture_submissions write until Firebase auth is available`

Relevant code:

- [`CaptureUploadService.swift`](/Users/nijelhunt_1/workspace/BlueprintCapture/BlueprintCapture/Services/CaptureUploadService.swift)
- [`firestore.rules`](/Users/nijelhunt_1/workspace/BlueprintCapture/firestore.rules)
- Cloud function listeners under `cloud/`

Current behavior:

- After Storage upload completes, `CaptureUploadService.writeSubmissionRecord(for:)` checks `Auth.auth().currentUser`.
- If no Firebase user exists, it logs the skip and does not create `capture_submissions/{captureId}`.

Why this matters:

- The raw bundle exists in Firebase Storage.
- But downstream systems that watch `capture_submissions` may never see the upload.
- This leaves the pipeline in a partial-success state.

Important note:

- Your current Firestore rules already allow `capture_submissions` create for the authenticated owner.
- The missing prerequisite is auth, not a missing rule branch.

Next-session tasks:

- Fix issue 1 first.
- Then validate that `capture_submissions/{captureId}` is written after upload completion.
- Confirm any downstream Cloud Functions or review workflows observe the document as expected.

Acceptance criteria:

- Device log shows `capture_submissions/... written`.
- Firestore contains the expected document with `creator_id`, `scene_id`, and timestamps.
- End-to-end workflow advances from upload to submission/review without manual intervention.

### 4. Push registration is not configured correctly for this build

Observed log lines:

- `[FirebaseMessaging][I-FCM012002] Error in application:didFailToRegisterForRemoteNotificationsWithError: no valid “aps-environment” entitlement string found for application`
- `⚠️ [Notifications] APNs registration failed: ...`

Relevant code:

- [`AppDelegate.swift`](/Users/nijelhunt_1/workspace/BlueprintCapture/BlueprintCapture/AppDelegate.swift)
- [`PushNotificationManager.swift`](/Users/nijelhunt_1/workspace/BlueprintCapture/BlueprintCapture/Services/PushNotificationManager.swift)
- [`BlueprintCapture.entitlements`](/Users/nijelhunt_1/workspace/BlueprintCapture/BlueprintCapture/BlueprintCapture.entitlements)
- [`project.pbxproj`](/Users/nijelhunt_1/workspace/BlueprintCapture/BlueprintCapture.xcodeproj/project.pbxproj)

Current state:

- The project points to `BlueprintCapture.entitlements`.
- That entitlements file is currently empty.
- `PushNotificationManager` requests notification authorization and registers for remote notifications.
- APNs registration fails because the built app has no `aps-environment` entitlement.

Why this matters:

- APNs device token registration will never complete.
- FCM/APNs token bridging is incomplete.
- Push-based nearby job / account / payout notifications cannot work reliably.

Next-session tasks:

- Add the Push Notifications capability in Xcode / Apple Developer configuration.
- Ensure the provisioning profile includes APS entitlements for the correct bundle ID.
- Verify the generated entitlements contain `aps-environment`.
- Confirm `didRegisterForRemoteNotificationsWithDeviceToken` is called on device.

Acceptance criteria:

- No more `aps-environment` entitlement error on launch.
- Device obtains APNs token successfully.
- FCM token + APNs token registration path completes without APNs entitlement failure.

### 5. Notification device sync and preference refresh are failing against the backend

Observed log lines:

- `⚠️ [Notifications] Failed to sync device registration: The operation couldn’t be completed. (BlueprintCapture.APIService.APIError error 1.)`
- `⚠️ [Notifications] Failed to refresh preferences: The operation couldn’t be completed. (BlueprintCapture.APIService.APIError error 1.)`

Relevant code:

- [`PushNotificationManager.swift`](/Users/nijelhunt_1/workspace/BlueprintCapture/BlueprintCapture/Services/PushNotificationManager.swift)
- [`NotificationPreferencesStore.swift`](/Users/nijelhunt_1/workspace/BlueprintCapture/BlueprintCapture/Support/NotificationPreferencesStore.swift)
- [`APIService.swift`](/Users/nijelhunt_1/workspace/BlueprintCapture/BlueprintCapture/Services/APIService.swift)
- [`RuntimeConfig.swift`](/Users/nijelhunt_1/workspace/BlueprintCapture/BlueprintCapture/Support/RuntimeConfig.swift)
- [`ConfigTemplates/BlueprintCapture.local.xcconfig.example`](/Users/nijelhunt_1/workspace/BlueprintCapture/ConfigTemplates/BlueprintCapture.local.xcconfig.example)
- [`PRIVATE_ALPHA_READINESS.md`](/Users/nijelhunt_1/workspace/BlueprintCapture/docs/PRIVATE_ALPHA_READINESS.md)

Likely causes:

- `BLUEPRINT_BACKEND_BASE_URL` is not set for the active build, which would trigger `APIError.missingBaseURL`.
- Or the backend URL is set but the endpoint returns a non-2xx response, which would trigger `APIError.invalidResponse(statusCode:)`.

Current debugging problem:

- `APIService.APIError` does not currently implement a useful `LocalizedError` description.
- The log only shows `APIError error 1`, which is not enough to distinguish missing base URL from a bad HTTP status.

Why this matters:

- Even after APNs/auth are fixed, notification registration and preference sync may still fail silently.
- This also suggests other backend-dependent surfaces could be misconfigured for the active local build.

Next-session tasks:

- Confirm whether `BLUEPRINT_BACKEND_BASE_URL` is set in the active device build.
- Improve `APIService.APIError` logging so it prints either `missingBaseURL` or the actual HTTP status code.
- Re-run notification sync after fixing APNs/auth.

Acceptance criteria:

- Device logs show a concrete, non-generic outcome for notification sync.
- `registerNotificationDevice` succeeds against the configured backend.
- `fetchNotificationPreferences` either succeeds or returns an explicit actionable backend error.

### 6. `default.csv` resource lookup is failing, but the source is not yet identified

Observed log lines:

- `Failed to locate resource named "default.csv"`

Current evidence:

- There is no `default.csv` reference in app source under the workspace.
- There is no `default.csv` file in the checked-out Swift packages searched from DerivedData.
- The emitting subsystem is not obvious from the current console output.

What this means:

- This is a real missing-resource log.
- But it currently looks like an external SDK or runtime-side lookup, not a direct app-code reference.

Spec classification:

- Investigate next session, but treat as lower priority than auth / Firestore / APNs unless it correlates with a user-visible failure.

Next-session tasks:

- Capture the subsystem / stack trace if possible when `default.csv` is logged.
- Check whether it originates from Meta Wearables SDK, RealityKit, or another bundled framework.
- Inspect built app resources and embedded framework resources, not just source files.

Acceptance criteria:

- Either identify the owning framework and bundle the required resource,
- Or prove the message is benign and document it as ignorable runtime noise.

## Recommended execution order for next session

1. Fix Firebase Anonymous Auth.
2. Re-test Firestore `capture_jobs` read and `capture_submissions` write.
3. Fix APNs entitlements and confirm token registration.
4. Fix backend notification sync observability and base URL / status reporting.
5. Investigate `default.csv` once the hard blockers above are resolved.

## Manual validation checklist after fixes

- Launch app on device.
- Confirm no anonymous auth failure is logged.
- Confirm `capture_jobs` reads do not log permission denied.
- Run a phone capture and upload.
- Confirm `capture_submissions/... written` appears after upload completion.
- Confirm APNs registration succeeds without entitlement errors.
- Confirm notification device sync and preference fetch succeed with actionable logs.

## Code touchpoints summary

- Auth bootstrap:
  [`UserDeviceService.swift`](/Users/nijelhunt_1/workspace/BlueprintCapture/BlueprintCapture/Services/UserDeviceService.swift)
  [`AppDelegate.swift`](/Users/nijelhunt_1/workspace/BlueprintCapture/BlueprintCapture/AppDelegate.swift)

- Firestore read/write rules:
  [`firestore.rules`](/Users/nijelhunt_1/workspace/BlueprintCapture/firestore.rules)
  [`JobsRepository.swift`](/Users/nijelhunt_1/workspace/BlueprintCapture/BlueprintCapture/Services/JobsRepository.swift)
  [`CaptureUploadService.swift`](/Users/nijelhunt_1/workspace/BlueprintCapture/BlueprintCapture/Services/CaptureUploadService.swift)

- Push/device registration:
  [`PushNotificationManager.swift`](/Users/nijelhunt_1/workspace/BlueprintCapture/BlueprintCapture/Services/PushNotificationManager.swift)
  [`NotificationPreferencesStore.swift`](/Users/nijelhunt_1/workspace/BlueprintCapture/BlueprintCapture/Support/NotificationPreferencesStore.swift)
  [`BlueprintCapture.entitlements`](/Users/nijelhunt_1/workspace/BlueprintCapture/BlueprintCapture/BlueprintCapture.entitlements)

- Backend config:
  [`APIService.swift`](/Users/nijelhunt_1/workspace/BlueprintCapture/BlueprintCapture/Services/APIService.swift)
  [`RuntimeConfig.swift`](/Users/nijelhunt_1/workspace/BlueprintCapture/BlueprintCapture/Support/RuntimeConfig.swift)
  [`BlueprintCapture.local.xcconfig.example`](/Users/nijelhunt_1/workspace/BlueprintCapture/ConfigTemplates/BlueprintCapture.local.xcconfig.example)

## Known noise to ignore while debugging these issues

- Firebase Messaging swizzling notice:
  informational only unless you explicitly want manual integration.
- CoreMotion managed preferences permission warning:
  not the root cause of the submission pipeline issues.
- ARKit / RealityKit material and passthrough console spam:
  noisy, but not what is blocking upload registration.
