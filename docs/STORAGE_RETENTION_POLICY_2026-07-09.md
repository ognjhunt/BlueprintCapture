# Raw Capture Bucket Storage Retention Policy

Audit finding: **R042 (P1)** — the primary raw capture bucket had no storage
lifecycle / retention rule, so large industrial (warehouse / factory) walkthrough
videos accumulate with no expiry or cheaper tiering, giving unbounded storage cost.

This document defines the committed, deployable Cloud Storage lifecycle policy that
bounds that cost **without deleting capture truth prematurely.**

- Bucket: Firebase Storage project `blueprint-8c1ca`
  (default bucket `gs://blueprint-8c1ca.appspot.com`;
  newer Firebase projects surface it as `gs://blueprint-8c1ca.firebasestorage.app`).
- Canonical raw path: `scenes/{sceneId}/captures/{captureId}/raw/...`
  (see `storage.rules`; per-object cap is 12 GiB for large industrial walkthroughs).
- Policy file: [`storage.lifecycle.json`](../storage.lifecycle.json) (repo root, next
  to `storage.rules`).
- Validator: [`scripts/validate_storage_lifecycle.py`](../scripts/validate_storage_lifecycle.py)
  (+ `scripts/validate_storage_lifecycle_tests.py`).

## Why lifecycle instead of security rules

`storage.rules` already denies client `update`/`delete` on raw objects. Rules cannot
express *age-based tiering or retention* — that is a bucket-level Cloud Storage
lifecycle concern, applied out-of-band from `firebase deploy` (which only ships
security rules). This file is therefore applied with `gsutil` / `gcloud`, not Firebase.

## The policy (tiers, ages, minimum retention)

Lifecycle actions target the `scenes/` object-name **prefix**. GCS lifecycle conditions
only match the *start* of an object name, so the mid-path `.../raw/...` segment cannot be
isolated; `scenes/` is the capture tree where every raw capture bundle accumulates.

| Age (days) | Action | Storage class match | Effect |
|-----------:|--------|---------------------|--------|
| 90  | `SetStorageClass` → **NEARLINE** | `STANDARD` | Warm→cool once past the review/delivery window. |
| 365 | `SetStorageClass` → **COLDLINE** | `STANDARD`, `NEARLINE` | Cheap cold storage for long-lived provenance. |
| 3650 | `Delete` | (any) | Deletion only after a **10-year** documented horizon. |

- **Review / delivery window: 90 days.** No lifecycle action fires before this. Raw
  captures stay in STANDARD (hot) and undeleted while a capture is still being reviewed
  and delivered to a buyer.
- **Cost is bounded by tiering, not deletion.** COLDLINE is roughly an order of magnitude
  cheaper per GB than STANDARD; the accumulating warehouse/factory videos land there at
  1 year and stay retrievable (retrieval incurs a small per-GB fee — acceptable for cold
  provenance that is rarely re-read).
- **Minimum retention floor: 2555 days (7 years).** The committed `Delete` age is 3650
  days (10 years), comfortably above the floor. The validator **fails closed** if any
  future edit sets a `Delete` age below the 7-year floor, or before the object has been
  tiered to COLDLINE, or inside the review/delivery window.

Ages are configurable: edit `storage.lifecycle.json`, keep the guardrails
(review window ≥ 90d, delete ≥ 7y, delete after COLDLINE, COLDLINE after NEARLINE),
re-run the validator, and re-apply.

## Capture-truth guardrail

Raw capture bundles are **authoritative provenance** (see `PLATFORM_CONTEXT.md`,
`docs/CAPTURE_RAW_CONTRACT_V3.md`). This policy therefore:

1. **Never** deletes or tiers inside the review/delivery window (< 90 days).
2. **Never** relies on deletion for routine cost control — cost is bounded by COLDLINE
   tiering, which preserves the object.
3. Deletes **only** after a deliberate, long (10-year) documented retention horizon, and
   **only** after the object has already been cold-tiered.
4. Is enforced by `validate_storage_lifecycle.py`, which rejects any drift toward
   aggressive deletion so a well-meaning cost-cutting edit cannot destroy capture truth.

Admin-SDK / server access bypasses `storage.rules` but **not** bucket lifecycle — the
lifecycle policy applies uniformly to every writer, including Cloud Functions.

## Apply / verify commands

```bash
# Validate before applying (also run in the archive/readiness gate):
python3 scripts/validate_storage_lifecycle.py
PYTHONDONTWRITEBYTECODE=1 python3 scripts/validate_storage_lifecycle_tests.py

# Apply to the bucket (either tool works):
gsutil lifecycle set storage.lifecycle.json gs://blueprint-8c1ca.appspot.com
gcloud storage buckets update gs://blueprint-8c1ca.appspot.com \
    --lifecycle-file=storage.lifecycle.json

# Read the live policy back to confirm:
gsutil lifecycle get gs://blueprint-8c1ca.appspot.com
```

> Changing the retention floor, the review window, or enabling shorter deletion is a
> deliberate policy change: update this doc and the guardrail constants in
> `scripts/validate_storage_lifecycle.py` together, and get sign-off before applying.
