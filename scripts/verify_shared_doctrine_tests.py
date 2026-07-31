#!/usr/bin/env python3
"""Contract tests for the cross-repo shared doctrine verifier.

These pin the extraction rule that the digest in
`contracts/shared-doctrine.lock.json` is computed over.  The rule must stay
byte-identical to `BlueprintCapturePipeline scripts/verify_shared_doctrine.py`
and to the TypeScript twin in `Blueprint-WebApp`, otherwise the same document
would hash differently in different repos and the gate would stop meaning
anything.

Run directly; no pytest, no sibling checkout, and no network required:

    python3 scripts/verify_shared_doctrine_tests.py
"""

from __future__ import annotations

import importlib.util
import json
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

sys.dont_write_bytecode = True


ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "scripts" / "verify_shared_doctrine.py"

spec = importlib.util.spec_from_file_location("verify_shared_doctrine", MODULE_PATH)
if spec is None or spec.loader is None:
    raise RuntimeError(f"Unable to load verifier module from {MODULE_PATH}")
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)

DoctrineVerificationError = verifier.DoctrineVerificationError
digest_block = verifier.digest_block
extract_block = verifier.extract_block
load_lock = verifier.load_lock
verify = verifier.verify


class CommittedStateTests(unittest.TestCase):
    """The blocks committed in this repo must match the committed lock."""

    def test_every_tracked_block_matches_the_lock(self) -> None:
        results = verify(ROOT)
        self.assertTrue(results, "lock declares no blocks")
        for row in results:
            self.assertTrue(row["matched"], f"{row['block']} does not match the lock")

    def test_lock_is_wellformed_and_covers_this_repo(self) -> None:
        lock = load_lock(ROOT)
        self.assertEqual(lock["schema_version"], verifier.LOCK_SCHEMA_VERSION)
        for block_name, entry in lock["blocks"].items():
            self.assertTrue(
                (ROOT / entry["file"]).is_file(), f"{block_name}: missing source"
            )
            if lock["status"] == verifier.STATUS_LOCKED:
                self.assertTrue(
                    entry.get("canonical_sha256"),
                    f"{block_name}: locked without a canonical digest",
                )
            else:
                self.assertTrue(
                    (entry.get("observed_sha256") or {}).get(verifier.REPO_NAME),
                    f"{block_name}: no baseline recorded for {verifier.REPO_NAME}",
                )

    def test_lock_lists_this_repo_in_the_repo_set(self) -> None:
        self.assertIn(verifier.REPO_NAME, load_lock(ROOT)["repos"])

    def test_repo_name_matches_this_checkout(self) -> None:
        """Guard the one line that legitimately differs from the Pipeline copy.

        A copy-paste that left `REPO_NAME` as the Pipeline's would silently
        verify the wrong repo's baseline under an `unreconciled` lock.
        """

        self.assertEqual(verifier.REPO_NAME, "BlueprintCapture")


class ExtractionRuleTests(unittest.TestCase):
    """The extraction rule itself, pinned character by character."""

    def test_extraction_is_exclusive_of_marker_lines(self) -> None:
        text = "before\n<!-- X_START -->\nbody line\n<!-- X_END -->\nafter\n"
        self.assertEqual(extract_block(text, "X"), "body line\n")

    def test_extraction_preserves_interior_blank_lines(self) -> None:
        text = "<!-- X_START -->\na\n\nb\n<!-- X_END -->\n"
        self.assertEqual(extract_block(text, "X"), "a\n\nb\n")

    def test_malformed_markers_fail_closed(self) -> None:
        malformed = [
            "no markers at all\n",
            "<!-- X_START -->\nbody\n",
            "<!-- X_END -->\nbody\n",
            "<!-- X_END -->\nbody\n<!-- X_START -->\n",
            "<!-- X_START -->\na\n<!-- X_START -->\nb\n<!-- X_END -->\n",
        ]
        for text in malformed:
            with self.subTest(text=text):
                with self.assertRaises(DoctrineVerificationError):
                    extract_block(text, "X")

    def test_crlf_and_cr_hash_identically_to_lf(self) -> None:
        """A CRLF checkout must produce the committed LF baseline digest.

        No .gitattributes rule pins these Markdown files to LF, so without
        folding line endings a Windows checkout would fail the gate on
        unmodified content.
        """

        lf = "<!-- X_START -->\na\n\nb\n<!-- X_END -->\n"
        digests = {
            digest_block(extract_block(text, "X"))
            for text in (lf, lf.replace("\n", "\r\n"), lf.replace("\n", "\r"))
        }
        self.assertEqual(len(digests), 1)

    def test_unicode_line_boundaries_are_not_treated_as_line_breaks(self) -> None:
        """Parity guard against `str.splitlines()`.

        `splitlines()` breaks on vertical tab, form feed, NEL, and the Unicode
        line/paragraph separators; JavaScript's `split("\\n")` does not.  Using
        it here would make this verifier disagree with the TypeScript twin on
        any document containing one, which would defeat the gate rather than
        enforce it.
        """

        for separator in ("\x0b", "\x0c", " ", " ", "\x85"):
            with self.subTest(separator=repr(separator)):
                body = extract_block(
                    f"<!-- X_START -->\na{separator}b\n<!-- X_END -->\n", "X"
                )
                self.assertEqual(body, f"a{separator}b\n")

    def test_splitlines_would_disagree(self) -> None:
        """Prove the guard above is load-bearing, not decorative."""

        text = "<!-- X_START -->\na\x0bb\n<!-- X_END -->\n"
        naive = text.splitlines()
        exact = verifier.normalize_newlines(text).split("\n")
        self.assertNotEqual(naive, exact)

    def test_digest_is_stable_for_identical_bodies(self) -> None:
        a = extract_block("<!-- X_START -->\nsame\n<!-- X_END -->\n", "X")
        b = extract_block("head\n<!-- X_START -->\nsame\n<!-- X_END -->\ntail\n", "X")
        self.assertEqual(digest_block(a), digest_block(b))


class FailClosedTests(unittest.TestCase):
    """Every way the lock can be wrong must exit non-zero, never skip."""

    def _stage(self, root: Path, lock: dict) -> None:
        """Write a throwaway repo root carrying real blocks and a mutated lock."""

        (root / "contracts").mkdir(parents=True, exist_ok=True)
        (root / verifier.LOCK_RELATIVE_PATH).write_text(
            json.dumps(lock, indent=2), encoding="utf-8"
        )
        for entry in lock["blocks"].values():
            source = ROOT / entry["file"]
            (root / entry["file"]).write_text(
                source.read_text(encoding="utf-8"), encoding="utf-8"
            )

    def _lock(self) -> dict:
        return json.loads(
            (ROOT / verifier.LOCK_RELATIVE_PATH).read_text(encoding="utf-8")
        )

    def test_drifted_block_fails_closed(self) -> None:
        lock = self._lock()
        for entry in lock["blocks"].values():
            entry["canonical_sha256"] = "0" * 64
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            self._stage(root, lock)
            with self.assertRaises(DoctrineVerificationError) as caught:
                verify(root)
            self.assertIn("does not match the lock", str(caught.exception))

    def test_locked_status_without_canonical_digest_fails_closed(self) -> None:
        lock = self._lock()
        lock["status"] = verifier.STATUS_LOCKED
        for entry in lock["blocks"].values():
            entry.pop("canonical_sha256", None)
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            self._stage(root, lock)
            with self.assertRaises(DoctrineVerificationError) as caught:
                verify(root)
            self.assertIn("canonical_sha256 is absent", str(caught.exception))

    def test_missing_repo_baseline_fails_closed(self) -> None:
        lock = self._lock()
        lock["status"] = verifier.STATUS_UNRECONCILED
        for entry in lock["blocks"].values():
            entry.pop("canonical_sha256", None)
            entry["observed_sha256"] = {}
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            self._stage(root, lock)
            with self.assertRaises(DoctrineVerificationError) as caught:
                verify(root)
            self.assertIn("no baseline recorded", str(caught.exception))

    def test_unreconciled_status_matches_this_repos_own_baseline(self) -> None:
        """Under `unreconciled` each repo is pinned to its own recorded digest."""

        lock = self._lock()
        for entry in lock["blocks"].values():
            canonical = entry.pop("canonical_sha256")
            entry["observed_sha256"] = {verifier.REPO_NAME: canonical}
        lock["status"] = verifier.STATUS_UNRECONCILED
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            self._stage(root, lock)
            self.assertTrue(all(row["matched"] for row in verify(root)))

    def test_unknown_lock_schema_version_fails_closed(self) -> None:
        lock = self._lock()
        lock["schema_version"] = "blueprint.shared_doctrine_lock.v999"
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            self._stage(root, lock)
            with self.assertRaises(DoctrineVerificationError) as caught:
                verify(root)
            self.assertIn("unsupported lock schema_version", str(caught.exception))

    def test_unknown_lock_status_fails_closed(self) -> None:
        lock = self._lock()
        lock["status"] = "probably_fine"
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            self._stage(root, lock)
            with self.assertRaises(DoctrineVerificationError) as caught:
                verify(root)
            self.assertIn("unsupported lock status", str(caught.exception))

    def test_missing_lock_fails_closed(self) -> None:
        with TemporaryDirectory() as tmp:
            with self.assertRaises(DoctrineVerificationError) as caught:
                verify(Path(tmp))
            self.assertIn("missing lock file", str(caught.exception))

    def test_missing_source_file_fails_closed(self) -> None:
        lock = self._lock()
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "contracts").mkdir(parents=True, exist_ok=True)
            (root / verifier.LOCK_RELATIVE_PATH).write_text(
                json.dumps(lock, indent=2), encoding="utf-8"
            )
            with self.assertRaises(DoctrineVerificationError) as caught:
                verify(root)
            self.assertIn("missing source file", str(caught.exception))

    def test_lock_declaring_no_blocks_fails_closed(self) -> None:
        lock = self._lock()
        lock["blocks"] = {}
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "contracts").mkdir(parents=True, exist_ok=True)
            (root / verifier.LOCK_RELATIVE_PATH).write_text(
                json.dumps(lock, indent=2), encoding="utf-8"
            )
            with self.assertRaises(DoctrineVerificationError) as caught:
                verify(root)
            self.assertIn("no blocks", str(caught.exception))


if __name__ == "__main__":
    unittest.main()
