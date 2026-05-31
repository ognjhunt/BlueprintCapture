# Android Feature Parity: Current Implementation Status

Last reconciled: 2026-05-31

This document is a parity status note, not a public launch-readiness certificate.
It must stay aligned with the root capture doctrine:

- Capture truth and raw bundle integrity come before qualification.
- Generated, provider, payout, hosted-review, or downstream artifacts are not the same thing as
  captured evidence.
- Repo-local implementation status must stay separate from private SDK, hardware, release,
  payment, and live-backend proof.

## Current Summary

The previous version of this file described an old three-gap backlog. That is no longer accurate.
Two of those gaps are already addressed in the current Android code:

1. Contributor profile no longer silently falls back to a demo identity.
2. Wallet ledger tabs no longer rely on static mock rows for payouts/history.

The remaining Meta DAT / private-SDK glasses work is not a normal repo-local implementation gap.
The app now has a private-SDK-gated implementation path and a disabled-stub path, but real Meta
glasses proof still requires external inputs: GitHub Packages credentials, `MWDAT_ENABLE_PRIVATE_SDK`,
Meta hardware, Meta AI registration/permissions, and physical-device capture proof.

## Status Matrix

| Area | Repo-local status | Implementation evidence | Test / verification evidence | Claim ceiling |
|---|---|---|---|---|
| Contributor profile demo fallback | Complete. The repository fails closed to `null` for missing auth, Firestore listener errors, and missing user docs; missing profile fields become empty strings instead of demo identity values. | `android/app/src/main/kotlin/app/blueprint/capture/data/profile/ContributorProfileRepository.kt` - `observeProfile()` and `DocumentSnapshot.toContributorProfile()` | `rg -n "DemoData\\.contributorProfile|Alex Rivera" android/app/src/main/kotlin/app/blueprint/capture android/app/src/test` should return no profile fallback hits; `./gradlew testDebugUnitTest` must pass. | Android may show real Firestore-backed profile state or empty/null state only. Do not reintroduce demo contributor identity as a fallback. |
| Wallet payout/history ledger | Complete for capture history and paid-payout rows. Cashouts remain intentionally empty unless a real provider-backed cashout collection is wired. | `android/app/src/main/kotlin/app/blueprint/capture/ui/screens/WalletViewModel.kt` - injects `CaptureHistoryRepository`, loads history on init/refresh, derives `payoutEntries` from `CaptureSubmissionStage.Paid`; `android/app/src/main/kotlin/app/blueprint/capture/ui/screens/WalletScreen.kt` - `WalletLedgerContent()` renders loaded entries, loading state, and accurate empty states; `android/app/src/main/kotlin/app/blueprint/capture/data/capture/CaptureHistoryRepository.kt` - `fetchHistory()` reads `capture_submissions` for the current user. | `rg -n "payoutEntries|historyEntries|fetchHistory|delay\\(900\\)" android/app/src/main/kotlin/app/blueprint/capture/ui/screens/WalletViewModel.kt android/app/src/main/kotlin/app/blueprint/capture/ui/screens/WalletScreen.kt android/app/src/main/kotlin/app/blueprint/capture/data/capture/CaptureHistoryRepository.kt`; `./gradlew testDebugUnitTest` must pass. | Wallet history and paid rows can be treated as repository-backed UI. Cashout execution, provider onboarding, and payout settlement are not proven. |
| Meta DAT glasses private SDK | Implementation scaffold exists, but real private-SDK and hardware proof remain blocked externally. | `android/app/build.gradle.kts` - `MWDAT_ENABLE_PRIVATE_SDK` gates `BuildConfig.MWDAT_PRIVATE_SDK_ENABLED` and swaps in `src/metaStub/kotlin` when disabled; `android/settings.gradle.kts` - GitHub Packages repository expects `gpr.user` / `gpr.token`; `android/app/src/main/kotlin/app/blueprint/capture/BlueprintCaptureApplication.kt` - initializes `Wearables` only when the private SDK flag is enabled; `android/app/src/main/kotlin/app/blueprint/capture/ui/screens/GlassesViewModel.kt` - reports disabled private-SDK truth and routes authorized real devices through `GlassesCaptureManager`; `android/app/src/main/kotlin/app/blueprint/capture/data/glasses/GlassesCaptureManager.kt` - owns stream session, capture artifacts, and canonical glasses sidecars. | `android/app/src/test/kotlin/app/blueprint/capture/data/glasses/GlassesCaptureManagerTest.kt`; `android/app/src/test/kotlin/app/blueprint/capture/data/capture/AndroidCaptureBundleBuilderTest.kt` checks Meta companion-phone/glasses sidecars and Android XR fail-closed bundle claims; `./gradlew testDebugUnitTest` must pass. | Repo-local tests can prove stubbed compilation and raw-contract shaping. They do not prove real Meta DAT connectivity, physical glasses capture, provider readiness, payout readiness, hosted-review readiness, or public launch readiness. |
| Android XR projected glasses | Implemented as internal video-first capture path; not geometry-authoritative. | `docs/CAPTURE_RAW_CONTRACT_V3.md` and `AndroidCaptureBundleBuilder` keep `capture_profile_id = "android_xr_glasses"` and `capture_modality = "android_xr_video_only"` unless a future explicit geometry contract exists. | `AndroidCaptureBundleBuilderTest` includes Android XR contract and fail-closed tests. See `docs/CAPTURE_TO_PIPELINE_ANDROID_XR_PROOF_MAP.md` for the broader proof map. | Internal video-first evidence only until physical Android XR hardware proof and downstream proof exist for the same capture. |

## Completed Gaps - Do Not Reopen As Parity Work

### Contributor profile

Do not spend a future repo-local `/goal` redoing the old demo-profile fallback removal.
Current code already has the intended contract:

- `null` profile means unauthenticated, listener error, or no bootstrapped Firestore user doc.
- Existing Firestore docs become `ContributorProfile` values.
- Missing string fields default to `""`, not to `DemoData`.
- `role` still defaults to `"capturer"` as a role fallback, not as a fake identity.

Future work in this area should be limited to focused tests, UI polish, or backend schema changes
when explicitly requested. It should not restore "Alex Rivera" or any other demo identity as
production-like profile truth.

### Wallet ledger

Do not spend a future repo-local `/goal` replacing static wallet rows with repository data again.
Current code already loads history from `CaptureHistoryRepository.fetchHistory()` and passes
`payoutEntries` / `historyEntries` into `WalletLedgerContent()`.

The only intentionally empty ledger lane is cashouts. Cashouts should stay empty until a real
provider-backed collection or backend endpoint exists. Do not fill that tab with mock provider rows,
fake transfer status, or inferred payout settlement.

## Meta DAT / Private SDK Boundary

The Meta DAT path has two separate statuses:

1. Repo-local implementation: present behind `MWDAT_ENABLE_PRIVATE_SDK` with a disabled stub path for
   ordinary local builds.
2. Real glasses proof: blocked until private credentials, the private dependency, Meta AI setup,
   device permission flow, and physical hardware capture are available and tested.

The real verification command is:

```bash
cd /Users/nijelhunt_1/workspace/BlueprintCapture/android
ANDROID_HOME=/Users/nijelhunt_1/Library/Android/sdk ./gradlew :app:compileDebugKotlin -PMWDAT_ENABLE_PRIVATE_SDK=true
```

That command is expected to require all of the following:

- valid `gpr.user`
- valid `gpr.token`
- access to `https://maven.pkg.github.com/facebook/meta-wearables-dat-android`
- `MWDAT_APPLICATION_ID` / `MWDAT_CLIENT_TOKEN` when using non-dev Meta app registration
- physical Meta glasses for runtime proof
- screenshots/logs/raw bundle evidence for the same capture id before any readiness claim

Passing normal local unit tests without `-PMWDAT_ENABLE_PRIVATE_SDK=true` proves only the stubbed
local lane and contract-level behavior.

## Not Eligible For Repo-Local `/goal` Closeout

The items below require external secrets, physical devices, distribution systems, payment/provider
accounts, or live services. A repo-local autonomous run may document the blocker, validate local
schemas, or update fail-closed copy, but it must not mark these as done from local code/tests alone:

- Meta DAT private SDK proof: requires GitHub Packages credentials, `MWDAT_ENABLE_PRIVATE_SDK=true`,
  Meta app credentials, Meta AI setup, and physical glasses.
- Release backend URL: requires real `BLUEPRINT_BACKEND_BASE_URL` and
  `BLUEPRINT_DEMAND_BACKEND_BASE_URL` owned by the release environment.
- Firebase App Distribution / device smoke: requires an installable artifact, real tester/device
  install, notification/upload smoke, and signed-off evidence.
- Payout provider: requires real provider account/config proof such as
  `BLUEPRINT_PAYOUT_PROVIDER_READY=true` with backend evidence. UI balances/history do not prove
  payout onboarding or settlement.
- Live backend proof: requires actual backend calls and same-capture evidence through Capture,
  bridge, Pipeline, and WebApp surfaces where applicable.

If any of these are missing, the correct status is externally blocked, not "implementation gap" and
not "done."

## Verification Commands

Use these checks after editing this document or before relying on it in a future parity goal:

```bash
rg -n "demo|mock wallet|three[[:space:]]+remaining|MWDAT|private SDK|blocked" \
  android/IMPLEMENTATION_SPEC.md android/README.md docs
```

```bash
cd /Users/nijelhunt_1/workspace/BlueprintCapture/android
ANDROID_HOME=/Users/nijelhunt_1/Library/Android/sdk ./gradlew testDebugUnitTest
```
