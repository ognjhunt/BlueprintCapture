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
- `captures/{capture_id}/capture_descriptor.json` - Canonical bridge handoff payload
- `captures/{capture_id}/qa_report.json` - Quality gate outcome and metrics
- `images/{capture_id}_keyframe.jpg` - Middle-third keyframe selected via sharpness proxy
- `prompts/scene_request.json` - Auto trigger request (written on QA pass for `scenes/*` paths)

## Processing Details

- **Frame extraction**: 5 FPS using FFmpeg with Lanczos scaling
- **Image quality**: JPEG at quality level 2
- **Pose alignment**: schema-tolerant parser supports both legacy ARKit rows (`frameIndex`/`timestamp`/`transform`) and v2 rows (`frame_id`/`t_device_sec`/`T_world_camera`)
- **Keyframe policy**: chooses highest sharpness proxy (file-size heuristic) from the middle third of extracted frames
- **Quality gates**:
  - required files (`manifest.json`, `walkthrough.mov`)
  - iPhone Tier-1 ARKit alignment checks
  - Tier-2 fallback for degraded iPhone and glasses captures

## Additional Functions

### cleanRoomplan

Triggers on `*/raw/roomplan.zip` uploads and removes `Object_grp` from RoomPlan USDZ files to create architecture-only models.

- **Input**: `*/raw/roomplan.zip`
- **Output**: `*/processed/roomplan.zip` with `RoomPlanArchitectureOnly.usdz`
