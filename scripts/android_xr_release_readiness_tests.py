#!/usr/bin/env python3
import os
import subprocess
import sys
import tempfile
import textwrap
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
ANDROID_NS = "{http://schemas.android.com/apk/res/android}"
SPATIAL_FEATURE = "android.software.xr.api.spatial"
OPENXR_FEATURE = "android.software.xr.api.openxr"


def manifest_features(manifest_path: Path) -> dict[str, str]:
    root = ET.parse(manifest_path).getroot()
    features: dict[str, str] = {}
    for element in root.findall("uses-feature"):
        name = element.attrib.get(f"{ANDROID_NS}name", "")
        required = element.attrib.get(f"{ANDROID_NS}required", "")
        if name:
            features[name] = required
    return features


class AndroidXrReleaseReadinessRepoTests(unittest.TestCase):
    def test_android_xr_manifest_declares_mobile_track_spatial_feature(self) -> None:
        build_gradle = REPO_ROOT / "android" / "app" / "build.gradle.kts"
        manifest = REPO_ROOT / "android" / "app" / "src" / "main" / "AndroidManifest.xml"

        self.assertIn("androidx.xr.", build_gradle.read_text())

        features = manifest_features(manifest)
        self.assertIn(SPATIAL_FEATURE, features)
        self.assertEqual(
            "false",
            features[SPATIAL_FEATURE],
            "Blueprint bundles XR features in the existing mobile Android app, so the "
            "mobile-track manifest feature must not filter out non-XR installs.",
        )
        self.assertNotIn(OPENXR_FEATURE, features)

    def test_android_alpha_script_runs_xr_config_and_proof_gates(self) -> None:
        script = (REPO_ROOT / "scripts" / "android_alpha_readiness.sh").read_text()

        self.assertIn("validate_android_xr_release_readiness.py", script)
        self.assertIn("--mode config", script)
        self.assertIn("--mode proof", script)


class AndroidXrReleaseReadinessValidatorCliTests(unittest.TestCase):
    def setUp(self) -> None:
        self.validator = REPO_ROOT / "scripts" / "validate_android_xr_release_readiness.py"
        self.assertTrue(self.validator.exists(), f"Missing validator at {self.validator}")

    def run_validator(
        self,
        repo_root: Path,
        mode: str,
        extra_env: dict[str, str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        env = os.environ.copy()
        env.update(extra_env or {})
        return subprocess.run(
            [
                sys.executable,
                str(self.validator),
                "--repo-root",
                str(repo_root),
                "--mode",
                mode,
            ],
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )

    def write_fixture(
        self,
        root: Path,
        uses_feature: str | None = SPATIAL_FEATURE,
        required: str | None = "false",
        target_sdk: int = 36,
        compile_sdk: int = 36,
        min_sdk: int = 29,
    ) -> None:
        manifest_dir = root / "android" / "app" / "src" / "main"
        manifest_dir.mkdir(parents=True)
        feature_line = ""
        if uses_feature is not None:
            feature_line = (
                f'<uses-feature android:name="{uses_feature}" '
                f'android:required="{required}" />'
            )
        (manifest_dir / "AndroidManifest.xml").write_text(
            textwrap.dedent(
                f"""\
                <?xml version="1.0" encoding="utf-8"?>
                <manifest xmlns:android="http://schemas.android.com/apk/res/android">
                    {feature_line}
                    <application />
                </manifest>
                """
            )
        )
        app_dir = root / "android" / "app"
        app_dir.mkdir(parents=True, exist_ok=True)
        (app_dir / "build.gradle.kts").write_text(
            textwrap.dedent(
                f"""\
                android {{
                    compileSdk = {compile_sdk}
                    defaultConfig {{
                        minSdk = {min_sdk}
                        targetSdk = {target_sdk}
                    }}
                }}

                dependencies {{
                    implementation(libs.androidx.xr.runtime)
                    implementation(libs.androidx.xr.projected)
                    implementation(libs.androidx.xr.glimmer)
                    implementation(libs.androidx.xr.arcore)
                }}
                """
            )
        )

    def test_config_mode_rejects_missing_xr_feature_when_xr_dependencies_exist(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.write_fixture(root, uses_feature=None)

            result = self.run_validator(root, "config")

        self.assertNotEqual(0, result.returncode)
        self.assertIn("Stage: android_xr_manifest_blocked", result.stderr)
        self.assertIn(SPATIAL_FEATURE, result.stderr)

    def test_config_mode_rejects_mobile_track_required_true(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.write_fixture(root, required="true")

            result = self.run_validator(root, "config")

        self.assertNotEqual(0, result.returncode)
        self.assertIn("Stage: android_xr_manifest_blocked", result.stderr)
        self.assertIn("android:required=\"false\"", result.stderr)

    def test_proof_mode_requires_external_proof_path(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.write_fixture(root)

            result = self.run_validator(root, "proof")

        self.assertNotEqual(0, result.returncode)
        self.assertIn("Stage: android_xr_release_proof_blocked", result.stderr)
        self.assertIn("BLUEPRINT_ANDROID_XR_RELEASE_PROOF_PATH", result.stderr)


if __name__ == "__main__":
    unittest.main()
