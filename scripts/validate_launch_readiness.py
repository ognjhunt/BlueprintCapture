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


def load_json(path: Path) -> dict[str, Any]:
    try:
        with path.open("r", encoding="utf-8") as handle:
            value = json.load(handle)
    except FileNotFoundError:
        raise SystemExit(f"Launch proof file not found: {path}")
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


def validate_proof(proof: dict[str, Any], failures: list[str], contract_only: bool, city_slug: str | None) -> None:
    if proof.get("contract_only") is True and not contract_only:
        failures.append("contract_only proof cannot be used for a real city launch")
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


def validate_live_routes(args: argparse.Namespace, failures: list[str]) -> None:
    if args.contract_only:
        return
    if not args.auth_token:
        failures.append("BLUEPRINT_LAUNCH_AUTH_TOKEN or --auth-token is required for live creator launch/Stripe route checks")
        return
    if not args.city_slug:
        failures.append("--city-slug is required for live launch route checks")
        return
    if args.lat is None or args.lng is None:
        failures.append("--lat and --lng are required for live demand feed checks")
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
        "lat": args.lat,
        "lng": args.lng,
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


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate BlueprintCapture city launch readiness.")
    parser.add_argument("--proof", default=str(ROOT / "ops/launch-readiness/austin-tx.launch-proof.json"))
    parser.add_argument("--release-xcconfig", default=os.environ.get("BLUEPRINT_RELEASE_XCCONFIG", str(ROOT / "Config/BlueprintCapture.release.xcconfig")))
    parser.add_argument("--backend-base-url", default=os.environ.get("BLUEPRINT_BACKEND_BASE_URL", "https://tryblueprint.io"))
    parser.add_argument("--demand-backend-base-url", default=os.environ.get("BLUEPRINT_DEMAND_BACKEND_BASE_URL", "https://us-central1-blueprint-prod-f0f19.cloudfunctions.net/api"))
    parser.add_argument("--auth-token", default=os.environ.get("BLUEPRINT_LAUNCH_AUTH_TOKEN"))
    parser.add_argument("--city-slug", default=os.environ.get("BLUEPRINT_LAUNCH_CITY_SLUG"))
    parser.add_argument("--lat", type=float, default=float(os.environ["BLUEPRINT_LAUNCH_LAT"]) if os.environ.get("BLUEPRINT_LAUNCH_LAT") else None)
    parser.add_argument("--lng", type=float, default=float(os.environ["BLUEPRINT_LAUNCH_LNG"]) if os.environ.get("BLUEPRINT_LAUNCH_LNG") else None)
    parser.add_argument("--radius-meters", type=int, default=int(os.environ.get("BLUEPRINT_LAUNCH_RADIUS_METERS", "50000")))
    parser.add_argument("--limit", type=int, default=int(os.environ.get("BLUEPRINT_LAUNCH_FEED_LIMIT", "20")))
    parser.add_argument("--contract-only", action="store_true", help="Validate schema using a contract-only proof artifact; not valid for launch signoff.")
    args = parser.parse_args()

    failures: list[str] = []
    validate_release_xcconfig(Path(args.release_xcconfig), failures)
    proof = load_json(Path(args.proof))
    validate_proof(proof, failures, args.contract_only, args.city_slug)
    validate_live_routes(args, failures)

    if failures:
        print("Launch readiness gate failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1

    mode = "contract-only schema check" if args.contract_only else "live launch readiness"
    print(f"Launch readiness gate passed ({mode}): {args.proof}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
