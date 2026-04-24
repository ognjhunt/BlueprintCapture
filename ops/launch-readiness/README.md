# iOS City Launch Readiness Proof

This folder holds launch-proof artifacts for `scripts/launch_city_readiness.sh`.

The gate has two modes:

- Contract check: `python3 scripts/validate_launch_readiness.py --contract-only --proof ops/launch-readiness/example.launch-proof.json`
- Real launch check: `BLUEPRINT_LAUNCH_PROOF_PATH=/absolute/path/to/<city>.launch-proof.json BLUEPRINT_LAUNCH_AUTH_TOKEN=<firebase-id-token> BLUEPRINT_LAUNCH_CITY_SLUG=<city-state> BLUEPRINT_LAUNCH_LAT=<lat> BLUEPRINT_LAUNCH_LNG=<lng> ./scripts/launch_city_readiness.sh`

Do not mark a real city green from the example artifact. A real proof file must be produced after a release-like hardware run and must point to actual storage, Firestore, pipeline, Meta-glasses, payout, and monitoring evidence.

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
