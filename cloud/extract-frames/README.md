# Extract Frames Cloud Function

This function turns uploaded walkthrough evidence into bridge outputs, then asks
the WebApp to reconstruct the capture.

It does not generate scenes itself. It extracts frames and publishes a downstream
handoff payload once upload completion is observed, then posts the frame prefix to
the WebApp, which sends those frames to a World Labs world model and hands the
resulting scene to the Pipeline. That request is the last link that makes the
chain hands-off: a capturer uploads one video and nobody presses a button after
that.

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
- asks the WebApp to start world reconstruction from the extracted frames

## World Reconstruction Request

After the handoff publishes, the function POSTs to the WebApp:

```
POST <BLUEPRINT_WEBAPP_BASE_URL>/api/internal/pipeline/creator-captures/<capture_id>/world/reconstruct
{ "frames_prefix_uri": "gs://<bucket>/<frames_prefix>", "scene_id": "..." }
```

Signed with HMAC-SHA256 over `<timestamp>.<body>` in
`X-Blueprint-Pipeline-Signature`, which is what the WebApp's
`verifyPipelineSyncRequest` recomputes.

Configuration:

- `BLUEPRINT_WEBAPP_BASE_URL` — WebApp origin. Unset means no request is made.
- `BLUEPRINT_PIPELINE_SYNC_TOKEN` — the same shared secret the WebApp verifies
  against (`PIPELINE_SYNC_TOKEN` there).

With either unset the function records
`captures/{capture_id}/world_reconstruction_request.json` with
`status: "not_configured"` and continues. Frames and the Pipeline handoff are
the canonical output of this function; a world is downstream of them, so a
WebApp that is unreachable leaves a capture that can be reconstructed later
rather than a capture that looks failed.

That receipt is also the idempotency guard. The storage trigger is
at-least-once and generating a world costs credits, so a redelivery that finds
`status: "requested"` does not ask again. The receipt records that
reconstruction was *requested* — it is not a claim that a world exists, that it
is any good, or that the capture qualified for anything.

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

> **Open verification (2026-07 audit):** nothing in this repository subscribes
> to `blueprint-capture-pipeline-handoff`. Confirm the pipeline repository
> actually consumes this topic (or gate publishing behind a flag) — otherwise
> every handoff publish is pure cost. Track the answer here when verified.
