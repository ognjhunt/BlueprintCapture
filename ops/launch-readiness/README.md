# iOS City Launch Readiness Proof

This folder holds launch-proof artifacts for `scripts/launch_city_readiness.sh`.

`scripts/launch_city_readiness.sh` always runs `python3 scripts/validate_launch_readiness_tests.py` before validating release config or proof artifacts.

The gate has two proof modes:

- Contract check: `python3 scripts/validate_launch_readiness.py --contract-only --proof ops/launch-readiness/example.launch-proof.json`
- Real launch check: `BLUEPRINT_LAUNCH_PROOF_PATH=/absolute/path/to/<city>.launch-proof.json BLUEPRINT_LAUNCH_AUTH_TOKEN=<firebase-id-token> BLUEPRINT_LAUNCH_CITY_SLUG=<city-state> BLUEPRINT_LAUNCH_LAT=<lat> BLUEPRINT_LAUNCH_LNG=<lng> ./scripts/launch_city_readiness.sh`

Do not mark a real city green from the example artifact. A real proof file must be produced after a release-like hardware run and must point to actual storage, Firestore, pipeline, Meta-glasses, payout, and monitoring evidence.
The real proof gate rejects `ops/launch-readiness/example.launch-proof.json` and placeholder strings such as `example`, `replace_me`, `your-*`, `todo`, or `tbd`; copying the example and flipping `contract_only` is not launch proof.
The live-route gate also rejects placeholder auth tokens, city slugs, and coordinates before making backend calls.
Use `ops/launch-readiness/real-launch-proof.template.json` only as a shape reference. Fill a separate `<city>.launch-proof.json` with real values and evidence references; the template itself is intentionally not named `*.launch-proof.json`.

The real launch proof must show:

- release config passed `./scripts/archive_external_alpha.sh --validate-config-only`
- backend launch-status supports the city
- the launch city has at least one live approved capture job and one live capture target
- mock job fallback and internal test space are disabled
- a real-device capture uploaded and wrote `capture_submissions/{captureId}`
- bridge artifacts and pipeline handoff completed
- Meta glasses were smoke-tested on physical hardware, with video-first/non-geometry marketing confirmed
- Open Capture Here remains review-gated and unpriced
- payout claims are gated behind live Stripe/backend state
- launch-week monitoring has an owner and concrete watches

The real launch proof must also include non-placeholder evidence references:

- `evidence.release_config_settings`
- `evidence.launch_status_response`
- `evidence.demand_feed_response`
- `evidence.capture_submission_document`
- `evidence.raw_upload_complete`
- `evidence.pipeline_descriptor`
- `evidence.pipeline_qa_report`
- `evidence.pipeline_handoff`
- `evidence.meta_glasses_smoke`
- `evidence.stripe_account_state`
- `evidence.monitoring_runbook`
