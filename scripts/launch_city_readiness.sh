#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_XCCONFIG="${BLUEPRINT_RELEASE_XCCONFIG:-$ROOT/Config/BlueprintCapture.release.xcconfig}"
PROOF_PATH="${BLUEPRINT_LAUNCH_PROOF_PATH:-$ROOT/ops/launch-readiness/austin-tx.launch-proof.json}"

cd "$ROOT"

echo "==> Testing launch readiness validator"
PYTHONDONTWRITEBYTECODE=1 python3 ./scripts/validate_launch_readiness_tests.py

echo "==> Validating release config"
BLUEPRINT_RELEASE_XCCONFIG="$RELEASE_XCCONFIG" ./scripts/archive_external_alpha.sh --validate-config-only

echo "==> Validating city launch readiness proof"
python3 ./scripts/validate_launch_readiness.py \
  --release-xcconfig "$RELEASE_XCCONFIG" \
  --proof "$PROOF_PATH" \
  "$@"
