#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="${ROOT}/build/DerivedData"
RELEASE_DERIVED_DATA_PATH="${BLUEPRINT_RELEASE_DERIVED_DATA_PATH:-$ROOT/build/DerivedDataRelease}"
SIMULATOR_NAME="${BLUEPRINT_SIMULATOR_NAME:-iPhone 17 Pro}"
SIMULATOR_OS="${BLUEPRINT_SIMULATOR_OS:-26.0}"
RELEASE_XCCONFIG="${BLUEPRINT_RELEASE_XCCONFIG:-$ROOT/Config/BlueprintCapture.release.xcconfig}"

cd "$ROOT"

ensure_extract_frames_dependencies() {
  ensure_node_dependencies "${ROOT}/cloud/extract-frames"
}

ensure_referral_earnings_dependencies() {
  ensure_node_dependencies "${ROOT}/cloud/referral-earnings"
}

ensure_node_dependencies() {
  local package_dir="$1"
  if [[ -x "${package_dir}/node_modules/.bin/tsc" ]]; then
    return 0
  fi

  echo "==> Installing dependencies for ${package_dir#$ROOT/}"
  (cd "$package_dir" && npm ci >/dev/null)
}

resolve_swift_packages() {
  local derived_data_path="$1"
  local resolve_args=(
    -resolvePackageDependencies
    -project BlueprintCapture.xcodeproj
    -scheme BlueprintCapture
    -derivedDataPath "$derived_data_path"
  )

  if xcodebuild "${resolve_args[@]}" >/dev/null 2>&1; then
    return 0
  fi

  echo "==> Repairing stale Swift package state"
  rm -rf "$derived_data_path/SourcePackages"
  xcodebuild "${resolve_args[@]}" >/dev/null
}

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

ensure_extract_frames_dependencies
ensure_referral_earnings_dependencies
resolve_swift_packages "$DERIVED_DATA_PATH"

echo "==> Running cloud bridge tests"
(cd "$ROOT/cloud/extract-frames" && npm test)

echo "==> Running demand backend tests"
(cd "$ROOT/cloud/referral-earnings" && npm test)

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
BUILD_ARGS=(
  build
  -project BlueprintCapture.xcodeproj
  -scheme BlueprintCapture
  -configuration Release
  -destination "platform=iOS Simulator,id=${SIMULATOR_UDID}"
  -derivedDataPath "$RELEASE_DERIVED_DATA_PATH"
)

if [[ -f "$RELEASE_XCCONFIG" ]]; then
  echo "==> Using release xcconfig ${RELEASE_XCCONFIG}"
  BUILD_ARGS+=(-xcconfig "$RELEASE_XCCONFIG")
fi

resolve_swift_packages "$RELEASE_DERIVED_DATA_PATH"
xcodebuild "${BUILD_ARGS[@]}" >/dev/null

APP_PRODUCTS_DIR="$RELEASE_DERIVED_DATA_PATH/Build/Products/Release-iphonesimulator"
APP_PATH="$(find "$APP_PRODUCTS_DIR" -path '*BlueprintCapture.app' | head -n 1)"
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

INFO_PLIST="$APP_PATH/Info.plist"
plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$INFO_PLIST" 2>/dev/null || true
}

normalize_bool() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]'
}

for forbidden_key in PLACES_API_KEY GOOGLE_PLACES_API_KEY GEMINI_API_KEY GOOGLE_AI_API_KEY GEMINI_MAPS_API_KEY; do
  if [[ -n "$(plist_value "$forbidden_key")" ]]; then
    echo "Provider key $forbidden_key is bundled in the app. Nearby discovery must go through the backend proxy." >&2
    exit 1
  fi
done

ALLOW_MOCK="$(normalize_bool "$(plist_value BLUEPRINT_ALLOW_MOCK_JOBS_FALLBACK)")"
if [[ "$ALLOW_MOCK" == "1" || "$ALLOW_MOCK" == "true" || "$ALLOW_MOCK" == "yes" ]]; then
  echo "BLUEPRINT_ALLOW_MOCK_JOBS_FALLBACK must be disabled for release/TestFlight builds." >&2
  exit 1
fi

INTERNAL_TEST_SPACE="$(normalize_bool "$(plist_value BLUEPRINT_ENABLE_INTERNAL_TEST_SPACE)")"
if [[ "$INTERNAL_TEST_SPACE" == "1" || "$INTERNAL_TEST_SPACE" == "true" || "$INTERNAL_TEST_SPACE" == "yes" ]]; then
  echo "BLUEPRINT_ENABLE_INTERNAL_TEST_SPACE must be disabled for release/TestFlight builds." >&2
  exit 1
fi

REMOTE_NOTIFICATIONS="$(normalize_bool "$(plist_value BLUEPRINT_ENABLE_REMOTE_NOTIFICATIONS)")"
if [[ "$REMOTE_NOTIFICATIONS" != "1" && "$REMOTE_NOTIFICATIONS" != "true" && "$REMOTE_NOTIFICATIONS" != "yes" ]]; then
  echo "BLUEPRINT_ENABLE_REMOTE_NOTIFICATIONS must be enabled for release/TestFlight builds." >&2
  exit 1
fi

BACKEND_BASE_URL="$(plist_value BLUEPRINT_BACKEND_BASE_URL)"
if [[ -z "$BACKEND_BASE_URL" ]]; then
  echo "BLUEPRINT_BACKEND_BASE_URL must be set in the release build before external distribution." >&2
  exit 1
fi

DEMAND_BACKEND_BASE_URL="$(plist_value BLUEPRINT_DEMAND_BACKEND_BASE_URL)"
if [[ -z "$DEMAND_BACKEND_BASE_URL" ]]; then
  echo "BLUEPRINT_DEMAND_BACKEND_BASE_URL must be set in the release build." >&2
  exit 1
fi

NEARBY_PROVIDER="$(plist_value BLUEPRINT_NEARBY_DISCOVERY_PROVIDER)"
if [[ "$NEARBY_PROVIDER" != "places_nearby" ]]; then
  echo "Release default nearby provider must be places_nearby (found '$NEARBY_PROVIDER')." >&2
  exit 1
fi

if ! grep -q "aps-environment" "$ROOT/BlueprintCapture/BlueprintCapture.entitlements"; then
  echo "BlueprintCapture.entitlements is missing aps-environment." >&2
  exit 1
fi

for required_url_key in \
  BLUEPRINT_MAIN_WEBSITE_URL \
  BLUEPRINT_HELP_CENTER_URL \
  BLUEPRINT_BUG_REPORT_URL \
  BLUEPRINT_TERMS_OF_SERVICE_URL \
  BLUEPRINT_PRIVACY_POLICY_URL \
  BLUEPRINT_CAPTURE_POLICY_URL \
  BLUEPRINT_ACCOUNT_DELETION_URL
do
  if [[ -z "$(plist_value "$required_url_key")" ]]; then
    echo "$required_url_key must be configured for external builds so support and legal flows are not dead links." >&2
    exit 1
  fi
done

SUPPORT_EMAIL_ADDRESS="$(plist_value BLUEPRINT_SUPPORT_EMAIL_ADDRESS)"
if [[ -z "$SUPPORT_EMAIL_ADDRESS" ]]; then
  echo "BLUEPRINT_SUPPORT_EMAIL_ADDRESS must be configured for external builds." >&2
  exit 1
fi

echo "Alpha readiness checks passed."
