#!/usr/bin/env python3
"""Validate BlueprintCapture iOS city-launch readiness.

This script is intentionally stricter than a build check. It refuses to mark a
city launch ready from code shape alone; live launch claims must be backed by an
authenticated backend check and a proof artifact produced from hardware/live
ops evidence.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]

REQUIRED_LIVE_INPUTS = [
    "BLUEPRINT_LAUNCH_PROOF_PATH=/absolute/path/to/<city>.launch-proof.json",
    "BLUEPRINT_LAUNCH_AUTH_TOKEN=<firebase-id-token>",
    "BLUEPRINT_LAUNCH_CITY_SLUG=<city-state>",
    "BLUEPRINT_LAUNCH_LAT=<latitude>",
    "BLUEPRINT_LAUNCH_LNG=<longitude>",
]

REQUIRED_REAL_PROOF_REFERENCES = [
    "evidence.release_config_settings",
    "evidence.launch_status_response",
    "evidence.demand_feed_response",
    "evidence.capture_submission_document",
    "evidence.raw_upload_complete",
    "evidence.pipeline_descriptor",
    "evidence.pipeline_qa_report",
    "evidence.pipeline_handoff",
    "evidence.meta_glasses_smoke",
    "evidence.stripe_account_state",
    "evidence.monitoring_runbook",
]

PLACEHOLDER_MARKERS = ("example", "replace_me", "your-", "<", ">", "todo", "tbd", "placeholder")


def live_input_hint() -> str:
    inputs = "\n  ".join(REQUIRED_LIVE_INPUTS)
    return (
        "Required live launch inputs:\n"
        f"  {inputs}\n"
        "The proof file must be real city evidence; "
        "ops/launch-readiness/example.launch-proof.json is contract-only."
    )


def load_json(path: Path) -> dict[str, Any]:
    try:
        with path.open("r", encoding="utf-8") as handle:
            value = json.load(handle)
    except FileNotFoundError:
        raise SystemExit(f"Launch proof file not found: {path}\n{live_input_hint()}")
    except json.JSONDecodeError as exc:
        raise SystemExit(f"Launch proof file is not valid JSON: {path}: {exc}")
    if not isinstance(value, dict):
        raise SystemExit(f"Launch proof file must contain a JSON object: {path}")
    return value


def nested(value: dict[str, Any], dotted_path: str) -> Any:
    current: Any = value
    for key in dotted_path.split("."):
        if not isinstance(current, dict) or key not in current:
            return None
        current = current[key]
    return current


def parse_xcconfig(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.exists():
        raise SystemExit(f"Release xcconfig not found: {path}")
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("//") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip()
    return values


def normalized_bool(value: str | None) -> bool | None:
    if value is None:
        return None
    normalized = value.strip().lower()
    if normalized in {"1", "true", "yes", "y", "on"}:
        return True
    if normalized in {"0", "false", "no", "n", "off"}:
        return False
    return None


def contains_placeholder(value: str) -> bool:
    normalized = value.strip().lower()
    return any(marker in normalized for marker in PLACEHOLDER_MARKERS)


def parse_live_coordinate(value: Any, path: str, failures: list[str]) -> float | None:
    if value is None:
        failures.append(f"{path} is required for live demand feed checks")
        return None
    if isinstance(value, (int, float)):
        return float(value)
    if not isinstance(value, str) or not value.strip():
        failures.append(f"{path} is required for live demand feed checks")
        return None
    if contains_placeholder(value):
        failures.append(f"{path} cannot be a placeholder for live route checks: {value}")
        return None
    try:
        return float(value)
    except ValueError:
        failures.append(f"{path} must be a decimal coordinate for live demand feed checks: {value}")
        return None


def http_json(url: str, method: str = "GET", token: str | None = None, body: dict[str, Any] | None = None) -> tuple[int, dict[str, Any]]:
    headers = {"Accept": "application/json", "X-Blueprint-Native-Client": "ios-launch-readiness"}
    data = None
    if token:
        headers["Authorization"] = f"Bearer {token}"
    if body is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(body).encode("utf-8")
    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            payload = response.read()
            parsed = json.loads(payload.decode("utf-8")) if payload else {}
            return response.status, parsed if isinstance(parsed, dict) else {"_value": parsed}
    except urllib.error.HTTPError as exc:
        payload = exc.read()
        try:
            parsed = json.loads(payload.decode("utf-8")) if payload else {}
        except json.JSONDecodeError:
            parsed = {"body": payload.decode("utf-8", errors="replace")}
        return exc.code, parsed if isinstance(parsed, dict) else {"_value": parsed}


def require_truthy(proof: dict[str, Any], failures: list[str], path: str) -> None:
    if nested(proof, path) is not True:
        failures.append(f"{path} must be true")


def require_number_at_least(proof: dict[str, Any], failures: list[str], path: str, minimum: int) -> None:
    value = nested(proof, path)
    if not isinstance(value, (int, float)) or value < minimum:
        failures.append(f"{path} must be >= {minimum}")


def require_non_empty(proof: dict[str, Any], failures: list[str], path: str) -> None:
    value = nested(proof, path)
    if not isinstance(value, str) or not value.strip():
        failures.append(f"{path} must be a non-empty string")


def validate_real_proof_not_placeholder(proof: dict[str, Any], failures: list[str], proof_path: Path, contract_only: bool) -> None:
    if contract_only:
        return
    if proof.get("contract_only") is not False:
        failures.append("real launch proof must set contract_only to false")
    if not proof_path.name.endswith(".launch-proof.json"):
        failures.append("real launch proof filename must end with .launch-proof.json")
    if proof_path.name == "example.launch-proof.json":
        failures.append("ops/launch-readiness/example.launch-proof.json cannot be used for a real city launch")

    proof_contract_paths = ["city_slug", "evidence_generated_at", "ops.launch_owner", *REQUIRED_REAL_PROOF_REFERENCES]
    for path in proof_contract_paths:
        value = nested(proof, path)
        if isinstance(value, str) and contains_placeholder(value):
            failures.append(f"{path} contains placeholder proof text: {value}")


def validate_real_proof_references(proof: dict[str, Any], failures: list[str], contract_only: bool) -> None:
    if contract_only:
        return
    weak_reference_values = {
        "done",
        "ok",
        "pass",
        "passed",
        "ready",
        "true",
        "verified",
        "yes",
    }
    for path in REQUIRED_REAL_PROOF_REFERENCES:
        require_non_empty(proof, failures, path)
        value = nested(proof, path)
        if not isinstance(value, str):
            continue
        normalized = value.strip().lower()
        if normalized in weak_reference_values:
            failures.append(f"{path} must point to concrete evidence, not status text: {value}")
        if not any(marker in value for marker in (":", "/", "#")):
            failures.append(f"{path} must include an inspectable evidence reference: {value}")


def validate_release_xcconfig(path: Path, failures: list[str]) -> None:
    values = parse_xcconfig(path)
    required_keys = [
        "BLUEPRINT_BACKEND_BASE_URL",
        "BLUEPRINT_DEMAND_BACKEND_BASE_URL",
        "BLUEPRINT_MAIN_WEBSITE_URL",
        "BLUEPRINT_HELP_CENTER_URL",
        "BLUEPRINT_BUG_REPORT_URL",
        "BLUEPRINT_TERMS_OF_SERVICE_URL",
        "BLUEPRINT_PRIVACY_POLICY_URL",
        "BLUEPRINT_CAPTURE_POLICY_URL",
        "BLUEPRINT_ACCOUNT_DELETION_URL",
        "BLUEPRINT_SUPPORT_EMAIL_ADDRESS",
        "BLUEPRINT_NEARBY_DISCOVERY_PROVIDER",
        "BLUEPRINT_ALLOW_MOCK_JOBS_FALLBACK",
        "BLUEPRINT_ENABLE_INTERNAL_TEST_SPACE",
        "BLUEPRINT_ENABLE_REMOTE_NOTIFICATIONS",
        "APS_ENVIRONMENT",
    ]
    for key in required_keys:
        value = values.get(key, "")
        if not value:
            failures.append(f"{key} must be set in {path}")
        if any(marker in value for marker in ("example.com", "replace_me", "your-project", "your-creator")):
            failures.append(f"{key} still contains a placeholder in {path}")

    if normalized_bool(values.get("BLUEPRINT_ALLOW_MOCK_JOBS_FALLBACK")) is not False:
        failures.append("BLUEPRINT_ALLOW_MOCK_JOBS_FALLBACK must be NO")
    if normalized_bool(values.get("BLUEPRINT_ENABLE_INTERNAL_TEST_SPACE")) is not False:
        failures.append("BLUEPRINT_ENABLE_INTERNAL_TEST_SPACE must be NO")
    if normalized_bool(values.get("BLUEPRINT_ENABLE_REMOTE_NOTIFICATIONS")) is not True:
        failures.append("BLUEPRINT_ENABLE_REMOTE_NOTIFICATIONS must be YES")
    if values.get("BLUEPRINT_NEARBY_DISCOVERY_PROVIDER") != "places_nearby":
        failures.append("BLUEPRINT_NEARBY_DISCOVERY_PROVIDER must be places_nearby")
    if values.get("APS_ENVIRONMENT") != "production":
        failures.append("APS_ENVIRONMENT must be production")


def validate_proof(
    proof: dict[str, Any],
    failures: list[str],
    contract_only: bool,
    city_slug: str | None,
    proof_path: Path | None = None,
) -> None:
    if proof.get("contract_only") is True and not contract_only:
        failures.append("contract_only proof cannot be used for a real city launch")
    if proof_path is not None:
        validate_real_proof_not_placeholder(proof, failures, proof_path, contract_only)
    validate_real_proof_references(proof, failures, contract_only)
    if city_slug and proof.get("city_slug") != city_slug:
        failures.append(f"proof city_slug must be {city_slug}")

    require_non_empty(proof, failures, "evidence_generated_at")
    require_truthy(proof, failures, "release.config_validated_by_archive_script")
    require_truthy(proof, failures, "city.backend_supported")
    require_number_at_least(proof, failures, "city.live_approved_job_count", 1)
    require_number_at_least(proof, failures, "city.live_capture_target_count", 1)
    require_truthy(proof, failures, "city.mock_fallback_disabled")
    require_truthy(proof, failures, "city.internal_test_space_disabled")
    require_truthy(proof, failures, "capture.real_device_capture_uploaded")
    require_truthy(proof, failures, "capture.capture_submissions_document_exists")
    require_truthy(proof, failures, "capture.raw_upload_complete_exists")
    require_truthy(proof, failures, "pipeline.capture_descriptor_exists")
    require_truthy(proof, failures, "pipeline.qa_report_exists")
    require_truthy(proof, failures, "pipeline.pipeline_handoff_exists")
    require_truthy(proof, failures, "pipeline.pubsub_handoff_succeeded")
    require_truthy(proof, failures, "pipeline.pipeline_processed_capture")
    require_truthy(proof, failures, "meta_glasses.physical_device_smoke_passed")
    require_truthy(proof, failures, "meta_glasses.video_first_positioning_confirmed")
    require_truthy(proof, failures, "meta_glasses.native_geometry_not_marketed")
    require_truthy(proof, failures, "open_capture.review_gated")
    if nested(proof, "open_capture.payout_cents") != 0:
        failures.append("open_capture.payout_cents must be 0")
    require_truthy(proof, failures, "open_capture.paid_anywhere_claim_disabled")
    require_truthy(proof, failures, "payouts.backend_configured")
    require_truthy(proof, failures, "payouts.stripe_state_checked")
    require_truthy(proof, failures, "payouts.marketing_claims_require_stripe_ready")
    require_non_empty(proof, failures, "ops.launch_owner")
    require_truthy(proof, failures, "ops.failed_upload_monitor")
    require_truthy(proof, failures, "ops.submission_registration_monitor")
    require_truthy(proof, failures, "ops.push_device_sync_monitor")
    require_truthy(proof, failures, "ops.bridge_pipeline_monitor")
    require_truthy(proof, failures, "ops.payout_exception_monitor")
    require_truthy(proof, failures, "ops.session_events_queryable")
    require_truthy(proof, failures, "ops.cloud_logging_handoff_alert")


def validate_live_routes(args: argparse.Namespace, failures: list[str], skip_network: bool = False) -> None:
    if args.contract_only:
        return
    missing_inputs: list[str] = []
    if not args.auth_token:
        missing_inputs.append("BLUEPRINT_LAUNCH_AUTH_TOKEN or --auth-token is required for live creator launch/Stripe route checks")
    elif contains_placeholder(args.auth_token):
        missing_inputs.append("BLUEPRINT_LAUNCH_AUTH_TOKEN or --auth-token cannot be a placeholder for live route checks")
    if not args.city_slug:
        missing_inputs.append("BLUEPRINT_LAUNCH_CITY_SLUG or --city-slug is required for live launch route checks")
    elif contains_placeholder(args.city_slug):
        missing_inputs.append(f"BLUEPRINT_LAUNCH_CITY_SLUG or --city-slug cannot be a placeholder for live route checks: {args.city_slug}")
    lat = parse_live_coordinate(args.lat, "BLUEPRINT_LAUNCH_LAT or --lat", missing_inputs)
    lng = parse_live_coordinate(args.lng, "BLUEPRINT_LAUNCH_LNG or --lng", missing_inputs)
    if missing_inputs:
        failures.extend(missing_inputs)
        return
    if skip_network:
        failures.append("live route checks skipped until release config and proof artifact failures are resolved")
        return

    backend = args.backend_base_url.rstrip("/")
    demand = args.demand_backend_base_url.rstrip("/")

    status_url = f"{backend}/v1/creator/launch-status?city_slug={urllib.parse.quote(args.city_slug)}"
    status, launch_payload = http_json(status_url, token=args.auth_token)
    if status != 200:
        failures.append(f"launch-status route returned HTTP {status}: {launch_payload}")
    else:
        supported = launch_payload.get("supportedCities", [])
        current = launch_payload.get("currentCity") or {}
        supported_slugs = {city.get("citySlug") for city in supported if isinstance(city, dict)}
        if args.city_slug not in supported_slugs and current.get("citySlug") != args.city_slug:
            failures.append(f"launch-status response does not include city_slug {args.city_slug}")
        if current and current.get("isSupported") is not True:
            failures.append(f"launch-status currentCity is not supported: {current}")

    feed_url = f"{demand}/v1/opportunities/feed"
    feed_body = {
        "lat": lat,
        "lng": lng,
        "radiusMeters": args.radius_meters,
        "limit": args.limit,
        "candidatePlaces": [],
    }
    feed_status, feed_payload = http_json(feed_url, method="POST", body=feed_body)
    if feed_status != 200:
        failures.append(f"demand opportunity feed returned HTTP {feed_status}: {feed_payload}")
    else:
        capture_jobs = feed_payload.get("capture_jobs") or feed_payload.get("captureJobs") or []
        if not isinstance(capture_jobs, list) or len(capture_jobs) == 0:
            failures.append("demand opportunity feed returned zero capture jobs for launch coordinates")

    stripe_status, stripe_payload = http_json(f"{backend}/v1/stripe/accounts/current", token=args.auth_token)
    if stripe_status != 200:
        failures.append(f"Stripe account state route must return 200 for paid launch proof; got HTTP {stripe_status}: {stripe_payload}")


def readiness_stage(failures: list[str]) -> str:
    if not failures:
        return "ready"
    if any("must be set in" in failure or "still contains a placeholder" in failure for failure in failures):
        return "release_config_blocked"
    if any(
        failure.startswith("contract_only proof")
        or failure.startswith("ops/launch-readiness/example.launch-proof.json")
        or failure.startswith("real launch proof")
        or "contains placeholder proof text" in failure
        or failure.startswith("evidence.")
        or failure.startswith("proof city_slug")
        or failure.startswith("city.")
        or failure.startswith("capture.")
        or failure.startswith("pipeline.")
        or failure.startswith("meta_glasses.")
        or failure.startswith("open_capture.")
        or failure.startswith("payouts.")
        or failure.startswith("ops.")
        for failure in failures
    ):
        return "proof_artifact_blocked"
    if any("required for live" in failure for failure in failures):
        return "live_inputs_blocked"
    if any("placeholder for live route checks" in failure or "decimal coordinate" in failure for failure in failures):
        return "live_inputs_blocked"
    if any("live route checks skipped" in failure for failure in failures):
        return "proof_artifact_blocked"
    return "live_route_blocked"


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate BlueprintCapture city launch readiness.")
    parser.add_argument("--proof", default=str(ROOT / "ops/launch-readiness/austin-tx.launch-proof.json"))
    parser.add_argument("--release-xcconfig", default=os.environ.get("BLUEPRINT_RELEASE_XCCONFIG", str(ROOT / "Config/BlueprintCapture.release.xcconfig")))
    parser.add_argument("--backend-base-url", default=os.environ.get("BLUEPRINT_BACKEND_BASE_URL", "https://tryblueprint.io"))
    parser.add_argument("--demand-backend-base-url", default=os.environ.get("BLUEPRINT_DEMAND_BACKEND_BASE_URL", "https://us-central1-blueprint-prod-f0f19.cloudfunctions.net/api"))
    parser.add_argument("--auth-token", default=os.environ.get("BLUEPRINT_LAUNCH_AUTH_TOKEN"))
    parser.add_argument("--city-slug", default=os.environ.get("BLUEPRINT_LAUNCH_CITY_SLUG"))
    parser.add_argument("--lat", default=os.environ.get("BLUEPRINT_LAUNCH_LAT"))
    parser.add_argument("--lng", default=os.environ.get("BLUEPRINT_LAUNCH_LNG"))
    parser.add_argument("--radius-meters", type=int, default=int(os.environ.get("BLUEPRINT_LAUNCH_RADIUS_METERS", "50000")))
    parser.add_argument("--limit", type=int, default=int(os.environ.get("BLUEPRINT_LAUNCH_FEED_LIMIT", "20")))
    parser.add_argument("--contract-only", action="store_true", help="Validate schema using a contract-only proof artifact; not valid for launch signoff.")
    args = parser.parse_args()

    failures: list[str] = []
    validate_release_xcconfig(Path(args.release_xcconfig), failures)
    proof_path = Path(args.proof)
    proof = load_json(proof_path)
    validate_proof(proof, failures, args.contract_only, args.city_slug, proof_path)
    validate_live_routes(args, failures, skip_network=bool(failures))

    if failures:
        print("Launch readiness gate failed:", file=sys.stderr)
        print(f"Stage: {readiness_stage(failures)}", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        if not args.contract_only:
            print(live_input_hint(), file=sys.stderr)
        return 1

    mode = "contract-only schema check" if args.contract_only else "live launch readiness"
    print(f"Launch readiness gate passed ({mode}): {args.proof}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
