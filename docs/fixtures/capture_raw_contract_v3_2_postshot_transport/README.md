# Raw V3.2 Postshot transport fixture

This directory contains a Blueprint-authored procedural Raw V3.2 capture bundle.
It is retained test evidence for producer-to-consumer transport, storage digest,
camera-order, Postshot import, export, and publication checks.

Truth boundary:

- No customer, person, or physical site is represented.
- The pixels, ARKit-shaped poses, depth, and confidence are procedural.
- Rights permit Blueprint's internal derived-processing test only.
- A Postshot result from this bundle is a development-only derived artifact.
- The fixture does not qualify metric alignment, reconstruction fidelity,
  collision geometry, task physics, robot behavior, or partner value.

`raw/` is the retained immutable example. `fixture_receipt.json` records its
capture identity and digests. Regenerate a production-unique copy with
`scripts/materialize_retained_raw_v3_2_fixture.py`; do not mutate the retained
example in place.
