#!/usr/bin/env python3
"""Unit tests for the raw-capture-bucket storage lifecycle validator (finding R042)."""

from __future__ import annotations

import copy
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True

REPO_ROOT = Path(__file__).resolve().parents[1]
VALIDATOR = REPO_ROOT / "scripts" / "validate_storage_lifecycle.py"
COMMITTED_POLICY = REPO_ROOT / "storage.lifecycle.json"

# A minimal, well-formed policy used as the base for mutation-based failure cases.
GOOD_POLICY = {
    "rule": [
        {
            "action": {"type": "SetStorageClass", "storageClass": "NEARLINE"},
            "condition": {
                "age": 90,
                "matchesPrefix": ["scenes/"],
                "matchesStorageClass": ["STANDARD"],
            },
        },
        {
            "action": {"type": "SetStorageClass", "storageClass": "COLDLINE"},
            "condition": {
                "age": 365,
                "matchesPrefix": ["scenes/"],
                "matchesStorageClass": ["STANDARD", "NEARLINE"],
            },
        },
        {
            "action": {"type": "Delete"},
            "condition": {"age": 3650, "matchesPrefix": ["scenes/"]},
        },
    ]
}


class StorageLifecycleValidatorTests(unittest.TestCase):
    def run_validator(self, lifecycle_path: Path) -> subprocess.CompletedProcess[str]:
        env = os.environ.copy()
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        return subprocess.run(
            [sys.executable, str(VALIDATOR), "--lifecycle", str(lifecycle_path)],
            env=env,
            capture_output=True,
            text=True,
        )

    def write_policy(self, policy: object) -> Path:
        tmp = tempfile.NamedTemporaryFile(
            mode="w", suffix=".json", delete=False, encoding="utf-8"
        )
        if isinstance(policy, str):
            tmp.write(policy)
        else:
            json.dump(policy, tmp)
        tmp.close()
        self.addCleanup(lambda: os.path.exists(tmp.name) and os.unlink(tmp.name))
        return Path(tmp.name)

    def assert_fails(self, policy: object, needle: str) -> None:
        result = self.run_validator(self.write_policy(policy))
        self.assertEqual(result.returncode, 1, msg=result.stdout + result.stderr)
        self.assertIn(needle, result.stderr)

    # ── The committed policy must pass, unmodified (default path and explicit path). ──

    def test_committed_policy_is_valid(self) -> None:
        self.assertTrue(COMMITTED_POLICY.exists(), "storage.lifecycle.json must be committed")
        result = self.run_validator(COMMITTED_POLICY)
        self.assertEqual(result.returncode, 0, msg=result.stdout + result.stderr)
        self.assertIn("validation passed", result.stdout)

    def test_committed_policy_default_path(self) -> None:
        env = os.environ.copy()
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        result = subprocess.run(
            [sys.executable, str(VALIDATOR)], env=env, capture_output=True, text=True
        )
        self.assertEqual(result.returncode, 0, msg=result.stdout + result.stderr)

    def test_synthetic_good_policy_passes(self) -> None:
        result = self.run_validator(self.write_policy(GOOD_POLICY))
        self.assertEqual(result.returncode, 0, msg=result.stdout + result.stderr)

    # ── Guardrail: aggressive deletion must be rejected. ──

    def test_delete_below_retention_floor_fails(self) -> None:
        policy = copy.deepcopy(GOOD_POLICY)
        policy["rule"][2]["condition"]["age"] = 400  # ~13 months -> far below 7 years
        self.assert_fails(policy, "minimum retention floor")

    def test_delete_inside_review_window_fails(self) -> None:
        policy = copy.deepcopy(GOOD_POLICY)
        policy["rule"][2]["condition"]["age"] = 30
        self.assert_fails(policy, "review/delivery window")

    def test_delete_before_coldline_fails(self) -> None:
        # Delete age respects the floor but fires before COLDLINE tiering has completed.
        policy = copy.deepcopy(GOOD_POLICY)
        policy["rule"][1]["condition"]["age"] = 4000  # COLDLINE later than delete
        policy["rule"][2]["condition"]["age"] = 3000
        self.assert_fails(policy, "strictly greater than the COLDLINE")

    # ── Guardrail: cost must be bounded by cold tiering, not deletion. ──

    def test_missing_coldline_tier_fails(self) -> None:
        policy = copy.deepcopy(GOOD_POLICY)
        del policy["rule"][1]  # drop the COLDLINE rule
        self.assert_fails(policy, "COLDLINE")

    def test_nearline_after_coldline_fails(self) -> None:
        policy = copy.deepcopy(GOOD_POLICY)
        policy["rule"][0]["condition"]["age"] = 500  # NEARLINE later than COLDLINE(365)
        self.assert_fails(policy, "COLDLINE transition")

    # ── Guardrail: the policy must stay scoped to the raw capture tree. ──

    def test_missing_scenes_prefix_fails(self) -> None:
        policy = copy.deepcopy(GOOD_POLICY)
        policy["rule"][2]["condition"].pop("matchesPrefix")
        self.assert_fails(policy, "matchesPrefix")

    def test_tiering_inside_review_window_fails(self) -> None:
        policy = copy.deepcopy(GOOD_POLICY)
        policy["rule"][0]["condition"]["age"] = 10  # tier while still under review
        self.assert_fails(policy, "review/delivery window")

    # ── Schema / well-formedness. ──

    def test_malformed_json_fails(self) -> None:
        self.assert_fails("{not valid json", "not valid JSON")

    def test_empty_rule_array_fails(self) -> None:
        self.assert_fails({"rule": []}, "non-empty 'rule' array")

    def test_unsupported_action_type_fails(self) -> None:
        policy = copy.deepcopy(GOOD_POLICY)
        policy["rule"][2]["action"]["type"] = "AbortIncompleteMultipartUpload"
        self.assert_fails(policy, "unsupported action.type")

    def test_missing_file_fails(self) -> None:
        result = self.run_validator(REPO_ROOT / "does_not_exist.json")
        self.assertEqual(result.returncode, 1, msg=result.stdout + result.stderr)
        self.assertIn("is missing", result.stderr)


if __name__ == "__main__":
    unittest.main()
