# Cloud Agent Notes

Read the root `AGENTS.md`, `README.md`, `docs/CAPTURE_RAW_CONTRACT_V3.md`, `docs/CAPTURE_BRIDGE_CONTRACT.md`, and `docs/architecture/source-of-truth-map.md` before changing cloud behavior.

Local scope:
- `extract-frames` is the raw-upload bridge to frame extraction, descriptor/QA artifacts, and Pipeline handoff.
- `referral-earnings` owns capture submission status, referral bonuses, demand/opportunity APIs, nearby/place proxies, and demand research schedules.

Rules:
- Local tests are safe; deploys and live function invocations are not.
- Preserve completion-marker-last assumptions and fail-closed bridge blockers.
- Do not fabricate upstream ids, provider proof, payout state, hosted-review proof, or launch proof.
- Prefer `src/` for implementation reasoning. Treat `dist/` as build/runtime output unless deliberately publishing function builds.

Safe checks:
- `cd cloud/extract-frames && npm test`
- `cd cloud/referral-earnings && npm test`

Restricted unless explicitly requested:
- `firebase deploy`
- live HTTP mutation calls
- Pub/Sub publishes
- Firestore writes against production data
