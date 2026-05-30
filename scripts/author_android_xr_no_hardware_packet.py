#!/usr/bin/env python3
import argparse
import getpass
import json
import os
import subprocess
import sys
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any

from validate_android_xr_hardware_packet import (
    EXPECTED_CLAIM_CEILING,
    NO_CLAIM_FIELDS,
    SCHEMA_VERSION,
)


GATE_BLOCKERS = {
    "HW-P0": {
        "result": "blocked",
        "failure_codes": ["xr_pairing_blocked"],
        "artifact_paths": [
            "evidence/local/git-status.txt",
            "evidence/local/git-commit.txt",
            "evidence/local/hardware-validator-fixture-check.txt",
            "evidence/blocked/HW-P0/no-hardware-blocker.md",
        ],
        "notes": "No target Android XR hardware was attached or paired. This packet is intentionally blocked.",
    },
    "HW-P1": {
        "result": "blocked_not_run",
        "failure_codes": ["projected_launch_blocked"],
        "artifact_paths": ["evidence/blocked/HW-P1/projected-launch-not-run.md"],
        "notes": "Projected activity launch was not attempted because HW-P0 is blocked by missing hardware.",
    },
    "HW-P2": {
        "result": "blocked_not_run",
        "failure_codes": ["projected_permission_blocked"],
        "artifact_paths": ["evidence/blocked/HW-P2/permissions-not-run.md"],
        "notes": "Projected camera and microphone permissions were not tested because no hardware was paired.",
    },
    "HW-P3": {
        "result": "blocked_not_run",
        "failure_codes": ["projected_camera_bind_failed", "thermal_or_battery_blocked"],
        "artifact_paths": ["evidence/blocked/HW-P3/camera-mic-thermal-not-run.md"],
        "notes": "Projected camera, microphone, voice, battery, and thermal smoke were not tested.",
    },
    "HW-P4": {
        "result": "blocked_not_run",
        "failure_codes": ["bundle_validation_failed"],
        "artifact_paths": ["evidence/blocked/HW-P4/raw-bundle-not-run.md"],
        "notes": "No physical Android XR capture occurred, so no raw bundle was finalized.",
    },
    "HW-P5": {
        "result": "blocked_not_run",
        "failure_codes": ["upload_queue_blocked"],
        "artifact_paths": ["evidence/blocked/HW-P5/upload-not-run.md"],
        "notes": "No raw bundle existed to enqueue or upload.",
    },
    "HW-P6": {
        "result": "blocked_not_run",
        "failure_codes": [
            "bridge_handoff_blocked",
            "pipeline_materialization_blocked",
            "upstream_truth_blocked",
        ],
        "artifact_paths": ["evidence/blocked/HW-P6/downstream-not-run.md"],
        "notes": "Bridge, Pipeline, and WebApp proof were not run and remain blocked for this capture id.",
    },
}


def utc_now_text() -> str:
    return datetime.now(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def parse_utc(value: str) -> datetime:
    if not value.endswith("Z"):
        raise argparse.ArgumentTypeError("--now must be a UTC timestamp ending in Z.")
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as error:
        raise argparse.ArgumentTypeError(f"--now must be valid ISO-8601: {error}") from error


def format_utc(value: datetime) -> str:
    return value.astimezone(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def safe_segment(value: str) -> str:
    allowed = []
    for char in value.lower():
        if char.isalnum() or char in {"-", "_"}:
            allowed.append(char)
        elif char.isspace() or char in {":", "/", "."}:
            allowed.append("-")
    sanitized = "".join(allowed).strip("-_")
    return sanitized or "android-xr-no-hardware"


def run_id_from(now_text: str) -> str:
    return f"android-xr-no-hardware-{safe_segment(now_text)}"


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def run_command(command: list[str], cwd: Path) -> str:
    env = os.environ.copy()
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    completed = subprocess.run(
        command,
        cwd=cwd,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    lines = [
        f"$ {' '.join(command)}",
        f"cwd: {cwd}",
        f"exit_code: {completed.returncode}",
        "",
        "stdout:",
        completed.stdout.rstrip() or "(empty)",
        "",
        "stderr:",
        completed.stderr.rstrip() or "(empty)",
        "",
    ]
    return "\n".join(lines)


def command_stdout(command: list[str], cwd: Path, fallback: str) -> str:
    completed = subprocess.run(
        command,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    value = completed.stdout.strip()
    return value or fallback


def dirty_summary(git_status_text: str) -> str:
    status_lines = [
        line
        for line in git_status_text.splitlines()
        if line and not line.startswith("$ ") and not line.startswith("cwd:") and not line.startswith("exit_code:")
    ]
    porcelain = [
        line
        for line in status_lines
        if not line.startswith("stdout:")
        and not line.startswith("stderr:")
        and line != "(empty)"
        and not line.startswith("## ")
    ]
    if not porcelain:
        return "clean local worktree; git status evidence captured"
    return f"dirty local worktree; {len(porcelain)} status line(s) captured in evidence/local/git-status.txt"


def write_blocker_notes(run_dir: Path) -> None:
    notes = {
        "HW-P0/no-hardware-blocker.md": (
            "# HW-P0 blocked\n\n"
            "No physical Android XR audio/display glasses, headset, or wired XR glasses were attached, "
            "paired, installed to, or smoke-tested for this packet. This is a repo-local blocked packet only.\n"
        ),
        "HW-P1/projected-launch-not-run.md": (
            "# HW-P1 blocked_not_run\n\n"
            "Projected activity launch was not attempted because the hardware pairing/install gate did not pass.\n"
        ),
        "HW-P2/permissions-not-run.md": (
            "# HW-P2 blocked_not_run\n\n"
            "Projected camera and microphone permission UX was not exercised without physical projected hardware.\n"
        ),
        "HW-P3/camera-mic-thermal-not-run.md": (
            "# HW-P3 blocked_not_run\n\n"
            "Projected CameraX binding, microphone capture, voice fallback, elapsed recording, and thermal/battery "
            "smoke were not run. Do not infer runtime readiness from this packet.\n"
        ),
        "HW-P4/raw-bundle-not-run.md": (
            "# HW-P4 blocked_not_run\n\n"
            "No Android XR hardware recording was produced, so there is no raw bundle, walkthrough video, "
            "manifest, recording session, or hash coverage proof for this packet.\n"
        ),
        "HW-P5/upload-not-run.md": (
            "# HW-P5 blocked_not_run\n\n"
            "No Android XR raw bundle existed to enqueue or upload. No Firebase, storage, or upload queue proof "
            "is claimed here.\n"
        ),
        "HW-P6/downstream-not-run.md": (
            "# HW-P6 blocked_not_run\n\n"
            "Bridge, Pipeline, WebApp, hosted-review, buyer-access, payout, provider, and launch proof were not "
            "run for this packet and remain blocked until a real same-capture hardware run exists.\n"
        ),
    }
    for relative_path, text in notes.items():
        write_text(run_dir / "evidence" / "blocked" / relative_path, text)


def build_packet(
    *,
    repo_root: Path,
    run_id: str,
    operator: str,
    now: datetime,
    git_branch: str,
    git_commit_sha: str,
    dirty_worktree_summary: str,
) -> dict[str, Any]:
    gates = {}
    for index, (gate_id, gate) in enumerate(GATE_BLOCKERS.items(), start=1):
        gates[gate_id] = {
            "result": gate["result"],
            "checked_at": format_utc(now + timedelta(minutes=index)),
            "failure_codes": gate["failure_codes"],
            "artifact_paths": gate["artifact_paths"],
            "notes": gate["notes"],
        }

    return {
        "schema_version": SCHEMA_VERSION,
        "packet_status": "blocked",
        "packet_note": (
            "Generated by scripts/author_android_xr_no_hardware_packet.py from local repo evidence only. "
            "This packet is not hardware proof and intentionally preserves every Android XR readiness claim as false."
        ),
        "run": {
            "run_id": run_id,
            "started_at": format_utc(now),
            "completed_at": format_utc(now + timedelta(minutes=len(GATE_BLOCKERS) + 1)),
            "operator": operator,
            "repo_path": str(repo_root),
            "git_branch": git_branch,
            "git_commit_sha": git_commit_sha,
            "dirty_worktree_summary": dirty_worktree_summary,
            "app_build_type": "offline local repo check",
            "app_version_build": "no-hardware packet; no Android build installed",
            "host_phone_model": "not attached for this offline packet",
            "host_phone_android_build": "not recorded because no host phone was used",
            "android_xr_device_type": "audio/display glasses hardware not attached",
            "android_xr_device_model": "not recorded because no Android XR hardware was attached",
            "android_xr_os_build": "not recorded because no Android XR hardware was attached",
            "pairing_method": "not paired; no physical hardware available",
            "network": "offline local repo evidence only",
            "test_account_user_id": "not used for this offline packet",
            "capture_target_label": "no physical capture target; offline blocked packet",
            "scene_id": f"scene_{safe_segment(run_id)}",
            "capture_id": f"cap_{safe_segment(run_id)}",
            "rights_basis": "no capture occurred; no new rights state asserted",
            "downstream_pipeline_webapp_validation_planned": "no; blocked until physical hardware proof exists",
        },
        "claim_ceiling": dict(EXPECTED_CLAIM_CEILING),
        "no_claims": {field: False for field in NO_CLAIM_FIELDS},
        "gates": gates,
    }


def validate_packet(repo_root: Path, run_dir: Path, packet_path: Path) -> subprocess.CompletedProcess[str]:
    validator = repo_root / "scripts" / "validate_android_xr_hardware_packet.py"
    return subprocess.run(
        [
            sys.executable,
            str(validator),
            "--packet",
            str(packet_path),
            "--evidence-root",
            str(run_dir),
            "--require-artifacts",
        ],
        cwd=repo_root,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def parse_args() -> argparse.Namespace:
    default_repo_root = Path(__file__).resolve().parents[1]
    default_operator = getpass.getuser() or "local-operator"
    default_now = utc_now_text()
    parser = argparse.ArgumentParser(
        description=(
            "Author a fail-closed Android XR hardware packet from local repo evidence only, "
            "then validate it with the existing offline validator."
        )
    )
    parser.add_argument("--repo-root", default=str(default_repo_root), help="BlueprintCapture repo root.")
    parser.add_argument("--operator", default=default_operator, help="Operator name to record in the packet.")
    parser.add_argument("--run-id", default=None, help="Run id. Defaults to android-xr-no-hardware-<UTC timestamp>.")
    parser.add_argument("--now", default=default_now, type=parse_utc, help="UTC timestamp ending in Z.")
    parser.add_argument(
        "--output-dir",
        default=str(default_repo_root / "output" / "android_xr_hardware_packets"),
        help="Directory where the run folder will be written.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repo_root = Path(args.repo_root).expanduser().resolve()
    now: datetime = args.now
    run_id = safe_segment(args.run_id) if args.run_id else run_id_from(format_utc(now))
    run_dir = Path(args.output_dir).expanduser().resolve() / run_id
    packet_path = run_dir / "packet.json"

    git_status = run_command(["git", "status", "--short", "--branch", "--untracked-files=all"], repo_root)
    git_commit = run_command(["git", "rev-parse", "HEAD"], repo_root)
    fixture_check = run_command(
        [
            sys.executable,
            "scripts/validate_android_xr_hardware_packet.py",
            "--packet",
            "docs/fixtures/android_xr_hardware_packets/blocked_no_hardware.example.json",
        ],
        repo_root,
    )

    write_text(run_dir / "evidence" / "local" / "git-status.txt", git_status)
    write_text(run_dir / "evidence" / "local" / "git-commit.txt", git_commit)
    write_text(run_dir / "evidence" / "local" / "hardware-validator-fixture-check.txt", fixture_check)
    write_blocker_notes(run_dir)

    git_branch = command_stdout(["git", "rev-parse", "--abbrev-ref", "HEAD"], repo_root, "local-branch-unavailable")
    git_commit_sha = command_stdout(["git", "rev-parse", "HEAD"], repo_root, "0000000000000000000000000000000000000000")
    packet = build_packet(
        repo_root=repo_root,
        run_id=run_id,
        operator=args.operator,
        now=now,
        git_branch=git_branch,
        git_commit_sha=git_commit_sha,
        dirty_worktree_summary=dirty_summary(git_status),
    )

    packet_path.parent.mkdir(parents=True, exist_ok=True)
    packet_path.write_text(json.dumps(packet, indent=2) + "\n", encoding="utf-8")

    validation = validate_packet(repo_root, run_dir, packet_path)
    if validation.stdout:
        print(validation.stdout.rstrip())
    if validation.stderr:
        print(validation.stderr.rstrip(), file=sys.stderr)
    if validation.returncode != 0:
        return validation.returncode

    print(f"Packet: {packet_path}")
    print(f"Evidence root: {run_dir}")
    print(
        "Validator tests: "
        "PYTHONDONTWRITEBYTECODE=1 python3 scripts/android_xr_hardware_packet_validator_tests.py"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
