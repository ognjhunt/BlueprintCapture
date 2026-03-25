#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_XCCONFIG="${BLUEPRINT_RELEASE_XCCONFIG:-$ROOT/Config/BlueprintCapture.release.xcconfig}"
ARCHIVE_PATH="${BLUEPRINT_ARCHIVE_PATH:-$ROOT/build/BlueprintCaptureExternal.xcarchive}"
DERIVED_DATA_PATH="${BLUEPRINT_DERIVED_DATA_PATH:-$ROOT/build/DerivedDataRelease}"
BUILD_SETTINGS_PATH="${BLUEPRINT_BUILD_SETTINGS_PATH:-$ROOT/build/BlueprintCaptureExternalRelease.settings}"
VALIDATE_ONLY=0

if [[ "${1:-}" == "--validate-config-only" ]]; then
  VALIDATE_ONLY=1
fi

cd "$ROOT"

if [[ ! -f "$RELEASE_XCCONFIG" ]]; then
  echo "Release xcconfig not found at $RELEASE_XCCONFIG" >&2
  echo "Copy ConfigTemplates/BlueprintCapture.release.xcconfig.example to an untracked local path first." >&2
  exit 1
fi

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

xcconfig_value() {
  local key="$1"
  awk -F= -v key="$key" '
    $0 !~ /^[[:space:]]*\/\// && $1 ~ ("^[[:space:]]*" key "[[:space:]]*$") {
      sub(/^[[:space:]]+/, "", $2)
      sub(/[[:space:]]+$/, "", $2)
      print $2
      exit
    }
  ' "$RELEASE_XCCONFIG"
}

require_xcconfig_value() {
  local key="$1"
  local value
  value="$(trim "$(xcconfig_value "$key")")"
  if [[ -z "$value" ]]; then
    echo "$key must be set in $RELEASE_XCCONFIG." >&2
    exit 1
  fi
  case "$value" in
    *your-backend.example.com*|*your-project.cloudfunctions.net*|*replace_me*|*example.com*)
      echo "$key still uses a placeholder value in $RELEASE_XCCONFIG." >&2
      exit 1
      ;;
  esac
}

normalize_bool() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]'
}

require_xcconfig_bool() {
  local key="$1"
  local expected="$2"
  local value
  value="$(normalize_bool "$(xcconfig_value "$key")")"
  if [[ "$value" != "$expected" ]]; then
    echo "$key must be set to $expected in $RELEASE_XCCONFIG." >&2
    exit 1
  fi
}

build_setting_value() {
  local key="$1"
  awk -F= -v key="$key" '
    $1 ~ ("^[[:space:]]*" key "[[:space:]]*$") {
      sub(/^[[:space:]]+/, "", $2)
      sub(/[[:space:]]+$/, "", $2)
      print $2
      exit
    }
  ' "$BUILD_SETTINGS_PATH"
}

lint_release_inputs() {
  require_xcconfig_value "BLUEPRINT_BACKEND_BASE_URL"
  require_xcconfig_value "BLUEPRINT_DEMAND_BACKEND_BASE_URL"
  require_xcconfig_bool "BLUEPRINT_ALLOW_MOCK_JOBS_FALLBACK" "no"
  require_xcconfig_bool "BLUEPRINT_ENABLE_INTERNAL_TEST_SPACE" "no"
  require_xcconfig_bool "BLUEPRINT_ENABLE_REMOTE_NOTIFICATIONS" "yes"

  mkdir -p "$(dirname "$BUILD_SETTINGS_PATH")"
  xcodebuild -showBuildSettings \
    -project BlueprintCapture.xcodeproj \
    -scheme BlueprintCapture \
    -configuration Release \
    -xcconfig "$RELEASE_XCCONFIG" > "$BUILD_SETTINGS_PATH"

  local resolved_backend_url
  local resolved_demand_url
  resolved_backend_url="$(trim "$(build_setting_value BLUEPRINT_BACKEND_BASE_URL)")"
  resolved_demand_url="$(trim "$(build_setting_value BLUEPRINT_DEMAND_BACKEND_BASE_URL)")"

  if [[ -z "$resolved_backend_url" ]]; then
    echo "Release build settings still resolve BLUEPRINT_BACKEND_BASE_URL to empty." >&2
    exit 1
  fi

  if [[ -z "$resolved_demand_url" ]]; then
    echo "Release build settings still resolve BLUEPRINT_DEMAND_BACKEND_BASE_URL to empty." >&2
    exit 1
  fi

  if [[ "$resolved_backend_url" =~ ^https?:$ || "$resolved_demand_url" =~ ^https?:$ ]]; then
    echo "Release xcconfig URLs are being truncated by xcconfig parsing. Use the slash-helper form from ConfigTemplates/BlueprintCapture.release.xcconfig.example." >&2
    exit 1
  fi
}

lint_release_inputs

if [[ "$VALIDATE_ONLY" == "1" ]]; then
  echo "Release config validated: $RELEASE_XCCONFIG"
  echo "Resolved build settings saved at $BUILD_SETTINGS_PATH"
  exit 0
fi

echo "==> Archiving BlueprintCapture with $RELEASE_XCCONFIG"
xcodebuild archive \
  -project BlueprintCapture.xcodeproj \
  -scheme BlueprintCapture \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE_PATH" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -xcconfig "$RELEASE_XCCONFIG"

APP_PATH="$ARCHIVE_PATH/Products/Applications/BlueprintCapture.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Archive completed but $APP_PATH was not found." >&2
  exit 1
fi

echo "==> Running release bundle lint"
INFO_PLIST="$APP_PATH/Info.plist"
plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$INFO_PLIST" 2>/dev/null || true
}

for forbidden_key in PLACES_API_KEY GOOGLE_PLACES_API_KEY GEMINI_API_KEY GOOGLE_AI_API_KEY GEMINI_MAPS_API_KEY; do
  if [[ -n "$(plist_value "$forbidden_key")" ]]; then
    echo "Provider key $forbidden_key is bundled in the archived app." >&2
    exit 1
  fi
done

if [[ "$(normalize_bool "$(plist_value BLUEPRINT_ALLOW_MOCK_JOBS_FALLBACK)")" == "true" ]]; then
  echo "BLUEPRINT_ALLOW_MOCK_JOBS_FALLBACK must be disabled in the archive." >&2
  exit 1
fi

if [[ "$(normalize_bool "$(plist_value BLUEPRINT_ENABLE_INTERNAL_TEST_SPACE)")" == "true" ]]; then
  echo "BLUEPRINT_ENABLE_INTERNAL_TEST_SPACE must be disabled in the archive." >&2
  exit 1
fi

if [[ "$(normalize_bool "$(plist_value BLUEPRINT_ENABLE_REMOTE_NOTIFICATIONS)")" != "true" ]]; then
  echo "BLUEPRINT_ENABLE_REMOTE_NOTIFICATIONS must be enabled in the archive." >&2
  exit 1
fi

if [[ "$(normalize_bool "$(plist_value MWDAT:MockDevice:Enabled)")" == "true" ]]; then
  echo "MWDAT mock device must be disabled in the archive." >&2
  exit 1
fi

if [[ -z "$(plist_value BLUEPRINT_BACKEND_BASE_URL)" ]]; then
  echo "BLUEPRINT_BACKEND_BASE_URL must be set in the archive." >&2
  exit 1
fi

if [[ -z "$(plist_value BLUEPRINT_DEMAND_BACKEND_BASE_URL)" ]]; then
  echo "BLUEPRINT_DEMAND_BACKEND_BASE_URL must be set in the archive." >&2
  exit 1
fi

echo "Archive ready at $ARCHIVE_PATH"
