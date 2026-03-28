# BlueprintCapture Claude Guide

Read first:

1. `/Users/nijelhunt_1/workspace/BlueprintCapture/PLATFORM_CONTEXT.md`
2. `/Users/nijelhunt_1/workspace/BlueprintCapture/WORLD_MODEL_STRATEGY_CONTEXT.md`
3. `/Users/nijelhunt_1/workspace/BlueprintCapture/AGENTS.md`

Key rules:

- Protect capture truth and canonical bundle integrity.
- Do not fabricate provider readiness, payout readiness, or qualification decisions.
- Keep downstream contracts stable for the pipeline and webapp.
- Treat advisory UX as advisory, not authoritative.

Key commands:

```bash
xcodebuild -project BlueprintCapture.xcodeproj -scheme BlueprintCapture -derivedDataPath build/DerivedData
cd cloud/extract-frames && npm test
./scripts/archive_external_alpha.sh --validate-config-only
./scripts/android_alpha_readiness.sh --validate-config-only
```
