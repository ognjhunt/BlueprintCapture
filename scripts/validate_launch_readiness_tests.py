#!/usr/bin/env python3
"""Unit tests for the iOS city-launch readiness validator."""

from __future__ import annotations

import importlib.util
import io
import sys
import types
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import mock

sys.dont_write_bytecode = True


ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "scripts" / "validate_launch_readiness.py"

spec = importlib.util.spec_from_file_location("validate_launch_readiness", MODULE_PATH)
if spec is None or spec.loader is None:
    raise RuntimeError(f"Unable to load validator module from {MODULE_PATH}")
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


class LaunchReadinessValidatorTests(unittest.TestCase):
    def test_contract_only_proof_cannot_be_used_for_real_launch(self) -> None:
        proof_path = ROOT / "ops" / "launch-readiness" / "example.launch-proof.json"
        proof = validator.load_json(proof_path)
        failures: list[str] = []

        validator.validate_proof(proof, failures, contract_only=False, city_slug=None, proof_path=proof_path)

        self.assertIn("contract_only proof cannot be used for a real city launch", failures)
        self.assertIn("ops/launch-readiness/example.launch-proof.json cannot be used for a real city launch", failures)

    def test_contract_only_mode_allows_example_proof_schema(self) -> None:
        proof_path = ROOT / "ops" / "launch-readiness" / "example.launch-proof.json"
        proof = validator.load_json(proof_path)
        failures: list[str] = []

        validator.validate_proof(proof, failures, contract_only=True, city_slug=None, proof_path=proof_path)

        self.assertEqual([], failures)

    def test_real_proof_rejects_placeholder_string_values(self) -> None:
        proof = validator.load_json(ROOT / "ops" / "launch-readiness" / "example.launch-proof.json")
        proof["contract_only"] = False
        proof["city_slug"] = "austin-tx"
        proof["ops"]["launch_owner"] = "example-owner"
        failures: list[str] = []

        validator.validate_proof(
            proof,
            failures,
            contract_only=False,
            city_slug="austin-tx",
            proof_path=ROOT / "ops" / "launch-readiness" / "austin-tx.launch-proof.json",
        )

        self.assertIn("ops.launch_owner contains placeholder proof text: example-owner", failures)

    def test_real_proof_placeholder_scan_ignores_diagnostic_harness_logs(self) -> None:
        proof = self.real_proof_fixture()
        proof["harness"] = {
            "release_config_validation": {
                "stderr_tail": "Xcode listed Any iOS Device and DVTiPhonePlaceholder in destination output"
            }
        }
        failures: list[str] = []

        validator.validate_proof(
            proof,
            failures,
            contract_only=False,
            city_slug="austin-tx",
            proof_path=ROOT / "ops" / "launch-readiness" / "austin-tx.launch-proof.json",
        )

        self.assertEqual([], failures)

    def test_real_proof_requires_explicit_false_contract_only_and_launch_proof_filename(self) -> None:
        proof = self.real_proof_fixture()
        del proof["contract_only"]
        failures: list[str] = []

        validator.validate_proof(
            proof,
            failures,
            contract_only=False,
            city_slug="austin-tx",
            proof_path=ROOT / "ops" / "launch-readiness" / "austin-tx.json",
        )

        self.assertIn("real launch proof must set contract_only to false", failures)
        self.assertIn("real launch proof filename must end with .launch-proof.json", failures)

    def test_real_proof_requires_evidence_references(self) -> None:
        proof = self.real_proof_fixture()
        del proof["evidence"]["pipeline_qa_report"]
        failures: list[str] = []

        validator.validate_proof(
            proof,
            failures,
            contract_only=False,
            city_slug="austin-tx",
            proof_path=ROOT / "ops" / "launch-readiness" / "austin-tx.launch-proof.json",
        )

        self.assertIn("evidence.pipeline_qa_report must be a non-empty string", failures)

    def test_real_proof_rejects_status_text_as_evidence_reference(self) -> None:
        proof = self.real_proof_fixture()
        proof["evidence"]["pipeline_qa_report"] = "done"
        failures: list[str] = []

        validator.validate_proof(
            proof,
            failures,
            contract_only=False,
            city_slug="austin-tx",
            proof_path=ROOT / "ops" / "launch-readiness" / "austin-tx.launch-proof.json",
        )

        self.assertIn("evidence.pipeline_qa_report must point to concrete evidence, not status text: done", failures)
        self.assertIn("evidence.pipeline_qa_report must include an inspectable evidence reference: done", failures)

    def test_real_proof_accepts_non_placeholder_evidence_references(self) -> None:
        proof = self.real_proof_fixture()
        failures: list[str] = []

        validator.validate_proof(
            proof,
            failures,
            contract_only=False,
            city_slug="austin-tx",
            proof_path=ROOT / "ops" / "launch-readiness" / "austin-tx.launch-proof.json",
        )

        self.assertEqual([], failures)

    def test_live_route_validation_reports_all_missing_inputs(self) -> None:
        args = types.SimpleNamespace(
            contract_only=False,
            auth_token=None,
            city_slug=None,
            lat=None,
            lng=None,
            backend_base_url="https://tryblueprint.io",
            demand_backend_base_url="https://us-central1-blueprint-prod-f0f19.cloudfunctions.net/api",
        )
        failures: list[str] = []

        validator.validate_live_routes(args, failures)

        self.assertIn(
            "BLUEPRINT_LAUNCH_AUTH_TOKEN or --auth-token is required for live creator launch/Stripe route checks",
            failures,
        )
        self.assertIn("BLUEPRINT_LAUNCH_CITY_SLUG or --city-slug is required for live launch route checks", failures)
        self.assertIn("BLUEPRINT_LAUNCH_LAT or --lat is required for live demand feed checks", failures)
        self.assertIn("BLUEPRINT_LAUNCH_LNG or --lng is required for live demand feed checks", failures)

    def test_live_route_validation_rejects_placeholder_inputs_before_network(self) -> None:
        args = types.SimpleNamespace(
            contract_only=False,
            auth_token="placeholder-token",
            city_slug="example-city",
            lat="<latitude>",
            lng="tbd",
            backend_base_url="https://tryblueprint.io",
            demand_backend_base_url="https://us-central1-blueprint-prod-f0f19.cloudfunctions.net/api",
        )
        failures: list[str] = []

        validator.validate_live_routes(args, failures)

        self.assertIn(
            "BLUEPRINT_LAUNCH_AUTH_TOKEN or --auth-token cannot be a placeholder for live route checks",
            failures,
        )
        self.assertIn(
            "BLUEPRINT_LAUNCH_CITY_SLUG or --city-slug cannot be a placeholder for live route checks: example-city",
            failures,
        )
        self.assertIn(
            "BLUEPRINT_LAUNCH_LAT or --lat cannot be a placeholder for live route checks: <latitude>",
            failures,
        )
        self.assertIn(
            "BLUEPRINT_LAUNCH_LNG or --lng cannot be a placeholder for live route checks: tbd",
            failures,
        )

    def test_live_route_validation_rejects_invalid_coordinates_before_network(self) -> None:
        args = types.SimpleNamespace(
            contract_only=False,
            auth_token="firebase-id-token-live-route-check",
            city_slug="austin-tx",
            lat="north",
            lng="west",
            backend_base_url="https://tryblueprint.io",
            demand_backend_base_url="https://us-central1-blueprint-prod-f0f19.cloudfunctions.net/api",
        )
        failures: list[str] = []

        validator.validate_live_routes(args, failures)

        self.assertIn(
            "BLUEPRINT_LAUNCH_LAT or --lat must be a decimal coordinate for live demand feed checks: north",
            failures,
        )
        self.assertIn(
            "BLUEPRINT_LAUNCH_LNG or --lng must be a decimal coordinate for live demand feed checks: west",
            failures,
        )

    def test_live_route_validation_can_skip_network_after_prior_failures(self) -> None:
        args = types.SimpleNamespace(
            contract_only=False,
            auth_token="token-present",
            city_slug="austin-tx",
            lat=30.2672,
            lng=-97.7431,
            backend_base_url="https://tryblueprint.io",
            demand_backend_base_url="https://us-central1-blueprint-prod-f0f19.cloudfunctions.net/api",
        )
        failures: list[str] = []

        validator.validate_live_routes(args, failures, skip_network=True)

        self.assertEqual(
            ["live route checks skipped until release config and proof artifact failures are resolved"],
            failures,
        )

    def test_readiness_stage_classifies_blockers(self) -> None:
        self.assertEqual("ready", validator.readiness_stage([]))
        self.assertEqual(
            "release_config_blocked",
            validator.readiness_stage(["Release xcconfig not found: /tmp/missing.xcconfig"]),
        )
        self.assertEqual("release_config_blocked", validator.readiness_stage(["APS_ENVIRONMENT must be set in release.xcconfig"]))
        self.assertEqual(
            "proof_artifact_blocked",
            validator.readiness_stage(["evidence.pipeline_qa_report must be a non-empty string"]),
        )
        self.assertEqual(
            "proof_artifact_blocked",
            validator.readiness_stage(["Launch proof file not found: /tmp/missing.launch-proof.json"]),
        )
        self.assertEqual(
            "live_inputs_blocked",
            validator.readiness_stage(["BLUEPRINT_LAUNCH_LAT or --lat is required for live demand feed checks"]),
        )
        self.assertEqual(
            "live_route_blocked",
            validator.readiness_stage(["launch-status route returned HTTP 401: {}"]),
        )

    def test_live_input_hint_names_required_env_vars(self) -> None:
        hint = validator.live_input_hint()

        self.assertIn("BLUEPRINT_LAUNCH_PROOF_PATH", hint)
        self.assertIn("BLUEPRINT_LAUNCH_AUTH_TOKEN", hint)
        self.assertIn("BLUEPRINT_LAUNCH_CITY_SLUG", hint)
        self.assertIn("BLUEPRINT_LAUNCH_LAT", hint)
        self.assertIn("BLUEPRINT_LAUNCH_LNG", hint)
        self.assertIn("contract-only", hint)

    def test_main_reports_stage_and_next_input_when_release_config_missing(self) -> None:
        proof_path = ROOT / "ops" / "launch-readiness" / "example.launch-proof.json"
        stderr = io.StringIO()
        stdout = io.StringIO()

        with mock.patch.object(
            sys,
            "argv",
            [
                "validate_launch_readiness.py",
                "--contract-only",
                "--release-xcconfig",
                "/tmp/missing-blueprint-release.xcconfig",
                "--proof",
                str(proof_path),
            ],
        ):
            with redirect_stdout(stdout), redirect_stderr(stderr):
                exit_code = validator.main()

        self.assertEqual(1, exit_code)
        self.assertIn("Stage: release_config_blocked", stderr.getvalue())
        self.assertIn("Next input needed:", stderr.getvalue())
        self.assertIn("Copy ConfigTemplates/BlueprintCapture.release.xcconfig.example", stderr.getvalue())

    def test_main_reports_stage_and_next_input_when_launch_proof_missing(self) -> None:
        with TemporaryDirectory() as temp_dir:
            release_xcconfig = Path(temp_dir) / "BlueprintCapture.release.xcconfig"
            release_xcconfig.write_text(self.valid_release_xcconfig(), encoding="utf-8")
            missing_proof = Path(temp_dir) / "missing.launch-proof.json"
            stderr = io.StringIO()
            stdout = io.StringIO()

            with mock.patch.object(
                sys,
                "argv",
                [
                    "validate_launch_readiness.py",
                    "--contract-only",
                    "--release-xcconfig",
                    str(release_xcconfig),
                    "--proof",
                    str(missing_proof),
                ],
            ):
                with redirect_stdout(stdout), redirect_stderr(stderr):
                    exit_code = validator.main()

        self.assertEqual(1, exit_code)
        self.assertIn("Stage: proof_artifact_blocked", stderr.getvalue())
        self.assertIn("Next input needed:", stderr.getvalue())
        self.assertIn("Provide a real city launch proof artifact", stderr.getvalue())

    def test_main_contract_only_defaults_to_example_proof(self) -> None:
        with TemporaryDirectory() as temp_dir:
            release_xcconfig = Path(temp_dir) / "BlueprintCapture.release.xcconfig"
            release_xcconfig.write_text(self.valid_release_xcconfig(), encoding="utf-8")
            stderr = io.StringIO()
            stdout = io.StringIO()

            with mock.patch.object(
                sys,
                "argv",
                [
                    "validate_launch_readiness.py",
                    "--contract-only",
                    "--release-xcconfig",
                    str(release_xcconfig),
                ],
            ):
                with redirect_stdout(stdout), redirect_stderr(stderr):
                    exit_code = validator.main()

        self.assertEqual(0, exit_code)
        self.assertIn("Launch readiness gate passed (contract-only schema check; not live launch signoff)", stdout.getvalue())
        self.assertIn("example.launch-proof.json", stdout.getvalue())

    def valid_release_xcconfig(self) -> str:
        return "\n".join(
            [
                "BLUEPRINT_BACKEND_BASE_URL = https://creator.tryblueprint.io",
                "BLUEPRINT_DEMAND_BACKEND_BASE_URL = https://us-central1-blueprint-prod-f0f19.cloudfunctions.net/api",
                "BLUEPRINT_MAIN_WEBSITE_URL = https://www.tryblueprint.io",
                "BLUEPRINT_HELP_CENTER_URL = https://www.tryblueprint.io/help",
                "BLUEPRINT_BUG_REPORT_URL = https://www.tryblueprint.io/support/bug-report",
                "BLUEPRINT_TERMS_OF_SERVICE_URL = https://www.tryblueprint.io/terms",
                "BLUEPRINT_PRIVACY_POLICY_URL = https://www.tryblueprint.io/privacy",
                "BLUEPRINT_CAPTURE_POLICY_URL = https://www.tryblueprint.io/capture-policy",
                "BLUEPRINT_ACCOUNT_DELETION_URL = https://www.tryblueprint.io/account/delete",
                "BLUEPRINT_SUPPORT_EMAIL_ADDRESS = support@blueprint.app",
                "BLUEPRINT_NEARBY_DISCOVERY_PROVIDER = places_nearby",
                "BLUEPRINT_ALLOW_MOCK_JOBS_FALLBACK = NO",
                "BLUEPRINT_ENABLE_INTERNAL_TEST_SPACE = NO",
                "BLUEPRINT_ENABLE_REMOTE_NOTIFICATIONS = YES",
                "BLUEPRINT_PAYOUT_PROVIDER = stripe",
                "BLUEPRINT_PAYOUT_PROVIDER_READY = YES",
                "APS_ENVIRONMENT = production",
            ]
        )

    def real_proof_fixture(self) -> dict:
        proof = validator.load_json(ROOT / "ops" / "launch-readiness" / "example.launch-proof.json")
        proof["contract_only"] = False
        proof["city_slug"] = "austin-tx"
        proof["evidence_generated_at"] = "2026-05-05T20:00:00Z"
        proof["ops"]["launch_owner"] = "founder-on-call"
        proof["evidence"] = {
            "release_config_settings": "build/BlueprintCaptureExternalRelease.settings#2026-05-05",
            "launch_status_response": "firestore:launch_status/austin-tx#run-2026-05-05",
            "demand_feed_response": "cloud-run:demand-feed/austin-tx/run-2026-05-05",
            "capture_submission_document": "firestore:capture_submissions/capture-austin-001",
            "raw_upload_complete": "gs://blueprint-prod-captures/austin/capture-austin-001/capture_upload_complete.json",
            "pipeline_descriptor": "gs://blueprint-prod-pipeline/austin/capture-austin-001/capture_descriptor.json",
            "pipeline_qa_report": "gs://blueprint-prod-pipeline/austin/capture-austin-001/qa_report.json",
            "pipeline_handoff": "pubsub:blueprint-capture-pipeline/austin/capture-austin-001",
            "meta_glasses_smoke": "ops-log:meta-glasses-smoke/austin/run-2026-05-05",
            "stripe_account_state": "stripe-account-state:acct_launch_ready_20260505",
            "payout_provider_state": "stripe-account-state:acct_launch_ready_20260505#provider-readiness",
            "payout_exception_monitor": "ops-monitor:payout-exceptions/austin-tx/run-2026-05-05",
            "identity_kyc_decision": "ops-doc:identity-kyc-provider-decision/2026-05-05#stripe-connect",
            "background_check_decision": "ops-doc:background-check-provider-decision/2026-05-05#human-gated",
            "human_finance_review_gate": "ops-runbook:finance-review/austin-tx#owner-founder",
            "monitoring_runbook": "ops-runbook:first-city-ios-launch/austin-tx/2026-05-05",
        }
        proof["payouts"].update(
            {
                "provider_name": "stripe",
                "provider_state_checked": True,
                "live_provider_ready": True,
                "contract_readiness_not_live_readiness": True,
                "live_payout_execution_human_gate": True,
                "identity_kyc_state_documented": True,
                "background_check_state_documented": True,
            }
        )
        proof["ops"].update(
            {
                "payout_exception_monitor_repo_contract": True,
                "human_finance_review_gate": True,
            }
        )
        return proof


if __name__ == "__main__":
    unittest.main()
