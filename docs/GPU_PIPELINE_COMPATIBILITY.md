# GPU Pipeline Compatibility Guide

This document describes how BlueprintCapture iOS app outputs data in a format compatible with the Cloud GPU Pipeline for processing video captures into SimReady USD scenes.

## Upload Location

All captures are uploaded to Firebase Storage at:

```
gs://blueprint-8c1ca.appspot.com/scenes/{scene_id}/{source}/{timestamp}-{uuid}/raw/
```

Where:
- `{scene_id}` - Target ID, Reservation ID, or Job ID (in that priority order)
- `{source}` - `iphone` for iPhone captures, `glasses` for Meta glasses captures
- `{timestamp}-{uuid}` - ISO8601 timestamp + UUID for uniqueness

## Required Files

| File | Description | Both Sources |
|------|-------------|--------------|
| `manifest.json` | Capture metadata (pipeline trigger) | Yes |
| `walkthrough.mov` | Main video file (H.264/MOV) | Yes |

## Optional Files (iPhone with ARKit)

| File/Folder | Description | Pipeline Benefit |
|-------------|-------------|------------------|
| `motion.jsonl` | IMU data at 60Hz | Better motion estimation |
| `arkit/poses.jsonl` | Camera pose per frame | **Skips SLAM entirely** |
| `arkit/intrinsics.json` | Camera calibration | Metric-accurate reconstruction |
| `arkit/frames.jsonl` | Frame timestamps | Pose-frame synchronization |
| `arkit/depth/*.png` | LiDAR depth maps (16-bit) | Better 3D reconstruction |
| `arkit/confidence/*.png` | Depth confidence maps | Filter unreliable depth |
| `arkit/meshes/*.obj` | ARKit mesh anchors | Pre-built geometry |
| `arkit/objects/index.json` | Point cloud refs | Object detection hints |

## manifest.json Schema

### Required Fields

```json
{
  "scene_id": "string",           // Unique ID for the space (patched by upload service)
  "video_uri": "string",          // Full GCS path (patched by upload service)
  "device_model": "string",       // e.g., "iPhone 15 Pro" or "Meta Ray-Ban Smart Glasses"
  "os_version": "string",         // e.g., "17.2"
  "fps_source": 30.0,             // Source video FPS (float)
  "width": 1920,                  // Video width in pixels
  "height": 1440,                 // Video height in pixels
  "capture_start_epoch_ms": 1702137045123,  // Unix timestamp in milliseconds
  "has_lidar": true,              // Whether device has LiDAR (false for glasses)
  "capture_schema_version": "2.0.0",
  "capture_source": "iphone|glasses",
  "capture_tier_hint": "tier1_iphone|tier2_glasses"
}
```

### Optional Fields

```json
{
  "scale_hint_m_per_unit": 1.0,           // ARKit scale factor (default 1.0)
  "intended_space_type": "home",          // "home", "office", "retail", etc.
  "object_point_cloud_index": "arkit/objects/index.json",  // Path to object index
  "object_point_cloud_count": 5,          // Number of detected objects
  "exposure_samples": [                   // Exposure data samples
    {
      "iso": 100,
      "exposure_duration": 0.008,
      "timestamp": 0.0                    // Seconds from capture start
    }
  ]
}
```

## ARKit Data Formats

### arkit/poses.jsonl

One JSON object per line, containing camera-to-world transform in **row-major** format.
The current schema is backward-compatible and includes both legacy and bridge fields:

```json
{
  "pose_schema_version": "2.0",
  "frameIndex": 0,
  "timestamp": 12345.6789,
  "transform": [[r00,r01,r02,tx],[r10,r11,r12,ty],[r20,r21,r22,tz],[0,0,0,1]],
  "frame_id": "000001",
  "t_device_sec": 0.000000,
  "T_world_camera": [[r00,r01,r02,tx],[r10,r11,r12,ty],[r20,r21,r22,tz],[0,0,0,1]]
}
```

- Legacy fields:
  - `frameIndex` - Integer frame index starting at 0
  - `timestamp` - ARKit device timestamp
  - `transform` - 4x4 camera-to-world matrix in row-major order
- Bridge fields:
  - `pose_schema_version` - Current pose schema version
  - `frame_id` - Zero-padded frame ID (`000001`, ...)
  - `t_device_sec` - Seconds from first ARKit frame in the capture
  - `T_world_camera` - Same transform in bridge canonical field name

### arkit/intrinsics.json

```json
{
  "fx": 1458.45,    // Focal length X
  "fy": 1458.45,    // Focal length Y
  "cx": 960.0,      // Principal point X
  "cy": 720.0,      // Principal point Y
  "width": 1920,    // Image width
  "height": 1440    // Image height
}
```

### arkit/frames.jsonl

Extended frame information including depth map references:

```json
{
  "frameIndex": 0,
  "timestamp": 0.0,
  "capturedAt": "2024-12-09T15:30:45.123Z",
  "cameraTransform": [16 floats],
  "intrinsics": [9 floats],
  "imageResolution": [1920, 1440],
  "sceneDepthFile": "arkit/depth/000001.png",
  "smoothedSceneDepthFile": "arkit/depth/smoothed-000001.png",
  "confidenceFile": "arkit/confidence/000001.png"
}
```

### motion.jsonl

IMU data at 60Hz:

```json
{
  "timestamp": 12345.678,
  "wallTime": "2024-12-09T15:30:45.123Z",
  "attitude": {
    "roll": 0.123,
    "pitch": -0.456,
    "yaw": 1.789,
    "quaternion": {"x": 0.1, "y": 0.2, "z": 0.3, "w": 0.9}
  },
  "rotationRate": {"x": 0.01, "y": 0.02, "z": 0.03},
  "gravity": {"x": 0.0, "y": -1.0, "z": 0.0},
  "userAcceleration": {"x": 0.1, "y": 0.05, "z": -0.02}
}
```

## Depth Map Format

- **Format**: 16-bit grayscale PNG
- **Encoding**: Float32 meters → UInt16 millimeters (clamped 0-65535)
- **Location**: `arkit/depth/*.png` and `arkit/depth/smoothed-*.png`

## Confidence Map Format

- **Format**: 8-bit grayscale PNG
- **Values**: 0 (low), 1 (medium), 2 (high)
- **Location**: `arkit/confidence/*.png`

## Mesh Data Format

- **Format**: Wavefront OBJ
- **Location**: `arkit/meshes/mesh-{uuid}.obj`
- **Contents**: World-space vertex positions, face indices, per-vertex normals

## Pipeline Trigger

The Cloud Function in `cloud/extract-frames/src/index.ts` monitors:

- `scenes/<scene_id>/<source>/<capture_id>/raw/walkthrough.mov`
- `targets/<scene_id>/raw/walkthrough.mov` (legacy compatibility)

When triggered it performs:

1. Frame extraction to `.../frames/*.jpg` + `.../frames/index.jsonl`
2. ARKit pose alignment with schema-tolerant parsing (legacy + v2 rows)
3. Keyframe selection (sharpness proxy in middle third) and upload to:
   - `scenes/<scene_id>/images/<capture_id>_keyframe.jpg` (scenes mode)
4. QA + descriptor emission:
   - `scenes/<scene_id>/captures/<capture_id>/qa_report.json`
   - `scenes/<scene_id>/captures/<capture_id>/capture_descriptor.json`
5. Automatic source orchestrator request on QA pass:
   - `scenes/<scene_id>/prompts/scene_request.json` (`source_mode=image`)

## Source-Specific Differences

### iPhone Capture

- **Has ARKit**: Full sensor data available (poses, depth, meshes, intrinsics)
- **LiDAR**: Available on Pro models (iPhone 12 Pro+)
- **Video**: H.264/MOV from AVCaptureSession or ARSession
- **Recommended**: Enable all ARKit data collection for best pipeline results

### Meta Glasses Capture

- **No ARKit**: No poses, depth, or intrinsics available
- **No LiDAR**: `has_lidar` is always `false`
- **Video**: 720p @ 30fps H.264/MOV stream
- **Motion**: Device IMU data from iPhone (not glasses)
- **Note**: Pipeline will run SLAM for camera pose estimation

## Processing Impact

| Data Available | Pipeline Behavior |
|----------------|-------------------|
| ARKit poses + intrinsics | **Fast path**: Skips SLAM, uses metric-accurate poses |
| No ARKit poses | **Slow path**: Runs WildGS-SLAM or COLMAP |
| LiDAR depth | Better 3D reconstruction, especially for textureless surfaces |
| Motion data | Helps with motion blur compensation and tracking |
| Object point clouds | Provides hints for object segmentation |

## Recommendations

### For Best Quality/Speed

1. **Use iPhone with LiDAR** (iPhone 12 Pro or newer)
2. **Enable all ARKit data** (poses, intrinsics, depth)
3. **Record at 30 FPS** (pipeline extracts at 4 FPS)
4. **Walk slowly and steadily**
5. **Cover all areas from multiple angles**
6. **Minimize moving objects** (people, pets)

### For Glasses Capture

1. Motion data is still captured from iPhone IMU
2. Consider including an ArUco marker or tape measure for scale calibration
3. Ensure good lighting for better SLAM results
4. Multiple captures from different angles improve reconstruction
