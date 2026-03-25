# BlueprintCapture Quick Start

## What You Are Building

This app captures walkthrough evidence and packages a raw bundle for downstream qualification and scene-memory work.

It is not a reconstruction app.

## Start

```bash
open BlueprintCapture.xcodeproj
```

Or:

```bash
xcodebuild -project BlueprintCapture.xcodeproj \
  -scheme BlueprintCapture \
  -destination "platform=iOS Simulator,name=iPhone 15" \
  -derivedDataPath build/DerivedData
```

## Primary Flow

1. Complete onboarding.
2. Reserve or select a capture target.
3. Record with iPhone or Meta glasses.
4. Let the app finalize the raw bundle.
5. Upload the bundle under `scenes/{scene_id}/captures/{capture_id}/raw/`.

## What To Verify

- `manifest.json` exists and is patched with `scene_id` and `video_uri`
- `capture_context.json` exists
- `capture_upload_complete.json` exists
- ARKit files are present for iPhone captures when the device supports them
- scene-memory and rights metadata are present even when values are unknown

## Alpha Notes

- Honest empty states are valid. Do not inject demo marketplace targets in production-like builds.
- Android glasses capture should only be started from a real target or open-capture flow so the bundle keeps truthful site metadata.
- Direct-provider AI features and Android payout onboarding are out of scope unless you explicitly wire and validate real provider contracts.

## Key Paths

- [/Users/nijelhunt_1/workspace/BlueprintCapture/BlueprintCapture/VideoCaptureManager.swift](/Users/nijelhunt_1/workspace/BlueprintCapture/BlueprintCapture/VideoCaptureManager.swift)
- [/Users/nijelhunt_1/workspace/BlueprintCapture/BlueprintCapture/Services/CaptureBundleSupport.swift](/Users/nijelhunt_1/workspace/BlueprintCapture/BlueprintCapture/Services/CaptureBundleSupport.swift)
- [/Users/nijelhunt_1/workspace/BlueprintCapture/cloud/extract-frames/src/index.ts](/Users/nijelhunt_1/workspace/BlueprintCapture/cloud/extract-frames/src/index.ts)

## Release Config

```bash
BLUEPRINT_RELEASE_XCCONFIG=/absolute/path/to/BlueprintCapture.release.xcconfig \
./scripts/archive_external_alpha.sh --validate-config-only
```

For xcconfig URLs, follow the slash-helper pattern in [ConfigTemplates/BlueprintCapture.release.xcconfig.example](/Users/nijelhunt_1/workspace/BlueprintCapture/ConfigTemplates/BlueprintCapture.release.xcconfig.example) so `https://...` is not parsed as `https:`.
