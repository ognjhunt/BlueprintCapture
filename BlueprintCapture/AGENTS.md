# iOS App Agent Notes

Read the root `AGENTS.md`, `PLATFORM_CONTEXT.md`, `WORLD_MODEL_STRATEGY_CONTEXT.md`, `README.md`, and `docs/CAPTURE_RAW_CONTRACT_V3.md` before changing iOS app behavior.

Local scope:
- SwiftUI app, capture flow, ARKit/AVFoundation recording, raw-bundle finalization, upload, wallet/profile, launch gating, and glasses surfaces live here.
- `VideoCaptureManager.swift`, `Services/CaptureBundleSupport.swift`, `Services/CaptureUploadService.swift`, and `GlassesCaptureManager.swift` are high-risk contract files.

Rules:
- Preserve raw capture truth and V3/V3.1 bundle compatibility.
- Keep quality hints advisory. Do not make in-app UI authoritative for payout, provider, rights, hosted-review, or launch readiness.
- Do not edit `GoogleService-Info.plist`, release xcconfig files, secrets, or local config.
- Simulator proof is not physical-device, Meta glasses, push, provider, payout, or TestFlight proof.

Safe checks:
- `xcodebuild -list -project BlueprintCapture.xcodeproj`
- `xcodebuild -project BlueprintCapture.xcodeproj -scheme BlueprintCapture -derivedDataPath build/DerivedData`
- Targeted `xcodebuild test` only when behavior changes justify it.
