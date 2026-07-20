#!/usr/bin/env python3
"""Unit tests for the embedded-storage-credential validator (finding SCALE2-05)."""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "scripts"))

import validate_no_embedded_storage_credentials as validator  # noqa: E402


def _write(root: Path, relative: str, content: str) -> None:
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


class EmbeddedCredentialValidatorTests(unittest.TestCase):
    def test_clean_tree_passes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _write(
                root,
                "BlueprintCapture/Services/UploadService.swift",
                "// requests short-lived upload auth from the backend\n"
                'let url = "/api/storage/uploads"\n',
            )
            self.assertEqual(validator.scan(root), [])

    def test_b2_authorize_account_in_app_source_fails(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _write(
                root,
                "BlueprintCapture/Firebase/StorageManager.swift",
                'let url = "https://api.backblazeb2.com/b2api/v1/b2_authorize_account"\n',
            )
            violations = validator.scan(root)
            self.assertTrue(violations)
            self.assertIn("StorageManager.swift", violations[0])

    def test_hardcoded_key_literals_fail(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _write(
                root,
                "BlueprintCapture/Anything.swift",
                'let keyID = "00550218f7653950000000001"\n'
                'let applicationKey = "K00521En3D6GNXS9VFKTLXFVctlPP3Y"\n',
            )
            violations = validator.scan(root)
            self.assertGreaterEqual(len(violations), 2)

    def test_unsigned_public_download_url_fails(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _write(
                root,
                "android/app/src/main/java/ProfilePic.kt",
                'val url = "https://f005.backblazeb2.com/file/bucket/user.jpg"\n',
            )
            violations = validator.scan(root)
            self.assertTrue(violations)

    def test_server_tree_allows_env_lookup_but_not_literals(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _write(
                root,
                "cloud/extract-frames/src/whatever.ts",
                "const key = process.env.B2_APPLICATION_KEY;\n",
            )
            self.assertEqual(validator.scan(root), [])
            _write(
                root,
                "cloud/extract-frames/src/leak.ts",
                'const B2_APPLICATION_KEY = "K00521En3D6GNXS9VFKTLXFVctlPP3Y";\n',
            )
            self.assertTrue(validator.scan(root))

    def test_committed_repo_is_clean(self) -> None:
        self.assertEqual(
            validator.scan(REPO_ROOT),
            [],
            "shipped app source must not contain static storage credentials",
        )


if __name__ == "__main__":
    unittest.main()
