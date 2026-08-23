# Living-room capture test — one page

Date prepared: 2026-08-17. Prepared against BlueprintCapture `fccd8383`
(origin/main) and pipeline `4906d4c5` (origin/main).

## What this test proves, and what it does not

**Proves:** a real iPhone Pro capture produces a valid Raw V3.2 bundle, uploads
it immutably and exactly once, and automatically reaches the Pipeline.

**Does not prove:** reconstruction. No 3DGS is produced by this test. Training
is a separate, paid step that runs afterwards against the capture this test
produces. Nothing in this procedure spends money.

## Before you start

Two prerequisites, both requiring a human.

1. **Metal toolchain** (blocks the build). Over SSH or Screen Sharing to the
   Mac:

   ```
   sudo xcodebuild -downloadComponent MetalToolchain
   ```

   The mount broke while the disk was at zero bytes. A reboot also fixes it.
   Verify with `xcrun metal --version`; it must print a version, not an error.

2. **Signing.** The Release build previously failed with
   `No profiles for 'Public.BlueprintCapture' were found`. The archive helper
   now supports automatic provisioning when explicitly enabled with
   `BLUEPRINT_ALLOW_PROVISIONING_UPDATES=1`; it is never enabled implicitly in
   CI. This is unrelated to the Metal problem; both must be resolved.

Disk: keep at least 10 GB free. The earlier failure cascade started with a full
volume, and Xcode's failure mode was a corrupted toolchain mount rather than a
clear error.

## Build

```
BLUEPRINT_ALLOW_PROVISIONING_UPDATES=1 \
BLUEPRINT_BUILD_NUMBER=<unused-integer-build-number> \
./scripts/archive_external_alpha.sh
```

Config bound by `Config/BlueprintCapture.release.xcconfig` (untracked, local
only) and `BlueprintCapture/GoogleService-Info.plist`:

| Setting | Value |
| --- | --- |
| Firebase project | `blueprint-8c1ca` |
| Storage bucket | `blueprint-8c1ca.appspot.com` |
| Backend base URL | `https://tryblueprint.io` |
| Bundle id | `Public.BlueprintCapture` |
| APS environment | `production` |

The Firebase project matches the Pub/Sub topic and listener subscription, so
the handoff chain is consistent end to end.

## Capture

One continuous guided walk, per the single-walk contract:

1. Hold at the start point until the app reports the entry anchor is set.
2. Walk the space once. Pause at doorways, thresholds, and anything with
   structure worth reobserving.
3. Reobserve shared structure on the way back, in the same recording.
4. Finish where you started and hold until the app reports the route closed.
5. Tap Finish/Upload.

No ruler, marker, or second pass is needed.

## Expected UI states

| Stage | What you should see |
| --- | --- |
| During capture | Live tracking quality; route-closure guidance near the end |
| On Finish | Bundle finalization, then raw-contract validation |
| Validation fail | Upload does not start; a named reason. This is correct — the completion marker is deliberately deleted so a bad bundle cannot be ingested |
| Uploading | Resumable chunked progress; survives backgrounding and network drops |
| Complete | Only after **both** storage upload and the Firestore submission write succeed. Storage alone is not success |

## What happens automatically after you tap Upload

1. App writes `capture_submissions/{captureId}` with `upload_state=uploading`.
2. Resumable upload to `scenes/{sceneId}/captures/{captureId}/raw/`, each file
   read back and hash-verified.
3. App writes `capture_upload_complete.json`, then flips the Firestore row to
   `upload_state=uploaded`, `status=submitted`.
4. Storage finalize fires the `extractFrames` Cloud Function (deployed, ACTIVE
   in `blueprint-8c1ca`, updated 2026-08-15).
5. It extracts frames, builds the pose/sync bridge, runs the quality gate, and
   publishes one message to `blueprint-capture-pipeline-handoff` under a claim
   lock.
6. The `blueprint-pipeline-handoff-listener` pull subscription stages the
   capture on the Pipeline host and attempts to queue reconstruction.

**Step 6 will abstain**, with `site_task_reconstruction_policy_absent`. That is
expected and correct: a personal capture carries no site, task, or job, and a
device must not be able to trigger paid GPU work by uploading. See "After the
capture" below.

## Monitoring

```
gcloud functions logs read extractFrames --project blueprint-8c1ca --region us-central1 --limit 50
```

```
gcloud firestore documents get "capture_submissions/<captureId>" --project blueprint-8c1ca
```

Storage objects land under
`gs://blueprint-8c1ca.appspot.com/scenes/<sceneId>/captures/<captureId>/raw/`.
The handoff receipt is written beside them as
`pipeline_handoff_pubsub_receipt.json`.

## Verifying capture truth

The device writes `raw/hashes.json` last, covering every other raw file, and
the Pipeline recomputes that agreement before accepting the capture. To check
by hand:

```
python -c "import json,hashlib,pathlib,sys; r=pathlib.Path(sys.argv[1]); a=json.loads((r/'hashes.json').read_text())['artifacts']; bad=[k for k,v in a.items() if hashlib.sha256((r/k).read_bytes()).hexdigest()!=v]; print('MISMATCH:',bad or 'none')" <raw-dir>
```

A capture whose bytes changed after hashing, or that carries a file the
manifest never listed, cannot acquire a capture digest and so cannot reach the
queue at all.

## After the capture — starting reconstruction

Two things are still needed before training can run, both requiring you:

1. **Stage the Postshot installer.** Install-at-boot needs the licensed MSI at
   a signed URL plus its SHA-256. The download is behind your Jawset account.
2. **Confirm the spend.** $50 authorized. The allocator admission has not been
   minted yet; it will bind that ceiling with `retry_cap=0`, a hard TTL, an
   independent watchdog, and provider-zero checks on both sides.

Then bind authority to the capture that landed:

```
python -m blueprint_pipeline.capture_reconstruction_launch_dispatcher bind-capture --policy-root <policy-root> --capture-id <captureId> --site-id site-my-living-room --task-id task-one-off-walk --selector profile_bound_quality_filter --parameters-json '{"allowed_tracking_states":["normal"],"require_pose_assisted_eligible":true,"exclude_relocalization_events":true}' --rights-profile operator_authorized_personal --rights-evidence-digest sha256:<64-hex> --arm postshot-primary --max-spend-usd 50 --hard-ttl-seconds 5400 --authority-id <authority-id>
```

That policy governs exactly that one capture. It does not authorize the next
one, and it does not leak to another capture sharing its site and task.

## Teardown and billing

This test allocates nothing, so there is nothing to tear down and no billing to
check. Current state verified 2026-08-17: **zero** non-terminated EC2 instances
in `us-east-1`, and no live Vast run (the `vast_paid_launch.lock` from Aug 12 is
stale; its PID is dead).

When training does run, closure is: `terminate()` plus a fresh API-confirmed
empty inventory. `stop()` is not closure, and an inventory call that fails or
returns an unreadable shape counts as unknown, never as zero.

## Rollback

Nothing deployed by this test. To roll back the build, reinstall the previous
TestFlight or device build. Capture bundles already uploaded are immutable by
design and are not deleted by a rollback; storage lifecycle governs retention.

## Honest boundary

Code, green tests, and this procedure do not establish device or reconstruction
performance. Until a real capture and a real authorized GPU run have produced
artifacts, the correct claim is "implementation ready for physical launch
qualification" — not "launch qualified", and not "reconstruction proven".
