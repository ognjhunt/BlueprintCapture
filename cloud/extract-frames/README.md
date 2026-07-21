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
`1_000_000_000` bytes — sized so video + extracted frames + node heap fit the
function's 4GiB memory limit, since `/tmp` is RAM-backed tmpfs on Cloud Run —
and can be lowered or raised with
`BLUEPRINT_EXTRACT_FRAMES_MAX_INLINE_VIDEO_BYTES`. Captures over the limit are
blocked with a documented artifact trail and require the segmented/Cloud Run
ingest path to be picked up separately.

If object metadata is unavailable or the raw video exceeds the inline limit, the
function returns before `file.download()` and before ffmpeg. It writes:

- `captures/{capture_id}/large_video_ingest_blocked.json`
- `captures/{capture_id}/large_video_ingest_request.json`
- `captures/{capture_id}/large_video_ingest_pubsub_receipt.json`
- `captures/{capture_id}/qa_report.json` with `status: "blocked"`
- `captures/{capture_id}/pipeline_status_event.json`

The request is published to Pub/Sub topic
`BLUEPRINT_LARGE_VIDEO_INGEST_TOPIC` or `blueprint-large-video-ingest` by
default. It is a handoff for a disk-backed Cloud Run worker: it explicitly
requires segmented decode and forbids downloading the raw video into the
2 GiB extractFrames function tmpfs. These artifacts do not claim frames,
descriptor generation, pipeline handoff, scene success, or task success.

## Tests

```bash
npm test
```
