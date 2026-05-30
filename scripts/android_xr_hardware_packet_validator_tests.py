#!/usr/bin/env python3
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
FIXTURE_DIR = REPO_ROOT / "docs" / "fixtures" / "android_xr_hardware_packets"


class AndroidXrHardwarePacketValidatorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.validator = REPO_ROOT / "scripts" / "validate_android_xr_hardware_packet.py"
        self.author = REPO_ROOT / "scripts" / "author_android_xr_no_hardware_packet.py"
        self.completed_fixture = FIXTURE_DIR / "completed_video_first.example.json"
        self.blocked_fixture = FIXTURE_DIR / "blocked_no_hardware.example.json"

    def run_validator(
        self,
        packet: Path,
        *extra_args: str,
        extra_env: dict[str, str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        env = os.environ.copy()
        env.pop("BLUEPRINT_ANDROID_XR_RELEASE_PROOF_PATH", None)
        env.pop("BLUEPRINT_ANDROID_XR_RELEASE_TRACK", None)
        env.update(extra_env or {})
        return subprocess.run(
            [
                sys.executable,
                str(self.validator),
                "--packet",
                str(packet),
                *extra_args,
            ],
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )

    def packet_copy(self, source: Path, mutator) -> Path:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        destination = Path(tmp.name) / "packet.json"
        packet = json.loads(source.read_text())
        mutator(packet)
        destination.write_text(json.dumps(packet, indent=2) + "\n")
        return destination

    def test_completed_video_first_fixture_validates_without_release_config(self) -> None:
        result = self.run_validator(self.completed_fixture)

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("validated offline", result.stdout)
        self.assertIn("packet_status=completed", result.stdout)
        self.assertIn("no hardware or downstream readiness claims", result.stdout)

    def test_blocked_fixture_validates_without_hardware_or_credentials(self) -> None:
        result = self.run_validator(self.blocked_fixture)

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("validated offline", result.stdout)
        self.assertIn("packet_status=blocked", result.stdout)
        self.assertIn("blocked gates: HW-P0", result.stdout)

    def test_rejects_hardware_readiness_overclaim(self) -> None:
        packet = self.packet_copy(
            self.blocked_fixture,
            lambda payload: payload["no_claims"].__setitem__("hardware_ready", True),
        )

        result = self.run_validator(packet)

        self.assertNotEqual(0, result.returncode)
        self.assertIn("Stage: android_xr_hardware_packet_blocked", result.stderr)
        self.assertIn("no_claims.hardware_ready must be false", result.stderr)

    def test_rejects_blocked_gate_without_failure_code(self) -> None:
        def mutate(payload: dict) -> None:
            payload["gates"]["HW-P0"]["failure_codes"] = []

        packet = self.packet_copy(self.blocked_fixture, mutate)

        result = self.run_validator(packet)

        self.assertNotEqual(0, result.returncode)
        self.assertIn("HW-P0", result.stderr)
        self.assertIn("failure_codes", result.stderr)

    def test_rejects_non_utc_timestamp(self) -> None:
        def mutate(payload: dict) -> None:
            payload["run"]["started_at"] = "2026-05-24 10:00:00"

        packet = self.packet_copy(self.blocked_fixture, mutate)

        result = self.run_validator(packet)

        self.assertNotEqual(0, result.returncode)
        self.assertIn("run.started_at", result.stderr)
        self.assertIn("UTC ISO-8601", result.stderr)

    def test_no_hardware_author_writes_self_contained_blocked_packet(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            output_dir = Path(tmp) / "packets"
            result = subprocess.run(
                [
                    sys.executable,
                    str(self.author),
                    "--operator",
                    "validator-test",
                    "--run-id",
                    "android-xr-no-hardware-validator-test",
                    "--now",
                    "2026-05-24T14:00:00Z",
                    "--output-dir",
                    str(output_dir),
                ],
                cwd=REPO_ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

            self.assertEqual(0, result.returncode, result.stderr)
            self.assertIn("packet_status=blocked", result.stdout)
            self.assertIn("blocked gates: HW-P0, HW-P1, HW-P2, HW-P3, HW-P4, HW-P5, HW-P6", result.stdout)

            run_dir = output_dir / "android-xr-no-hardware-validator-test"
            packet_path = run_dir / "packet.json"
            self.assertTrue(packet_path.exists())

            packet = json.loads(packet_path.read_text())
            self.assertEqual("blocked", packet["packet_status"])
            self.assertEqual("android_xr_glasses", packet["claim_ceiling"]["capture_profile_id"])
            self.assertTrue(all(value is False for value in packet["no_claims"].values()))

            validation = self.run_validator(
                packet_path,
                "--evidence-root",
                str(run_dir),
                "--require-artifacts",
            )
            self.assertEqual(0, validation.returncode, validation.stderr)
            self.assertIn("blocked gates: HW-P0", validation.stdout)

    def test_can_require_artifact_paths_to_exist_for_physical_packets(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            evidence_root = Path(tmp)
            artifact = evidence_root / "evidence" / "blocked" / "HW-P0" / "pairing-note.txt"
            artifact.parent.mkdir(parents=True)
            artifact.write_text("pairing blocked before hardware proof\n")

            result = self.run_validator(
                self.blocked_fixture,
                "--evidence-root",
                str(evidence_root),
                "--require-artifacts",
            )

        self.assertNotEqual(0, result.returncode)
        self.assertIn("Missing artifact path", result.stderr)
        self.assertIn("HW-P1", result.stderr)


if __name__ == "__main__":
    unittest.main()
