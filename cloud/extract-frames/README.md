# Extract Frames Cloud Function

This function turns uploaded walkthrough evidence into bridge outputs.

It does not generate scenes. It does not run downstream model derivation requests.

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
- `images/{capture_id}_keyframe.jpg`

## What It Does

- extracts frames at 5 FPS
- aligns ARKit poses when present
- computes QA metrics
- writes an evidence descriptor and QA report

## Tests

```bash
npm test
```
