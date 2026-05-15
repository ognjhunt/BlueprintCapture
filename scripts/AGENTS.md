# Scripts Agent Notes

Read the root `AGENTS.md`, `README.md`, `docs/PRIVATE_ALPHA_READINESS.md`, and `docs/architecture/command-safety-matrix.md` before changing scripts.

Local scope:
- Scripts are readiness gates, validators, and release helpers. Their job is to fail closed when proof or config is missing.

Rules:
- Do not soften release, Android, launch, provider, payout, Firebase, App Distribution, or device-proof blockers to make a run pass.
- Missing ignored release config is a blocker, not a repo bug by default.
- Do not edit `Config/*.xcconfig`, `android/local.properties`, secrets, Firebase plist/json secrets, or release config files.
- Keep stage names and "next input needed" output specific enough for future agents to identify the earliest hard stop.

Safe checks:
- `PYTHONDONTWRITEBYTECODE=1 python3 scripts/validate_launch_readiness_tests.py`
- `./scripts/archive_external_alpha.sh --validate-config-only`
- `./scripts/android_alpha_readiness.sh --validate-config-only`
