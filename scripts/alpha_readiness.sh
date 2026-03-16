#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="${ROOT}/build/DerivedData"
SIMULATOR_NAME="${BLUEPRINT_SIMULATOR_NAME:-iPhone 17 Pro}"
SIMULATOR_OS="${BLUEPRINT_SIMULATOR_OS:-26.0}"

cd "$ROOT"

find_simulator_udid() {
  xcrun simctl list devices available | awk -v name="$SIMULATOR_NAME" -v os="$SIMULATOR_OS" '
    $0 ~ "^-- iOS " os " --$" { in_os=1; next }
    /^--/ { in_os=0 }
    in_os && index($0, name " (") {
      split($0, parts, "(")
      if (length(parts) >= 2) {
        udid = parts[2]
        sub(/\).*/, "", udid)
        print udid
        exit
      }
    }
  '
}

wait_for_simulator_boot() {
  local deadline=$((SECONDS + 180))

  while (( SECONDS < deadline )); do
    if xcrun simctl list devices | grep -Fq "${SIMULATOR_UDID}) (Booted)"; then
      if xcrun simctl spawn "$SIMULATOR_UDID" launchctl print system >/dev/null 2>&1; then
        return 0
      fi
    fi
    sleep 2
  done

  echo "Timed out waiting for simulator ${SIMULATOR_NAME} (${SIMULATOR_UDID}) to finish booting." >&2
  return 1
}

SIMULATOR_UDID="$(find_simulator_udid)"
if [[ -z "$SIMULATOR_UDID" ]]; then
  echo "Unable to find simulator ${SIMULATOR_NAME} (iOS ${SIMULATOR_OS})." >&2
  exit 1
fi

XCODE_TEST_ARGS=(
  -project BlueprintCapture.xcodeproj
  -scheme BlueprintCapture
  -destination "platform=iOS Simulator,id=${SIMULATOR_UDID}"
  -parallel-testing-enabled NO
  -maximum-concurrent-test-simulator-destinations 1
  -derivedDataPath "$DERIVED_DATA_PATH"
)

echo "==> Booting simulator ${SIMULATOR_NAME} (${SIMULATOR_UDID})"
xcrun simctl boot "$SIMULATOR_UDID" >/dev/null 2>&1 || true
wait_for_simulator_boot

echo "==> Running cloud bridge tests"
(cd "$ROOT/cloud/extract-frames" && npm test)

echo "==> Running focused iOS tests"
xcodebuild test \
  "${XCODE_TEST_ARGS[@]}" \
  -only-testing:BlueprintCaptureTests \
  >/dev/null

xcodebuild test \
  "${XCODE_TEST_ARGS[@]}" \
  -only-testing:BlueprintCaptureUITests/CorePathUITests \
  >/dev/null

echo "==> Building app bundle for secret packaging check"
xcodebuild build \
  -project BlueprintCapture.xcodeproj \
  -scheme BlueprintCapture \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath "$DERIVED_DATA_PATH" >/dev/null

APP_PATH="$(find "$DERIVED_DATA_PATH/Build/Products" -path '*BlueprintCapture.app' | head -n 1)"
if [[ -z "$APP_PATH" ]]; then
  echo "Failed to locate built BlueprintCapture.app" >&2
  exit 1
fi

echo "==> Checking bundle contents"
if find "$APP_PATH" -maxdepth 1 -name 'Secrets*.plist' | grep -q .; then
  echo "Secret plist files are still present in the app bundle:" >&2
  find "$APP_PATH" -maxdepth 1 -name 'Secrets*.plist' >&2
  exit 1
fi

if [[ -f "$ROOT/BlueprintCapture/GoogleService-Info.plist" ]] && [[ ! -f "$APP_PATH/GoogleService-Info.plist" ]]; then
  echo "GoogleService-Info.plist is missing from the app bundle." >&2
  exit 1
fi

echo "Alpha readiness checks passed."
