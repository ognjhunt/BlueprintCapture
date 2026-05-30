#!/usr/bin/env python3
import argparse
import json
import re
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any


SCHEMA_VERSION = "android_xr_hardware_validation_packet_v1"
REQUIRED_GATES = ("HW-P0", "HW-P1", "HW-P2", "HW-P3", "HW-P4", "HW-P5", "HW-P6")
HARDWARE_GATES = ("HW-P0", "HW-P1", "HW-P2", "HW-P3", "HW-P4", "HW-P5")
ALLOWED_GATE_RESULTS = {"pass", "blocked", "blocked_not_run", "fail", "not_run"}
ALLOWED_PACKET_STATUSES = {"completed", "blocked"}
ALLOWED_FAILURE_CODES = {
    "xr_pairing_blocked",
    "projected_launch_blocked",
    "projected_permission_blocked",
    "display_capability_mismatch",
    "projected_camera_bind_failed",
    "recording_finalize_failed",
    "voice_truth_mismatch",
    "bundle_validation_failed",
    "hash_coverage_missing",
    "upload_queue_blocked",
    "bridge_handoff_blocked",
    "pipeline_materialization_blocked",
    "upstream_truth_blocked",
    "thermal_or_battery_blocked",
}
DOWNSTREAM_FAILURE_CODES = {
    "bridge_handoff_blocked",
    "pipeline_materialization_blocked",
    "upstream_truth_blocked",
}
EXPECTED_CLAIM_CEILING = {
    "capture_source": "glasses",
    "capture_tier_hint": "tier2_glasses",
    "capture_profile_id": "android_xr_glasses",
    "capture_modality": "android_xr_video_only",
    "world_frame_definition": "unavailable_no_public_world_tracking",
}
NO_CLAIM_FIELDS = (
    "hardware_ready",
    "public_or_external_alpha_ready",
    "launch_ready",
    "payout_ready",
    "provider_ready",
    "buyer_access_ready",
    "hosted_review_ready",
    "native_pose_ready",
    "native_imu_ready",
    "depth_ready",
    "geospatial_ready",
    "pipeline_quality_ready",
    "world_model_ready",
    "gemini_live_ready",
)
REQUIRED_RUN_FIELDS = (
    "run_id",
    "operator",
    "repo_path",
    "git_branch",
    "git_commit_sha",
    "dirty_worktree_summary",
    "app_build_type",
    "app_version_build",
    "host_phone_model",
    "host_phone_android_build",
    "android_xr_device_type",
    "android_xr_device_model",
    "android_xr_os_build",
    "pairing_method",
    "network",
    "test_account_user_id",
    "capture_target_label",
    "scene_id",
    "capture_id",
    "rights_basis",
    "downstream_pipeline_webapp_validation_planned",
)
UTC_ISO_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$")
REMOTE_PATH_PREFIXES = ("https://", "http://", "gs://", "s3://", "ticket://")
PLACEHOLDER_TOKENS = ("replace-with", "todo", "tbd", "<", ">")


@dataclass
class GateFailure(Exception):
    stage: str
    next_input: str
    details: list[str]


def fail(stage: str, next_input: str, *details: str) -> None:
    raise GateFailure(stage=stage, next_input=next_input, details=list(details))


def print_failure(error: GateFailure) -> None:
    print("Android XR hardware packet validation failed:", file=sys.stderr)
    print(f"Stage: {error.stage}", file=sys.stderr)
    print(f"Next input needed: {error.next_input}", file=sys.stderr)
    for detail in error.details:
        print(f"- {detail}", file=sys.stderr)


def load_json(path: Path) -> dict[str, Any]:
    try:
        parsed = json.loads(path.read_text())
    except FileNotFoundError:
        fail(
            "android_xr_hardware_packet_blocked",
            "Point --packet at an existing Android XR hardware packet JSON file.",
            f"Missing packet file: {path}",
        )
    except json.JSONDecodeError as error:
        fail(
            "android_xr_hardware_packet_blocked",
            "Provide a valid JSON Android XR hardware packet.",
            f"{path}: {error}",
        )
    if not isinstance(parsed, dict):
        fail(
            "android_xr_hardware_packet_blocked",
            "Provide a JSON object Android XR hardware packet.",
            f"{path} did not contain a JSON object.",
        )
    return parsed


def require_object(parent: dict[str, Any], key: str) -> dict[str, Any]:
    value = parent.get(key)
    if not isinstance(value, dict):
        fail(
            "android_xr_hardware_packet_blocked",
            f"Record {key} as a JSON object.",
            f"Missing object: {key}",
        )
    return value


def require_non_blank(parent: dict[str, Any], key: str, label: str) -> str:
    value = parent.get(key)
    if not isinstance(value, str) or not value.strip():
        fail(
            "android_xr_hardware_packet_blocked",
            f"Record {label}.",
            f"Missing or blank field: {label}",
        )
    if looks_placeholder(value):
        fail(
            "android_xr_hardware_packet_blocked",
            f"Replace placeholder text in {label}.",
            f"{label} contains placeholder text: {value!r}",
        )
    return value.strip()


def looks_placeholder(value: str) -> bool:
    lowered = value.lower()
    return any(token in lowered for token in PLACEHOLDER_TOKENS)


def parse_utc_timestamp(parent: dict[str, Any], key: str, label: str) -> datetime:
    value = require_non_blank(parent, key, label)
    if not UTC_ISO_RE.match(value):
        fail(
            "android_xr_hardware_packet_blocked",
            f"Record {label} as a UTC ISO-8601 timestamp ending in Z.",
            f"{label} must be UTC ISO-8601 like 2026-05-24T12:00:00Z; received {value!r}.",
        )
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def validate_run(packet: dict[str, Any]) -> None:
    run = require_object(packet, "run")
    started_at = parse_utc_timestamp(run, "started_at", "run.started_at")
    completed_at = parse_utc_timestamp(run, "completed_at", "run.completed_at")
    if completed_at < started_at:
        fail(
            "android_xr_hardware_packet_blocked",
            "Make run.completed_at greater than or equal to run.started_at.",
            "run.completed_at is earlier than run.started_at.",
        )
    for field in REQUIRED_RUN_FIELDS:
        require_non_blank(run, field, f"run.{field}")


def validate_claim_ceiling(packet: dict[str, Any]) -> None:
    claim_ceiling = require_object(packet, "claim_ceiling")
    for key, expected in EXPECTED_CLAIM_CEILING.items():
        actual = claim_ceiling.get(key)
        if actual != expected:
            fail(
                "android_xr_hardware_packet_blocked",
                "Keep the current Android XR packet claim ceiling video-first and no-sidecar.",
                f"claim_ceiling.{key} must be {expected!r}; received {actual!r}.",
            )


def validate_no_claims(packet: dict[str, Any]) -> None:
    no_claims = require_object(packet, "no_claims")
    for key in NO_CLAIM_FIELDS:
        actual = no_claims.get(key)
        if actual is not False:
            fail(
                "android_xr_hardware_packet_blocked",
                "Keep Android XR readiness and downstream claims explicitly false until direct proof exists.",
                f"no_claims.{key} must be false; received {actual!r}.",
            )


def validate_failure_codes(gate_id: str, result: str, gate: dict[str, Any]) -> list[str]:
    raw_codes = gate.get("failure_codes")
    if not isinstance(raw_codes, list) or not all(isinstance(code, str) for code in raw_codes):
        fail(
            "android_xr_hardware_packet_blocked",
            f"Record {gate_id}.failure_codes as a list of strings.",
            f"{gate_id}.failure_codes is missing or malformed.",
        )
    codes = [code.strip() for code in raw_codes if code.strip()]
    unknown = sorted(set(codes) - ALLOWED_FAILURE_CODES)
    if unknown:
        fail(
            "android_xr_hardware_packet_blocked",
            "Use only documented Android XR hardware failure codes.",
            f"{gate_id}.failure_codes contains unknown code(s): {', '.join(unknown)}.",
        )
    if result == "pass" and codes:
        fail(
            "android_xr_hardware_packet_blocked",
            "Remove failure codes from passing Android XR hardware gates.",
            f"{gate_id}.result is pass but failure_codes is not empty.",
        )
    if result != "pass" and not codes:
        fail(
            "android_xr_hardware_packet_blocked",
            f"Record at least one documented failure code for {gate_id}.",
            f"{gate_id}.result is {result!r}, but failure_codes is empty.",
        )
    return codes


def validate_artifact_paths(
    packet_path: Path,
    evidence_root: Path | None,
    require_artifacts: bool,
    gate_id: str,
    gate: dict[str, Any],
) -> None:
    raw_paths = gate.get("artifact_paths")
    if not isinstance(raw_paths, list) or not all(isinstance(path, str) for path in raw_paths):
        fail(
            "android_xr_hardware_packet_blocked",
            f"Record {gate_id}.artifact_paths as a non-empty list of strings.",
            f"{gate_id}.artifact_paths is missing or malformed.",
        )
    paths = [path.strip() for path in raw_paths if path.strip()]
    if not paths:
        fail(
            "android_xr_hardware_packet_blocked",
            f"Record at least one artifact path for {gate_id}.",
            f"{gate_id}.artifact_paths is empty.",
        )
    for path in paths:
        if "\x00" in path or "\n" in path or looks_placeholder(path):
            fail(
                "android_xr_hardware_packet_blocked",
                "Use concrete, non-placeholder artifact paths in Android XR hardware packets.",
                f"{gate_id}.artifact_paths contains invalid path: {path!r}.",
            )
        if not require_artifacts or path.startswith(REMOTE_PATH_PREFIXES):
            continue
        candidate = Path(path).expanduser()
        if not candidate.is_absolute():
            candidate = (evidence_root or packet_path.parent) / candidate
        if not candidate.exists():
            fail(
                "android_xr_hardware_packet_blocked",
                "Attach or pull the referenced local evidence artifact before requiring artifact existence.",
                f"Missing artifact path for {gate_id}: {candidate}",
            )


def validate_gates(
    packet_path: Path,
    evidence_root: Path | None,
    require_artifacts: bool,
    packet_status: str,
    packet: dict[str, Any],
) -> list[str]:
    gates = require_object(packet, "gates")
    missing = [gate_id for gate_id in REQUIRED_GATES if gate_id not in gates]
    if missing:
        fail(
            "android_xr_hardware_packet_blocked",
            "Record every required Android XR hardware validation gate.",
            f"Missing gate(s): {', '.join(missing)}.",
        )

    blocked_gates: list[str] = []
    for gate_id in REQUIRED_GATES:
        gate = gates[gate_id]
        if not isinstance(gate, dict):
            fail(
                "android_xr_hardware_packet_blocked",
                f"Record {gate_id} as a JSON object.",
                f"{gate_id} is not an object.",
            )
        result = gate.get("result")
        if result not in ALLOWED_GATE_RESULTS:
            fail(
                "android_xr_hardware_packet_blocked",
                "Use a documented Android XR hardware gate result.",
                f"{gate_id}.result must be one of {sorted(ALLOWED_GATE_RESULTS)}; received {result!r}.",
            )
        parse_utc_timestamp(gate, "checked_at", f"gates.{gate_id}.checked_at")
        validate_artifact_paths(packet_path, evidence_root, require_artifacts, gate_id, gate)
        failure_codes = validate_failure_codes(gate_id, result, gate)
        if result != "pass":
            blocked_gates.append(gate_id)
        if gate_id == "HW-P6" and result != "pass" and not (set(failure_codes) & DOWNSTREAM_FAILURE_CODES):
            fail(
                "android_xr_hardware_packet_blocked",
                "Use a downstream blocker code when HW-P6 bridge/pipeline/webapp is not passing.",
                f"HW-P6.failure_codes must include one of {sorted(DOWNSTREAM_FAILURE_CODES)}.",
            )

    if packet_status == "completed":
        for gate_id in HARDWARE_GATES:
            result = gates[gate_id]["result"]
            if result != "pass":
                fail(
                    "android_xr_hardware_packet_blocked",
                    "Completed Android XR hardware packets require HW-P0 through HW-P5 to pass.",
                    f"{gate_id}.result is {result!r}; expected 'pass'.",
                )
        if gates["HW-P6"]["result"] not in {"pass", "blocked_not_run"}:
            fail(
                "android_xr_hardware_packet_blocked",
                "Completed hardware-only packets may pass HW-P6 or mark it blocked_not_run.",
                f"HW-P6.result is {gates['HW-P6']['result']!r}.",
            )
    if packet_status == "blocked" and not blocked_gates:
        fail(
            "android_xr_hardware_packet_blocked",
            "Blocked Android XR hardware packets must name at least one blocked gate.",
            "packet_status is blocked but every gate passed.",
        )
    return blocked_gates


def validate_packet(
    packet_path: Path,
    evidence_root: Path | None,
    require_artifacts: bool,
) -> tuple[str, list[str]]:
    packet = load_json(packet_path)
    schema_version = require_non_blank(packet, "schema_version", "schema_version")
    if schema_version != SCHEMA_VERSION:
        fail(
            "android_xr_hardware_packet_blocked",
            f"Use schema_version {SCHEMA_VERSION} for Android XR hardware packets.",
            f"Received schema_version: {schema_version}",
        )
    packet_status = require_non_blank(packet, "packet_status", "packet_status")
    if packet_status not in ALLOWED_PACKET_STATUSES:
        fail(
            "android_xr_hardware_packet_blocked",
            "Set packet_status to completed or blocked.",
            f"Received packet_status: {packet_status!r}.",
        )
    validate_run(packet)
    validate_claim_ceiling(packet)
    validate_no_claims(packet)
    blocked_gates = validate_gates(packet_path, evidence_root, require_artifacts, packet_status, packet)
    return packet_status, blocked_gates


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate an offline Android XR hardware evidence packet without hardware or release config."
    )
    parser.add_argument("--packet", required=True, help="Path to an Android XR hardware packet JSON file.")
    parser.add_argument(
        "--evidence-root",
        default=None,
        help="Optional root for resolving relative artifact paths when --require-artifacts is set.",
    )
    parser.add_argument(
        "--require-artifacts",
        action="store_true",
        help="Require local artifact paths in the packet to exist. Remote URLs are shape-checked only.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    packet_path = Path(args.packet).expanduser().resolve()
    evidence_root = Path(args.evidence_root).expanduser().resolve() if args.evidence_root else None
    try:
        packet_status, blocked_gates = validate_packet(
            packet_path=packet_path,
            evidence_root=evidence_root,
            require_artifacts=args.require_artifacts,
        )
    except GateFailure as error:
        print_failure(error)
        return 1

    blocked_text = ", ".join(blocked_gates) if blocked_gates else "none"
    print(
        "Android XR hardware packet validated offline: "
        f"packet_status={packet_status}; blocked gates: {blocked_text}; "
        "no hardware or downstream readiness claims asserted."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
