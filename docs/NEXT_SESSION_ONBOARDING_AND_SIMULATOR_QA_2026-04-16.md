# Next Session Master Prompt

You are continuing work on the native iOS app in:

`/Users/nijelhunt_1/paperclip-clean-session`

The app target is `BlueprintCapture`, and the Xcode project is:

`/Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture.xcodeproj`

Your job in this session is to fix 4 onboarding/capture UX bugs that were reproduced in the iOS Simulator, then re-test those exact flows in the simulator after the fixes.

Do not restart from scratch. Use the context below.

## Repo and platform context

- This repo is the iOS capture client.
- The relevant product framing is in:
  - `/Users/nijelhunt_1/paperclip-clean-session/AGENTS.md`
  - `/Users/nijelhunt_1/paperclip-clean-session/PLATFORM_CONTEXT.md`
- This checkout is a worktree. The `.git` file points to:
  - `/Users/nijelhunt_1/workspace/BlueprintCapture/.git/worktrees/paperclip-clean-session`

## Important state already established

The Xcode/package-resolution issue from the prior session was fixed by making the project use workspace-relative DerivedData instead of stale global DerivedData state.

This shared workspace settings file now matters:

- `/Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture.xcodeproj/project.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings`

It contains:

- `DerivedDataLocationStyle = WorkspaceRelativePath`
- `DerivedDataCustomLocation = DerivedData`
- `BuildLocationStyle = UseAppPreferences`

Do not remove or overwrite that fix casually.

## Verified build command

This command was verified and ended with `** BUILD SUCCEEDED **`:

```bash
xcodebuild \
  -project /Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture.xcodeproj \
  -scheme BlueprintCapture \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /Users/nijelhunt_1/paperclip-clean-session/DerivedData \
  -clonedSourcePackagesDirPath /Users/nijelhunt_1/paperclip-clean-session/DerivedData/SourcePackages \
  -packageCachePath /Users/nijelhunt_1/paperclip-clean-session/DerivedData/PackageCache \
  -disableAutomaticPackageResolution \
  -onlyUsePackageVersionsFromResolvedFile \
  -skipPackageUpdates \
  build
```

The built app bundle exists at:

`/Users/nijelhunt_1/paperclip-clean-session/DerivedData/Build/Products/Debug-iphonesimulator/BlueprintCapture.app`

## Simulator notes

- The app was tested in `iPhone 17 Pro` simulator.
- The simulator onboarding flow was manually exercised.
- Computer Use accessibility snapshots sometimes lagged one screen behind the live rendered frame. If using desktop automation again, verify against the visible frame, not only the accessibility tree.
- `xcodebuildmcp` simulator helpers required session defaults and were not fully relied on. Direct simulator launch/install via `simctl` worked.

Helpful commands:

```bash
xcrun simctl install booted /Users/nijelhunt_1/paperclip-clean-session/DerivedData/Build/Products/Debug-iphonesimulator/BlueprintCapture.app
xcrun simctl launch booted Public.BlueprintCapture
```

## Flows already reproduced

### Onboarding path used

1. Launch app
2. Welcome
3. Tap `Get Started`
4. Auth screen appears
5. Skip auth
6. Invite screen appears
7. Skip invite
8. Permissions screen
9. Accept permission dialogs in simulator
10. Continue through device/tutorial/glasses flow
11. Land on home screen

### Main screen path also tested

1. From home screen, tap `Submit a new space`
2. `Submit a Space` sheet appears
3. Location fetch can fail and display raw Core Location text

## Bugs to fix

### 1. Permission onboarding false-negative race

Observed behavior:

- I granted camera, location, and notifications.
- The app still showed `Permissions Required`.
- It only progressed after `Continue Anyway`.
- A moment later, the state corrected itself and all permissions showed granted.

Likely cause:

- The onboarding permission flow checks location permission too early, immediately after calling `requestWhenInUseAuthorization()`, instead of waiting for the authorization callback/state refresh.

Primary file references:

- `/Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture/OnboardingFlowView.swift:716`
- `/Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture/OnboardingFlowView.swift:721`
- `/Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture/OnboardingFlowView.swift:728`

Relevant code area:

- `OnboardingPermissionsView.enableAll()`

Goal:

- After granting the required permissions, onboarding should continue automatically without surfacing the false `Permissions Required` alert.

Acceptance criteria:

- If camera, location, and motion are granted during the permission flow, the user should advance directly.
- The fallback alert should only appear when permissions are truly still missing.

### 2. Auth step triggers pasteboard privacy prompt too early

Observed behavior:

- As soon as the onboarding auth screen appeared, iOS showed a pasteboard prompt:
  - `"BlueprintCapture" would like to paste from "CoreSimulatorBridge"`
- The user had not tapped any paste-related action.

Likely cause:

- The auth view reads `UIPasteboard.general.string` on screen load via `.task`.

Primary file references:

- `/Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture/ViewModels/AuthViewModel.swift:125`
- `/Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture/ViewModels/AuthViewModel.swift:127`
- `/Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture/OnboardingFlowView.swift:482`

Relevant code area:

- `AuthViewModel.consumePasteboardReferralIfNeeded()`
- `.task { vm.consumePasteboardReferralIfNeeded() }`

Goal:

- Do not trigger an iOS pasteboard privacy prompt just by entering the auth screen.

Acceptance criteria:

- Entering the auth step should not prompt for pasteboard access.
- Referral/deep-link handling should still work through existing non-pasteboard paths.
- If pasteboard fallback is still desired, make it explicit and user-initiated.

### 3. Onboarding copy contradicts home screen glasses requirement

Observed behavior:

- Onboarding glasses step says pairing glasses is optional and offers:
  - `Skip — Use iPhone Only`
- Completion screen says:
  - `You're All Set`
- First post-onboarding home screen then says glasses are:
  - `Required for approved capture opportunities.`

This is contradictory and misleading.

Primary file references:

- `/Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture/OnboardingFlowView.swift:761`
- `/Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture/OnboardingFlowView.swift:779`
- `/Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture/OnboardingFlowView.swift:825`
- `/Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture/Views/Scan/ScanHomeView.swift:582`

Goal:

- Make the onboarding and post-onboarding messaging consistent.

Questions to resolve in code:

- Are glasses truly optional for at least some capture paths?
- If yes, the home screen copy should stop calling them required.
- If no, the onboarding flow should stop presenting skip as an equivalent completion path and should not say `You're All Set`.

Acceptance criteria:

- A user who skips glasses should see copy that matches the actual allowed capture capabilities.
- No screen should imply “fully ready” if the app will immediately block or contradict that state.

### 4. `Submit a Space` shows raw Core Location error text

Observed behavior:

- In `Submit a Space`, the location area displayed:
  - `The operation couldn’t be completed. (kCLErrorDomain error 0.)`

That is not acceptable user-facing copy.

Primary file references:

- `/Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture/CaptureFlowViewModel.swift:1339`
- `/Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture/CaptureFlowViewModel.swift:1340`
- `/Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture/LocationConfirmationView.swift:128`

Goal:

- Replace raw Core Location/internal error text with useful, human-readable guidance.

Acceptance criteria:

- Users should see plain-language copy such as inability to determine location, retry suggestion, or manual address entry guidance.
- Internal system-domain error strings should not appear in the UI.

## Recommended implementation order

1. Fix the permission race first.
2. Fix the pasteboard prompt second.
3. Align glasses copy and readiness messaging third.
4. Replace raw location error surfacing fourth.
5. Rebuild.
6. Re-test in simulator.

## Re-test checklist for after fixes

After making code changes, rebuild with the verified command above, then re-test these flows in simulator:

### Re-test 1: onboarding permission flow

1. Fresh install / reset onboarding state if needed.
2. Launch app.
3. `Get Started`
4. Skip auth.
5. Skip invite.
6. Tap `Enable`.
7. Grant camera.
8. Grant location.
9. Grant notifications.
10. Verify the app advances automatically without showing the false `Permissions Required` alert.

### Re-test 2: auth screen pasteboard behavior

1. Fresh install / relaunch if needed.
2. Enter auth screen again.
3. Verify no pasteboard privacy prompt appears just from landing on the screen.

### Re-test 3: glasses copy consistency

1. Continue onboarding with `Skip — Use iPhone Only`.
2. Reach completion.
3. Tap `Start Capturing`.
4. Verify the first post-onboarding screen does not contradict the skipped-glasses path.

### Re-test 4: submit-a-space location error UX

1. From home screen, tap `Submit a new space`.
2. Let location detection fail in simulator if it still does.
3. Verify the UI shows human-friendly copy rather than raw `kCLErrorDomain` text.

## Output expected from the next session

The next session should provide:

1. A concise summary of the code changes made.
2. The exact files changed.
3. The verification command run.
4. Re-test results for each of the 4 bugs.
5. Any remaining simulator-only limitations vs real-device limitations.

## Extra caution

- Do not re-break the workspace-relative DerivedData/package resolution fix.
- Do not trust Xcode’s stale Issue Navigator from the prior broken state; verify using fresh builds and simulator behavior.
- Prefer user-facing behavior fixes over papering over symptoms.
