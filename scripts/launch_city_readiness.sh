#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_XCCONFIG="${BLUEPRINT_RELEASE_XCCONFIG:-$ROOT/Config/BlueprintCapture.release.xcconfig}"
CONTRACT_ONLY=0

for arg in "$@"; do
  if [[ "$arg" == "--contract-only" ]]; then
    CONTRACT_ONLY=1
  fi
done

if [[ -n "${BLUEPRINT_LAUNCH_PROOF_PATH:-}" ]]; then
  PROOF_PATH="$BLUEPRINT_LAUNCH_PROOF_PATH"
elif [[ "$CONTRACT_ONLY" == "1" ]]; then
  PROOF_PATH="$ROOT/ops/launch-readiness/example.launch-proof.json"
else
  PROOF_PATH="$ROOT/ops/launch-readiness/austin-tx.launch-proof.json"
fi

cd "$ROOT"

echo "==> Testing launch readiness validator"
PYTHONDONTWRITEBYTECODE=1 python3 ./scripts/validate_launch_readiness_tests.py

echo "==> Validating release config"
BLUEPRINT_RELEASE_XCCONFIG="$RELEASE_XCCONFIG" ./scripts/archive_external_alpha.sh --validate-config-only

echo "==> Validating city launch readiness proof"
if [[ "$CONTRACT_ONLY" == "1" && "$PROOF_PATH" == "$ROOT/ops/launch-readiness/example.launch-proof.json" ]]; then
  echo "==> Using contract-only example proof; this is not live launch signoff"
fi
python3 ./scripts/validate_launch_readiness.py \
  --release-xcconfig "$RELEASE_XCCONFIG" \
  --proof "$PROOF_PATH" \
  "$@"
