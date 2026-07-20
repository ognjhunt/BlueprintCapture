#!/usr/bin/env python3
"""Fail closed when the capture bucket lifecycle policy drifts toward premature deletion.

Finding R042 (P1): the raw capture bucket (Firebase Storage project ``blueprint-8c1ca``;
canonical path ``scenes/{sceneId}/captures/{captureId}/raw/...``) had no lifecycle /
retention rule, so large industrial (warehouse / factory) walkthrough captures
accumulate with no expiry or cheaper tiering -> unbounded storage cost.

This validator guards the committed GCS lifecycle policy (``storage.lifecycle.json``)
so it stays *deployable* and *cost-bounded* WITHOUT letting a future edit turn it into
aggressive deletion of authoritative capture truth. Capture-truth / provenance rules:

  * Raw capture bundles are AUTHORITATIVE. Deletion must be a deliberate, documented,
    long-horizon decision -- never the default cost lever.
  * Cost is bounded first by cold TIERING (NEARLINE -> COLDLINE), not by deletion.
  * Nothing may fire inside the review / delivery window (objects must stay in STANDARD
    and undeleted while a capture is still being reviewed and delivered to a buyer).
  * Any ``Delete`` action must be gated behind a documented minimum retention floor and
    must only run AFTER the object has been tiered to COLDLINE.

The policy targets the ``scenes/`` object-name prefix. GCS lifecycle conditions can only
prefix-match the START of an object name, so the mid-path ``.../raw/...`` segment cannot
be isolated; ``scenes/`` is the capture tree where every raw capture bundle accumulates.

Apply the committed policy with either:

    gsutil lifecycle set storage.lifecycle.json gs://blueprint-8c1ca.appspot.com
    gcloud storage buckets update gs://blueprint-8c1ca.appspot.com \
        --lifecycle-file=storage.lifecycle.json

Read the current live policy back with:

    gsutil lifecycle get gs://blueprint-8c1ca.appspot.com
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

# ── Documented retention guardrails (days). These are FLOORS/relations enforced by the
#    validator, not the exact committed ages -- ages stay configurable in the JSON as
#    long as they respect these guardrails. See docs/STORAGE_RETENTION_POLICY_*.md. ──

# Review + delivery window during which a raw capture must stay hot and undeleted.
# No lifecycle action (tiering OR deletion) may fire before this age. Mirrors the
# canonical cross-repo policy (BlueprintCapturePipeline
# deploy/storage/primary-capture-bucket-lifecycle.json), which tiers to NEARLINE
# at 30 days.
REVIEW_DELIVERY_WINDOW_DAYS = 30

# Minimum age before ANY Delete action may run. Raw capture bundles are authoritative
# provenance; deletion is only permitted after a long, deliberate retention horizon.
# A future edit that drops a Delete rule below this floor fails the validator.
MIN_DELETE_AGE_DAYS = 2555  # 7 years

_ALLOWED_ACTION_TYPES = {"SetStorageClass", "Delete"}
_ALLOWED_STORAGE_CLASSES = {"NEARLINE", "COLDLINE", "ARCHIVE"}
# Ordered from hot/expensive to cold/cheap so we can assert progressive tiering.
_STORAGE_CLASS_ORDER = {"STANDARD": 0, "NEARLINE": 1, "COLDLINE": 2, "ARCHIVE": 3}

RAW_CAPTURE_PREFIX = "scenes/"


def fail(message: str) -> None:
    print(f"Storage lifecycle validation failed: {message}", file=sys.stderr)
    sys.exit(1)


def _condition_age(condition: dict, rule_label: str) -> int:
    age = condition.get("age")
    if not isinstance(age, int) or isinstance(age, bool):
        fail(f"{rule_label}: condition.age must be an integer number of days")
    if age < 0:
        fail(f"{rule_label}: condition.age must be non-negative")
    return age


def validate_lifecycle(config: object, source: str) -> None:
    if not isinstance(config, dict):
        fail(f"{source}: top-level lifecycle config must be a JSON object")

    rules = config.get("rule")
    if not isinstance(rules, list) or not rules:
        fail(f"{source}: lifecycle config must contain a non-empty 'rule' array")

    tiering_ages: dict[str, int] = {}
    delete_ages: list[int] = []

    for index, rule in enumerate(rules):
        label = f"{source}: rule[{index}]"
        if not isinstance(rule, dict):
            fail(f"{label}: each rule must be an object")

        action = rule.get("action")
        condition = rule.get("condition")
        if not isinstance(action, dict):
            fail(f"{label}: rule.action must be an object")
        if not isinstance(condition, dict):
            fail(f"{label}: rule.condition must be an object")

        action_type = action.get("type")
        if action_type not in _ALLOWED_ACTION_TYPES:
            fail(
                f"{label}: unsupported action.type {action_type!r}; "
                f"expected one of {sorted(_ALLOWED_ACTION_TYPES)}"
            )

        # Every rule must target the raw-capture tree; a rule with no prefix would
        # silently tier/delete unrelated buckets (webapp/account uploads).
        prefixes = condition.get("matchesPrefix")
        if not isinstance(prefixes, list) or RAW_CAPTURE_PREFIX not in prefixes:
            fail(
                f"{label}: condition.matchesPrefix must include {RAW_CAPTURE_PREFIX!r} "
                "so the policy only affects the raw capture tree"
            )

        age = _condition_age(condition, label)

        # Capture-truth guardrail: nothing may act inside the review/delivery window.
        if age < REVIEW_DELIVERY_WINDOW_DAYS:
            fail(
                f"{label}: condition.age {age} is inside the review/delivery window "
                f"(< {REVIEW_DELIVERY_WINDOW_DAYS} days); raw captures must stay hot "
                "and undeleted while under review and delivery"
            )

        if action_type == "SetStorageClass":
            storage_class = action.get("storageClass")
            if storage_class not in _ALLOWED_STORAGE_CLASSES:
                fail(
                    f"{label}: SetStorageClass.storageClass {storage_class!r} must be one of "
                    f"{sorted(_ALLOWED_STORAGE_CLASSES)}"
                )
            tiering_ages[storage_class] = min(
                age, tiering_ages.get(storage_class, age)
            )
        else:  # Delete
            # Capture-truth guardrail: deletion only after the documented retention floor.
            if age < MIN_DELETE_AGE_DAYS:
                fail(
                    f"{label}: Delete.condition.age {age} is below the minimum retention "
                    f"floor of {MIN_DELETE_AGE_DAYS} days ({MIN_DELETE_AGE_DAYS // 365} years). "
                    "Raw capture bundles are authoritative provenance; do not shorten this "
                    "without a documented policy change"
                )
            delete_ages.append(age)

    # Must cold-tier for cost control (COLDLINE), not rely on deletion.
    if "COLDLINE" not in tiering_ages:
        fail(
            f"{source}: policy must include a SetStorageClass -> COLDLINE tiering rule so "
            "cost is bounded by cheap cold tiering rather than aggressive deletion"
        )

    # Progressive tiering: COLDLINE must not fire before NEARLINE.
    if "NEARLINE" in tiering_ages and tiering_ages["COLDLINE"] < tiering_ages["NEARLINE"]:
        fail(
            f"{source}: COLDLINE transition (age {tiering_ages['COLDLINE']}) must not fire "
            f"before NEARLINE transition (age {tiering_ages['NEARLINE']})"
        )

    # Deletion must only happen AFTER the object has been tiered to COLDLINE.
    coldline_age = tiering_ages["COLDLINE"]
    for delete_age in delete_ages:
        if delete_age <= coldline_age:
            fail(
                f"{source}: Delete age {delete_age} must be strictly greater than the "
                f"COLDLINE tiering age {coldline_age}; captures must be cold-tiered before "
                "any deletion is considered"
            )

    tier_summary = ", ".join(
        f"{cls}@{tiering_ages[cls]}d"
        for cls in ("NEARLINE", "COLDLINE", "ARCHIVE")
        if cls in tiering_ages
    )
    delete_summary = (
        ", ".join(f"delete@{a}d" for a in sorted(delete_ages)) if delete_ages else "no-delete"
    )
    print(
        "Storage lifecycle validation passed: raw captures tiered "
        f"({tier_summary}) then {delete_summary}; review/delivery window "
        f">= {REVIEW_DELIVERY_WINDOW_DAYS}d protected; delete floor "
        f">= {MIN_DELETE_AGE_DAYS}d enforced."
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate the committed GCS lifecycle policy for the raw capture bucket."
    )
    parser.add_argument(
        "--lifecycle",
        type=Path,
        default=None,
        help="Path to a GCS lifecycle JSON file (defaults to repo-root storage.lifecycle.json).",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    repo_root = Path(__file__).resolve().parents[1]
    lifecycle_path = args.lifecycle or (repo_root / "storage.lifecycle.json")

    if not lifecycle_path.exists():
        fail(f"{lifecycle_path} is missing")

    try:
        config = json.loads(lifecycle_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        fail(f"{lifecycle_path} is not valid JSON: {exc}")

    validate_lifecycle(config, lifecycle_path.name)


if __name__ == "__main__":
    main()
