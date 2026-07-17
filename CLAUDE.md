# BlueprintCapture Claude Guide

Read first:

1. `PLATFORM_CONTEXT.md`
2. `WORLD_MODEL_STRATEGY_CONTEXT.md`
3. `AGENTS.md`

Key rules:

- Protect capture truth and canonical bundle integrity.
- Do not fabricate provider readiness, payout readiness, or qualification decisions.
- Keep downstream contracts stable for the pipeline and webapp.
- Treat advisory UX as advisory, not authoritative.
- Before claiming Paperclip/autonomous-loop `done`, `blocked`, or `awaiting_human_decision`, apply `../Blueprint-WebApp/docs/autonomous-loop-evidence-checklist-2026-05-03.md` (sibling checkout of Blueprint-WebApp).

Key commands:

```bash
xcodebuild -project BlueprintCapture.xcodeproj -scheme BlueprintCapture -derivedDataPath build/DerivedData
cd cloud/extract-frames && npm test
./scripts/archive_external_alpha.sh --validate-config-only
./scripts/android_alpha_readiness.sh --validate-config-only
```

## gstack

- Use the repo-local gstack install at `.agents/skills/gstack` when you need slash-skill workflows.
- Prefer `/investigate`, `/review`, `/codex`, and `/cso` for runtime bugs, capture regressions, and security-sensitive changes.
