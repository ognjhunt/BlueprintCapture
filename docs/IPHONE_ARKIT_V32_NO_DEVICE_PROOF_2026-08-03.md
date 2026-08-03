# iPhone ARKit V3.2 no-device proof packet — 2026-08-03

## Current evidence

- The iOS app and selected test targets compile with `build-for-testing` for the
  installed iOS 26 simulator runtime.
- The versioned synthetic contract fixture and cloud bridge tests pass.
- `xcrun xctrace list devices` discovers an iPhone 17 Pro, but it is offline;
  `xcrun devicectl list devices` reports it as unavailable.
- The iOS 26 simulator reaches boot completion, then shuts down while Xcode is
  waiting for XCTest workers to materialize. Repeated targeted test launches
  therefore did not execute tests and were interrupted after preserving the
  XCTest result bundle.
- Older iOS 18 simulator records exist in CoreSimulator, but the current Xcode
  installation does not expose them as valid destinations for this scheme.

This packet is not physical-device, ARKit sensor, LiDAR, media-retention, or
end-to-end reconstruction proof.

## Exact open blockers

```text
physical_iphone_unavailable
actual_arkit_lidar_v3_2_capture_missing
actual_encoded_decoded_pts_binding_unverified
actual_depth_confidence_pose_intrinsics_bundle_unverified
actual_new_site_pipeline_admission_unverified
ios26_simulator_xctest_worker_materialization_unavailable
```

## Required physical-device run

1. Connect, unlock, and trust a LiDAR-capable iPhone; confirm it is `available`
   in `xcrun devicectl list devices`.
2. Record one previously unseen site through the shared ARKit recorder without
   changing site-specific code.
3. Export the canonical raw bundle and run the Capture validator. Preserve the
   bundle digest and validator output.
4. Confirm `video_frame_retention.jsonl`, `sync_map.jsonl`,
   `video_track.json`, and `downstream_candidate_manifest.json` agree on every
   retained ordinal, decoded source PTS, write attempt, frame/pose ID, site
   transform, intrinsics, and source-video SHA-256.
5. Confirm privacy, provider-upload denial, retention, and revocation fields in
   `rights_consent.json`; perform the latest authoritative revocation check
   before any downstream use.
6. Stage the unchanged bundle into Pipeline. Supply an explicit digest-bound
   `task_site_frame_selection_profile.v1`; without one, require the exact
   blocker `task_site_evidence_profile_with_frame_selection_parameters`.
7. Materialize only the admitted decoded ordinals, compile the frozen
   train/validation/hidden-held-out dataset, bind the ARKit metric scaffold, and
   continue through the normal reconstruction and Task Evaluation Run gates.

## Claim boundary after that run

A valid capture and admission would prove raw observation integrity and entry
to reconstruction preparation. Reconstruction quality, metric accuracy,
collision/physics validity, Isaac load/stability, Task Evaluation Run decisions,
and physical/deployment performance remain separate evidence gates.
