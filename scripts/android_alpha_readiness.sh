#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_DIR="$ROOT/android"
VALIDATE_ONLY="${1:-}"

cd "$ANDROID_DIR"

echo "==> Validating Android external alpha release config"
./gradlew validateExternalAlphaReleaseConfig

if [[ "$VALIDATE_ONLY" == "--validate-config-only" ]]; then
  echo "Android external alpha config validation passed."
  exit 0
fi

echo "==> Running Android unit tests"
./gradlew testDebugUnitTest

echo "==> Building Android release artifact"
./gradlew assembleRelease

echo "Android alpha readiness checks passed."
