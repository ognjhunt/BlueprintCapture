# Optional Niantic NSDK Capture Augmentation

## Decision

Blueprint Capture Raw Contract V3.2 remains the only canonical capture input for
reconstruction. The Niantic Spatial SDK integration is a disabled-by-default,
same-`ARSession` recorder that can attach a byte-exact vendor archive for a
separate qualification experiment. It does not generate a 3D Gaussian splat,
replace Blueprint timestamps or poses, or authorize a Niantic reconstruction
route. No Niantic reconstruction endpoint is configured or shipped.

The production reconstruction path consumes the canonical retained RGB frames,
decoded presentation timestamps, `sync_map.jsonl`, raw ARKit poses, intrinsics,
and depth/confidence pairs. Postshot is the initial quality-oriented trainer and
Splatfacto is the controlled open implementation comparison. Both must consume
the same immutable candidate-only COLMAP dataset.

## Activation gates

All gates must be present at runtime. Values are read from the process
environment only; tokens are never read from `Info.plist`.

| Variable | Default | Purpose |
| --- | --- | --- |
| `BLUEPRINT_ENABLE_NIANTIC_SCAN_AUGMENTATION` | `false` | Explicitly opts into the secondary recorder. |
| `BLUEPRINT_NIANTIC_BUSINESS_TERMS_AUTHORIZED` | `false` | Operator attests that current terms, privacy, consent, and capture scope authorize the run. |
| `BLUEPRINT_NIANTIC_ACCESS_TOKEN` | unset | Short-lived runtime token. Never commit or bundle it. |
| `BLUEPRINT_NIANTIC_REQUIRE_LIDAR` | `true` | Keeps the experimental lane on devices with platform depth. |
| `BLUEPRINT_NIANTIC_EXPORT_AS_VIDEO` | `false` | Individual vendor images are the quality-first default. |
| `BLUEPRINT_NIANTIC_SCAN_FPS` | `30` | Requested vendor scan cadence. |
| `BLUEPRINT_NIANTIC_ENABLE_FULL_RESOLUTION` | `true` | Requests full-resolution vendor images. |
| `BLUEPRINT_NIANTIC_FULL_RESOLUTION_FPS` | `5` | Conservative starting cadence pending thermal qualification. |
| `BLUEPRINT_NIANTIC_MINIMUM_FREE_DISK_BYTES` | `10737418240` | Protects canonical recording from disk contention. |

Production authentication must use a short-lived access token issued by a
Blueprint backend. Developer tokens are limited to internal testing and must
not be shipped in an app build.

The pinned NSDK package includes a Metal playback shader, so the selected Xcode
installation must have its matching Metal Toolchain component installed and
mountable even though Blueprint's capture wrapper does not use playback during
recording. A missing or permission-blocked Metal component is a host toolchain
failure, not evidence that the device scanning backend compiled successfully.

## Bundle layout

On a successful opt-in run, the raw directory additionally contains:

```text
nsdk/
  archive_manifest.json
  reconstruction_binding.json
  archives/
    nsdk_scan_archive_000.tgz
```

`archive_manifest.json` records the SDK version, profile, byte size, SHA-256,
terms attestation, frame count reported by the vendor, and explicit
`canonical_capture_authority=false`. `reconstruction_binding.json` records only
a candidate association. Timestamp domains and coordinate conventions must be
inspected and residual-tested before an alignment claim.

An export failure leaves a failure manifest and no partial archive. A skipped
or failed NSDK run never invalidates the canonical V3.2 capture.

## Device qualification before enabling

Run paired captures on the same supported iPhone with augmentation off and on.
Do not enable the feature for production unless all of these are measured:

1. Canonical decoded/retained-frame count and backpressure-drop rate do not
   regress beyond the precommitted threshold.
2. Canonical video resolution, bitrate, exposure, focus, motion blur, depth
   retention, pose continuity, and timestamp residuals remain within the V3.2
   qualification envelope.
3. Thermal state, memory pressure, free disk, export duration, and crash rate
   remain acceptable for the intended capture duration.
4. The vendor archive parses; its timestamps, intrinsics, poses, images, and
   depth sources are inventoried; time and pose residuals to canonical evidence
   are reported rather than assumed.
5. A blinded held-out reconstruction comparison demonstrates a material quality
   benefit. An archive or attractive screenshot is not sufficient evidence.

Until those gates pass, NSDK is an experimental supplemental recording only.
