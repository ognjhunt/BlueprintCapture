# Android Agent Notes

Read the root `AGENTS.md`, `PLATFORM_CONTEXT.md`, `WORLD_MODEL_STRATEGY_CONTEXT.md`, `README.md`, `docs/CAPTURE_RAW_CONTRACT_V3.md`, `android/README.md`, and `android/IMPLEMENTATION_SPEC.md` before changing Android behavior.

Local scope:
- Kotlin/Compose app shell, auth, onboarding, scan, capture, upload, wallet, profile, glasses, Android XR, ARCore, and launch gating live here.
- `ScanScreen.kt`, `CaptureSessionScreen.kt`, `AndroidCaptureBundleBuilder.kt`, `CaptureUploadRepository.kt`, and `data/glasses/GlassesCaptureManager.kt` are high-risk surfaces.

Rules:
- Android is internal-only until release config, unit tests, release build, device/App Distribution smoke, and downstream proof are satisfied.
- Do not turn mock/stub glasses, local wallet state, or open capture into public provider/payout/launch proof.
- Do not edit `android/local.properties`, `app/google-services.json`, secrets, or release config.
- Prefer `ANDROID_HOME=/Users/nijelhunt_1/Library/Android/sdk` in commands instead of writing local config.

Safe checks:
- `cd android && ANDROID_HOME=/Users/nijelhunt_1/Library/Android/sdk ./gradlew testDebugUnitTest`
- `cd android && ANDROID_HOME=/Users/nijelhunt_1/Library/Android/sdk ./gradlew assembleDebug`
- `./scripts/android_alpha_readiness.sh --validate-config-only` from the repo root; fail-closed config failures are blockers.
