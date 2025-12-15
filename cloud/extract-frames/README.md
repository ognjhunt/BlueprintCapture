# Extract Frames Cloud Function

Firebase Cloud Function that extracts video frames and aligns them with ARKit pose data.

## Supported Input Paths

The function triggers on video uploads to either path format:

- **iOS uploader format**: `scenes/<scene_id>/<source>/<capture_id>/raw/walkthrough.mov`
- **Legacy format**: `targets/<scene_id>/raw/walkthrough.mov`

## Output

For each input video, the function outputs to a `frames/` directory next to `raw/`:

- `frames/*.jpg` - Extracted frames (5 FPS, 512px max dimension, Lanczos scaling)
- `frames/index.jsonl` - Frame index with timestamps and matched ARKit poses

## Processing Details

- **Frame extraction**: 5 FPS using FFmpeg with Lanczos scaling
- **Image quality**: JPEG at quality level 2
- **Pose alignment**: When `arkit/poses.jsonl` exists, each frame is matched to the closest ARKit pose by frame_id or timestamp

## Additional Functions

### cleanRoomplan

Triggers on `*/raw/roomplan.zip` uploads and removes `Object_grp` from RoomPlan USDZ files to create architecture-only models.

- **Input**: `*/raw/roomplan.zip`
- **Output**: `*/processed/roomplan.zip` with `RoomPlanArchitectureOnly.usdz`
