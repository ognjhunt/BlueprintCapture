# Android XR Offline No-Hardware Packet

Use this when you need an operator-ready Android XR hardware packet before any physical Android XR hardware, credentials, Firebase config, App Distribution, Gemini, Meta DAT, payout provider, or payment provider is available.

This command creates a valid **blocked** packet only. It does not prove hardware readiness.

## One Command

Run from the repo root:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 scripts/author_android_xr_no_hardware_packet.py --operator "$USER"
```

The helper writes:

- `output/android_xr_hardware_packets/<run-id>/packet.json`
- local evidence notes under `output/android_xr_hardware_packets/<run-id>/evidence/`

It records local git status, the current commit, a validator fixture check, and explicit blocked notes for `HW-P0` through `HW-P6`. It then validates the generated packet with:

```bash
python3 scripts/validate_android_xr_hardware_packet.py \
  --packet output/android_xr_hardware_packets/<run-id>/packet.json \
  --evidence-root output/android_xr_hardware_packets/<run-id> \
  --require-artifacts
```

Expected result:

```text
Android XR hardware packet validated offline: packet_status=blocked; blocked gates: HW-P0, HW-P1, HW-P2, HW-P3, HW-P4, HW-P5, HW-P6; no hardware or downstream readiness claims asserted.
```

## What Remains Blocked

- `HW-P0`: physical Android XR pairing/install proof
- `HW-P1`: projected activity launch proof
- `HW-P2`: projected camera/mic permission proof
- `HW-P3`: projected camera, mic, voice, battery, and thermal smoke
- `HW-P4`: real Android XR raw-bundle finalization
- `HW-P5`: upload queue or remote raw-prefix proof
- `HW-P6`: bridge, Pipeline, WebApp, hosted-review, buyer-access, payout, provider, and launch proof

## Rerun Tests

```bash
PYTHONDONTWRITEBYTECODE=1 python3 scripts/android_xr_hardware_packet_validator_tests.py
```

When hardware exists, use [Android XR Hardware Validation Packet](ANDROID_XR_HARDWARE_VALIDATION_PACKET_2026-05-23.md) and replace the blocked notes with real device evidence. Do not convert this offline packet into a completed packet.
