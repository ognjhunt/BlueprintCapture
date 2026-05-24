#!/usr/bin/env python3
import argparse
import json
import os
import re
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path
from typing import Any


ANDROID_NS = "{http://schemas.android.com/apk/res/android}"
SPATIAL_FEATURE = "android.software.xr.api.spatial"
OPENXR_FEATURE = "android.software.xr.api.openxr"
VALID_RELEASE_TRACKS = {"mobile", "dedicated"}
PROOF_SCHEMA_VERSION = "android_xr_release_readiness_v1"


@dataclass
class GateFailure(Exception):
    stage: str
    next_input: str
    details: list[str]


def fail(stage: str, next_input: str, *details: str) -> None:
    raise GateFailure(stage=stage, next_input=next_input, details=list(details))


def print_failure(error: GateFailure) -> None:
    print("Android XR release-readiness gate failed:", file=sys.stderr)
    print(f"Stage: {error.stage}", file=sys.stderr)
    print(f"Next input needed: {error.next_input}", file=sys.stderr)
    for detail in error.details:
        print(f"- {detail}", file=sys.stderr)


def read_text(path: Path, label: str) -> str:
    if not path.exists():
        fail(
            "android_xr_release_config_blocked",
            f"Restore the missing {label} before validating Android XR release readiness.",
            f"Missing file: {path}",
        )
    return path.read_text()


def parse_assignment_int(text: str, name: str, minimum: int) -> int:
    match = re.search(rf"\b{name}\s*=\s*(\d+)", text)
    if not match:
        fail(
            "android_xr_release_config_blocked",
            f"Declare {name} explicitly in android/app/build.gradle.kts.",
            f"{name} was not found.",
        )
    value = int(match.group(1))
    if value < minimum:
        fail(
            "android_xr_release_config_blocked",
            f"Raise {name} to at least {minimum} for Android XR release readiness.",
            f"{name} is {value}.",
        )
    return value


def manifest_features(manifest_path: Path) -> dict[str, str]:
    root = ET.parse(manifest_path).getroot()
    features: dict[str, str] = {}
    for element in root.findall("uses-feature"):
        name = element.attrib.get(f"{ANDROID_NS}name", "")
        required = element.attrib.get(f"{ANDROID_NS}required", "")
        if name:
            features[name] = required
    return features


def xr_dependencies_present(build_gradle_text: str) -> bool:
    return "androidx.xr." in build_gradle_text or "libs.androidx.xr" in build_gradle_text


def validate_config(repo_root: Path, release_track: str) -> None:
    if release_track not in VALID_RELEASE_TRACKS:
        fail(
            "android_xr_release_config_blocked",
            "Set BLUEPRINT_ANDROID_XR_RELEASE_TRACK to mobile or dedicated.",
            f"Received release track: {release_track}",
        )

    build_gradle_path = repo_root / "android" / "app" / "build.gradle.kts"
    manifest_path = repo_root / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
    build_gradle_text = read_text(build_gradle_path, "Android Gradle build file")

    if not xr_dependencies_present(build_gradle_text):
        print("Android XR dependencies were not detected; Android XR release gate is not applicable.")
        return

    parse_assignment_int(build_gradle_text, "compileSdk", 34)
    parse_assignment_int(build_gradle_text, "minSdk", 24)
    parse_assignment_int(build_gradle_text, "targetSdk", 35)

    features = manifest_features(manifest_path)
    has_spatial = SPATIAL_FEATURE in features
    has_openxr = OPENXR_FEATURE in features

    if has_spatial and has_openxr:
        fail(
            "android_xr_manifest_blocked",
            "Choose one Android XR API feature for this APK before release validation.",
            f"Both {SPATIAL_FEATURE} and {OPENXR_FEATURE} are declared.",
        )

    if not has_spatial:
        fail(
            "android_xr_manifest_blocked",
            "Declare the Android XR Spatial API feature in AndroidManifest.xml for the Jetpack XR app path.",
            f"Missing <uses-feature android:name=\"{SPATIAL_FEATURE}\" ...>.",
        )

    required = features[SPATIAL_FEATURE]
    expected_required = "true" if release_track == "dedicated" else "false"
    if required != expected_required:
        fail(
            "android_xr_manifest_blocked",
            f"Set {SPATIAL_FEATURE} android:required=\"{expected_required}\" for the {release_track} release track.",
            f"Current manifest value is android:required=\"{required}\".",
        )

    print(f"Android XR release config gate passed for {release_track} track.")


def load_json(path: Path) -> dict[str, Any]:
    try:
        parsed = json.loads(path.read_text())
    except json.JSONDecodeError as error:
        fail(
            "android_xr_release_proof_blocked",
            "Provide a valid JSON proof file for Android XR release readiness.",
            f"{path}: {error}",
        )
    if not isinstance(parsed, dict):
        fail(
            "android_xr_release_proof_blocked",
            "Provide a JSON object proof file for Android XR release readiness.",
            f"{path} did not contain a JSON object.",
        )
    return parsed


def result_for(proof: dict[str, Any], key: str) -> str:
    value = proof.get(key)
    if not isinstance(value, dict):
        fail(
            "android_xr_release_proof_blocked",
            f"Record {key}.result in the Android XR release proof file.",
            f"Missing object: {key}",
        )
    result = value.get("result")
    if not isinstance(result, str):
        fail(
            "android_xr_release_proof_blocked",
            f"Record {key}.result in the Android XR release proof file.",
            f"Missing result field in: {key}",
        )
    return result


def require_non_blank(proof: dict[str, Any], key: str) -> str:
    value = proof.get(key)
    if not isinstance(value, str) or not value.strip():
        fail(
            "android_xr_release_proof_blocked",
            f"Record {key} in the Android XR release proof file.",
            f"Missing or blank field: {key}",
        )
    return value.strip()


def validate_proof(repo_root: Path, release_track: str, proof_path: str | None) -> None:
    validate_config(repo_root, release_track)

    if not proof_path:
        fail(
            "android_xr_release_proof_blocked",
            "Set BLUEPRINT_ANDROID_XR_RELEASE_PROOF_PATH to a local, non-secret Android XR proof JSON file.",
            "The full Android release gate cannot pass without device/App Distribution smoke and quality-review evidence.",
        )

    path = Path(proof_path).expanduser()
    if not path.is_absolute():
        path = repo_root / path
    if not path.exists():
        fail(
            "android_xr_release_proof_blocked",
            "Point BLUEPRINT_ANDROID_XR_RELEASE_PROOF_PATH at an existing local proof JSON file.",
            f"Missing proof file: {path}",
        )

    proof = load_json(path)
    schema_version = require_non_blank(proof, "schema_version")
    if schema_version != PROOF_SCHEMA_VERSION:
        fail(
            "android_xr_release_proof_blocked",
            f"Use schema_version {PROOF_SCHEMA_VERSION} for Android XR release proof.",
            f"Received schema_version: {schema_version}",
        )

    proof_track = require_non_blank(proof, "release_track")
    if proof_track != release_track:
        fail(
            "android_xr_release_proof_blocked",
            "Make the proof release_track match BLUEPRINT_ANDROID_XR_RELEASE_TRACK.",
            f"Proof release_track is {proof_track}; active release track is {release_track}.",
        )

    require_non_blank(proof, "checked_at")
    require_non_blank(proof, "reviewer")

    for key in ("device_smoke", "app_distribution_smoke", "quality_guidelines_review"):
        result = result_for(proof, key)
        if result != "pass":
            fail(
                "android_xr_release_proof_blocked",
                f"Complete {key} before Android XR can leave internal-only status.",
                f"{key}.result is {result!r}; expected 'pass'.",
            )

    public_claims = proof.get("public_distribution_claims")
    if not isinstance(public_claims, dict) or public_claims.get("audio_display_glasses_ready") is not False:
        fail(
            "android_xr_release_proof_blocked",
            "Keep Android XR audio/display-glasses public distribution claims blocked until platform distribution is explicitly available.",
            "public_distribution_claims.audio_display_glasses_ready must be false.",
        )

    print(f"Android XR release proof gate passed using {path}.")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate Android XR release-readiness gates.")
    parser.add_argument("--repo-root", default=Path(__file__).resolve().parents[1])
    parser.add_argument("--mode", choices=("config", "proof"), required=True)
    parser.add_argument("--proof-path", default=None)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repo_root = Path(args.repo_root).resolve()
    release_track = os.environ.get("BLUEPRINT_ANDROID_XR_RELEASE_TRACK", "mobile").strip() or "mobile"
    proof_path = args.proof_path or os.environ.get("BLUEPRINT_ANDROID_XR_RELEASE_PROOF_PATH")

    try:
        if args.mode == "config":
            validate_config(repo_root, release_track)
        else:
            validate_proof(repo_root, release_track, proof_path)
    except GateFailure as error:
        print_failure(error)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
