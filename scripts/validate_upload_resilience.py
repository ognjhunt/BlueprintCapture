#!/usr/bin/env python3
"""Validate beta-critical iOS upload resilience invariants with no live Firebase dependency."""

from __future__ import annotations

import re
import sys
from pathlib import Path


def fail(message: str) -> None:
    print(f"Upload resilience validation failed: {message}", file=sys.stderr)
    sys.exit(1)


def require_contains(text: str, needle: str, description: str) -> None:
    if needle not in text:
        fail(f"missing {description}: {needle}")


def require_order(text: str, first: str, second: str, description: str) -> None:
    first_index = text.find(first)
    second_index = text.find(second)
    if first_index == -1:
        fail(f"missing first marker for {description}: {first}")
    if second_index == -1:
        fail(f"missing second marker for {description}: {second}")
    if first_index > second_index:
        fail(f"wrong order for {description}: {first} must appear before {second}")


def main() -> None:
    repo_root = Path(__file__).resolve().parents[1]
    upload_service_path = repo_root / "BlueprintCapture" / "Services" / "CaptureUploadService.swift"
    app_delegate_path = repo_root / "BlueprintCapture" / "AppDelegate.swift"

    if not upload_service_path.exists():
        fail(f"{upload_service_path.relative_to(repo_root)} is missing")
    if not app_delegate_path.exists():
        fail(f"{app_delegate_path.relative_to(repo_root)} is missing")

    upload_service = upload_service_path.read_text(encoding="utf-8")
    app_delegate = app_delegate_path.read_text(encoding="utf-8")
    upload_directory_match = re.search(
        r"private func uploadDirectory\(.*?\n    private func slugifyCity",
        upload_service,
        re.DOTALL,
    )
    if not upload_directory_match:
        fail("could not isolate uploadDirectory implementation")
    upload_directory = upload_directory_match.group(0)

    forbidden_upload_calls = [".putFile(", ".putData("]
    for call in forbidden_upload_calls:
        if call in upload_service:
            fail(f"foreground Firebase Storage upload call remains in CaptureUploadService.swift: {call}")

    required_upload_snippets = [
        ("BackgroundFirebaseStorageUploader.shared.uploadFile", "background uploader usage"),
        ("URLSessionConfiguration.background", "background URLSession configuration"),
        ("configuration.sessionSendsLaunchEvents = true", "background relaunch support"),
        ("configuration.waitsForConnectivity = true", "connectivity wait for background uploads"),
        ("UIApplication.shared.beginBackgroundTask", "foreground grace-period background task"),
        ("hasUsableDiskSpace(for: localDirectory)", "disk-space preflight"),
        ("rawContractValidator.validate(rawDirectoryURL: uploadRoot)", "raw contract validation after finalization"),
        ('custom["sha256"]', "per-file sha256 custom metadata"),
        ('metadata.customMetadata?["sha256"] != expectedSha256', "resume checksum verification"),
        ("metadata.size != Int64(localSize)", "resume file-size verification"),
        ("capture_lifecycle_write_failed", "pre-upload lifecycle failure recording"),
        ("submissionRegistrationFailed", "post-upload submission failure state"),
    ]
    for needle, description in required_upload_snippets:
        require_contains(upload_service, needle, description)

    require_order(
        upload_directory,
        "guard hasUsableDiskSpace(for: localDirectory)",
        "finalizer.finalize(",
        "disk-space preflight before finalization/upload",
    )
    require_order(
        upload_directory,
        "finalizer.finalize(",
        "rawContractValidator.validate(rawDirectoryURL: uploadRoot)",
        "raw contract validation after finalization",
    )
    require_order(
        upload_directory,
        "rawContractValidator.validate(rawDirectoryURL: uploadRoot)",
        "CaptureUploadFilePlan.make(for: uploadRoot)",
        "raw contract validation before upload enumeration",
    )
    require_order(
        upload_directory,
        "CaptureUploadFilePlan.make(for: uploadRoot)",
        "BackgroundFirebaseStorageUploader.shared.uploadFile",
        "upload planning before background transfer",
    )

    if len(re.findall(r"BackgroundFirebaseStorageUploader\.shared\.uploadFile", upload_service)) < 2:
        fail("directory payload and completion-marker uploads must both use the background uploader")

    required_app_delegate_snippets = [
        ("handleEventsForBackgroundURLSession", "iOS background URLSession relaunch hook"),
        (
            "BackgroundFirebaseStorageUploader.shared.setBackgroundCompletionHandler(completionHandler)",
            "background completion handler handoff",
        ),
    ]
    for needle, description in required_app_delegate_snippets:
        require_contains(app_delegate, needle, description)

    print("Upload resilience validation passed: background transfers, checksum resume verification, disk preflight, and validation ordering are present.")


if __name__ == "__main__":
    main()
