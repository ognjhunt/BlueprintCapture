#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_DIR="$ROOT/android"
VALIDATE_ONLY="${1:-}"

require_command() {
  local command_name="$1"
  local hint="$2"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "$hint" >&2
    exit 1
  fi
}

require_java() {
  if [[ -n "${JAVA_HOME:-}" ]]; then
    if [[ -x "$JAVA_HOME/jre/sh/java" || -x "$JAVA_HOME/bin/java" ]]; then
      return 0
    fi

    echo "JAVA_HOME is set but does not point to a valid Java installation. Fix JAVA_HOME before running Android alpha readiness." >&2
    exit 1
  fi

  require_command java "Java is missing from PATH. Install a JDK and set JAVA_HOME before running Android alpha readiness."
}

cd "$ANDROID_DIR"

require_java

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
