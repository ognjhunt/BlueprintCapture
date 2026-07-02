#!/usr/bin/env python3
"""Fail closed when Firebase Storage rules drift away from raw capture ownership."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


def fail(message: str) -> None:
    print(f"Storage rules validation failed: {message}", file=sys.stderr)
    sys.exit(1)


def compact_rules(text: str) -> str:
    return re.sub(r"\s+", " ", text)


def require_contains(text: str, needle: str, description: str) -> None:
    if needle not in text:
        fail(f"missing {description}: {needle}")


def main() -> None:
    repo_root = Path(__file__).resolve().parents[1]
    firebase_json = repo_root / "firebase.json"
    storage_rules = repo_root / "storage.rules"

    if not firebase_json.exists():
        fail("firebase.json is missing")
    if not storage_rules.exists():
        fail("storage.rules is missing")

    try:
        firebase_config = json.loads(firebase_json.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        fail(f"firebase.json is not valid JSON: {exc}")

    storage_config = firebase_config.get("storage")
    if not isinstance(storage_config, dict):
        fail("firebase.json must define a storage section")
    if storage_config.get("rules") != "storage.rules":
        fail("firebase.json storage.rules must point to storage.rules")

    rules = compact_rules(storage_rules.read_text(encoding="utf-8"))

    required_snippets = [
        ("rules_version = '2';", "rules version"),
        ("service firebase.storage", "Firebase Storage service block"),
        ("request.auth != null", "authenticated-user requirement"),
        (
            "match /scenes/{sceneId}/captures/{captureId}/raw/{rawPath=**}",
            "canonical raw capture path rule",
        ),
        (
            "request.resource.metadata.creatorId == request.auth.uid",
            "creator ownership metadata check",
        ),
        ("request.resource.metadata.sceneId == sceneId", "scene metadata path binding"),
        ("request.resource.metadata.captureId == captureId", "capture metadata path binding"),
        ("request.resource.metadata.sha256 != null", "per-object checksum requirement"),
        (
            "request.resource.metadata.sha256.matches('^[a-f0-9]{64}$')",
            "lowercase sha256 format check",
        ),
        ("allow create: if isSignedIn()", "create-only authenticated raw upload rule"),
        ("allow update, delete: if false;", "raw update/delete deny rule"),
        ("match /{allPaths=**} { allow read, write: if false;", "catch-all deny rule"),
    ]
    for needle, description in required_snippets:
        require_contains(rules, needle, description)

    unsafe_patterns = [
        r"allow\s+write\s*:\s*if\s+request\.auth\s*!=\s*null",
        r"allow\s+write\s*:\s*if\s+true",
        r"allow\s+create\s*:\s*if\s+true",
        r"allow\s+read,\s*write\s*:\s*if\s+request\.auth\s*!=\s*null",
    ]
    for pattern in unsafe_patterns:
        if re.search(pattern, rules):
            fail(f"unsafe broad rule matched {pattern}")

    print("Storage rules validation passed: raw capture writes require auth, owner metadata, path binding, checksum, and catch-all deny.")


if __name__ == "__main__":
    main()
