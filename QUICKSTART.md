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
  -destination "platform=iOS Simulator,name=iPhone 15"
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

## Key Paths

- [/Users/nijelhunt_1/workspace/BlueprintCapture/BlueprintCapture/VideoCaptureManager.swift](/Users/nijelhunt_1/workspace/BlueprintCapture/BlueprintCapture/VideoCaptureManager.swift)
- [/Users/nijelhunt_1/workspace/BlueprintCapture/BlueprintCapture/Services/CaptureBundleSupport.swift](/Users/nijelhunt_1/workspace/BlueprintCapture/BlueprintCapture/Services/CaptureBundleSupport.swift)
- [/Users/nijelhunt_1/workspace/BlueprintCapture/cloud/extract-frames/src/index.ts](/Users/nijelhunt_1/workspace/BlueprintCapture/cloud/extract-frames/src/index.ts)
