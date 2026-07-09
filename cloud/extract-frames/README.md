# Extract Frames Cloud Function

This function turns uploaded walkthrough evidence into bridge outputs.

It does not generate scenes. It does not run downstream model derivation requests.
It does publish a downstream handoff payload once upload completion is observed.

## Supported Input Paths

Canonical:

- `scenes/<scene_id>/captures/<capture_id>/raw/walkthrough.mov`

Compatibility:

- `scenes/<scene_id>/<source>/<capture_id>/raw/walkthrough.mov`
- `targets/<scene_id>/raw/walkthrough.mov`

## Outputs

- `frames/*.jpg`
- `frames/index.jsonl`
- `captures/{capture_id}/capture_descriptor.json`
- `captures/{capture_id}/qa_report.json`
- `captures/{capture_id}/pipeline_handoff.json`
- `images/{capture_id}_keyframe.jpg`

## What It Does

- extracts frames at 5 FPS
- aligns ARKit poses when present
- computes QA metrics
- writes an evidence descriptor and QA report
- publishes the finalized capture handoff to Pub/Sub topic `blueprint-capture-pipeline-handoff`

## Large Video Guard

The inline Cloud Function path is bounded before downloading `walkthrough.mov` or
`walkthrough.mp4` into `/tmp`. The default max inline video size is
`1_500_000_000` bytes and can be lowered or raised with
`BLUEPRINT_EXTRACT_FRAMES_MAX_INLINE_VIDEO_BYTES`.

If object metadata is unavailable or the raw video exceeds the inline limit, the
function returns before `file.download()` and before ffmpeg. It writes:

- `captures/{capture_id}/large_video_ingest_blocked.json`
- `captures/{capture_id}/qa_report.json` with `status: "blocked"`
- `captures/{capture_id}/pipeline_status_event.json`

The blocker points the capture to `large_video_cloud_run_ingest`; it does not
claim frames, descriptor generation, pipeline handoff, scene success, or task
success.

## Tests

```bash
npm test
```
