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

fail_android_gate() {
  local stage="$1"
  local next_input="$2"
  shift 2
  echo "Android alpha readiness gate failed:" >&2
  echo "Stage: $stage" >&2
  echo "Next input needed: $next_input" >&2
  for line in "$@"; do
    echo "- $line" >&2
  done
  echo "Android remains internal-only until config validation, unit tests, release build, and device/App Distribution smoke are all explicitly satisfied." >&2
  exit 1
}

run_android_config_validation() {
  local output
  local status
  set +e
  output="$(./gradlew --no-daemon validateExternalAlphaReleaseConfig 2>&1)"
  status=$?
  set -e
  if [[ -n "$output" ]]; then
    printf '%s\n' "$output"
  fi
  if [[ "$status" != "0" ]]; then
    fail_android_gate \
      "android_release_config_blocked" \
      "Set the missing Android release properties in android/gradle.properties or pass them with -P; do not use placeholders or real secrets in tracked files." \
      "Gradle validateExternalAlphaReleaseConfig exited with status $status."
  fi
}

run_android_xr_config_validation() {
  python3 "$ROOT/scripts/validate_android_xr_release_readiness.py" --mode config --repo-root "$ROOT"
}

run_android_xr_proof_validation() {
  python3 "$ROOT/scripts/validate_android_xr_release_readiness.py" --mode proof --repo-root "$ROOT"
}

cd "$ANDROID_DIR"

require_java

echo "==> Validating Android external alpha release config"
run_android_config_validation

echo "==> Validating Android XR release config"
run_android_xr_config_validation

if [[ "$VALIDATE_ONLY" == "--validate-config-only" ]]; then
  echo "Android external alpha config validation passed. Android still requires unit tests, release build, Android XR proof, and device/App Distribution smoke before it can leave internal-only status."
  exit 0
fi

echo "==> Running Android unit tests"
./gradlew testDebugUnitTest

echo "==> Building Android release artifact"
./gradlew assembleRelease

echo "==> Validating Android XR release proof"
run_android_xr_proof_validation

echo "Android repo readiness checks passed with Android XR proof. Android still remains internal-only unless downstream proof and any human rollout approval are in scope."
