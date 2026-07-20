#!/usr/bin/env python3
"""Fail closed if static storage credentials appear anywhere in shipped app source.

Finding SCALE2-05 (P0, security): the legacy Backblaze B2 ``StorageManager.swift`` path
embedded a live B2 ``keyID`` / ``applicationKey`` pair as string literals, which shipped
inside every compiled app binary. That file was dead code (zero call sites) and has been
deleted; the exposed key must additionally be ROTATED/REVOKED in the Backblaze dashboard
(a human/ops action -- no code change can un-leak a key).

This validator keeps the class of bug from coming back: any B2 master/application-key
authorization flow, static storage credential literal, or unsigned public B2 download URL
reintroduced into app source fails CI. Storage access from the app must be brokered by a
backend (short-lived, scoped credentials or signed URLs minted server-side), never by a
static key compiled into the binary.

Scanned trees: the iOS app target (``BlueprintCapture/``) and the Android app source
(``android/``). Cloud-function code (``cloud/``) is server-side and is allowed to hold
service credentials via its own secret management; it is still scanned for the
*hardcoded-literal* patterns (secrets belong in env/secret manager, not source).
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]

# Source trees that ship to (or define) client binaries.
CLIENT_SOURCE_TREES = ("BlueprintCapture", "android")
# Server-side source: scanned only for hardcoded-secret literals.
SERVER_SOURCE_TREES = ("cloud",)

SOURCE_SUFFIXES = {".swift", ".kt", ".kts", ".java", ".m", ".mm", ".ts", ".js"}

# Patterns that indicate the app is talking to B2 with embedded static credentials
# or fetching through the unsigned public download host. Client trees only.
CLIENT_FORBIDDEN_PATTERNS = (
    # B2 native-API authorization from the client (requires an embedded static key).
    re.compile(r"b2_authorize_account"),
    re.compile(r"api\.backblazeb2\.com"),
    # Unsigned public file downloads (no access control at all).
    re.compile(r"f\d{3}\.backblazeb2\.com/file/"),
)

# Hardcoded-credential literals. Forbidden everywhere, including server-side source:
# a B2 keyID is 25 hex-ish chars starting with the account id; an applicationKey
# is a 31-char token starting with "K0". Also catch obvious assignment literals.
SECRET_LITERAL_PATTERNS = (
    re.compile(r"[\"']005[0-9a-f]{10,}[\"']"),
    re.compile(r"[\"']K0[0-9A-Za-z]{25,}[\"']"),
    re.compile(
        r"(applicationKey|application_key|B2_APPLICATION_KEY)\s*[:=]\s*[\"'][^\"']{16,}[\"']"
    ),
)


def iter_source_files(root: Path, trees: tuple[str, ...]):
    for tree in trees:
        base = root / tree
        if not base.is_dir():
            continue
        for path in sorted(base.rglob("*")):
            if path.suffix.lower() not in SOURCE_SUFFIXES:
                continue
            if any(part in {"node_modules", "build", "Pods", ".git"} for part in path.parts):
                continue
            yield path


def scan(root: Path) -> list[str]:
    violations: list[str] = []
    for path in iter_source_files(root, CLIENT_SOURCE_TREES):
        text = path.read_text(encoding="utf-8", errors="replace")
        for lineno, line in enumerate(text.splitlines(), start=1):
            for pattern in (*CLIENT_FORBIDDEN_PATTERNS, *SECRET_LITERAL_PATTERNS):
                if pattern.search(line):
                    violations.append(
                        f"{path.relative_to(root)}:{lineno}: forbidden storage-credential "
                        f"pattern {pattern.pattern!r}"
                    )
    for path in iter_source_files(root, SERVER_SOURCE_TREES):
        text = path.read_text(encoding="utf-8", errors="replace")
        for lineno, line in enumerate(text.splitlines(), start=1):
            for pattern in SECRET_LITERAL_PATTERNS:
                if pattern.search(line):
                    violations.append(
                        f"{path.relative_to(root)}:{lineno}: hardcoded storage secret "
                        f"literal matches {pattern.pattern!r}"
                    )
    return violations


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root",
        type=Path,
        default=REPO_ROOT,
        help="Repo root to scan (tests point this at fixtures).",
    )
    args = parser.parse_args(argv)

    violations = scan(args.root.resolve())
    if violations:
        print("Embedded storage credential validator FAILED:", file=sys.stderr)
        for violation in violations:
            print(f"- {violation}", file=sys.stderr)
        print(
            "\nStorage access from the app must be brokered by the backend "
            "(short-lived scoped credentials / signed URLs), never a static key "
            "compiled into the binary. See docs/backend-scaling round-2 notes.",
            file=sys.stderr,
        )
        return 1
    print("Embedded storage credential validator passed: no static credentials in app source.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
