# Single-Walk Postshot Launch Readiness

## Product workflow

The canonical iPhone Pro workflow is one continuous guided closed-loop walk:

1. Hold at the start point until the app establishes the entry anchor.
2. Walk the site once, pausing at stable doorways, intersections, thresholds, and task-critical structure.
3. Reobserve shared structure while returning in the same recording.
4. Finish at the start point and hold until the app reports that the route is closed.

No ruler, marker, or second routine capture is required. A targeted recapture is requested only when evidence is missing or a bound task/site gate fails.

## Captured evidence

Canonical iPhone bundles contain the native ARKit RGB video and decoded-PTS retention map, metric `T_world_camera` poses, intrinsics, Core Motion, scene depth and confidence, feature points, planes, tracking state, light/exposure state, and world-space ARKit mesh OBJ files. The depth manifest declares portable encoding, scale, ray convention, registered-camera relationship, and depth-resolution intrinsics. Meshes are always labeled `candidate_only` for collision use.

The bridge must associate sampled review frames through `sync_map.jsonl`; extracted thumbnail numbering is never treated as the source ARKit frame ID. BlueprintPipeline can then extract full-resolution, no-auto-rotate RGB frames and construct registered COLMAP camera/point inputs for Postshot.

## Qualification boundary

`reconstruction_qualification_request.json` records Capture-observed facts and requests:

- loop closure;
- tracking quality;
- depth reprojection error;
- mesh coverage;
- floor/support continuity;
- physical collision probes;
- registered Postshot reconstruction quality.

Thresholds come from a digest-bound task/site evidence profile. Capture abstains while any downstream measurement is absent. BlueprintPipeline may qualify scale and collisions only when all required checks pass; otherwise it returns the smallest missing measurement or targeted recapture.

## Periodic device calibration

The preflight calibration sheet measures a flat known rig at a declared distance using only high-confidence (`2`) center LiDAR samples. It stores a 90-day hardware-model-bound profile with median error, median absolute deviation, sample count, thresholds, result, and expiry. This is optional for routine walking and cannot qualify a site or collision mesh by itself.

## Launch proof still required

Code, simulator tests, and bundle validation do not establish device or reconstruction performance. Before a launch claim, archive evidence for:

- a supported physical iPhone Pro/LiDAR recording of the complete single-walk route;
- bundle validation with decoded-frame/pose/depth/confidence/mesh hash integrity;
- Postshot import using full-resolution RGB plus generated COLMAP poses and points, with registration retained in the ARKit metric frame;
- held-out depth reprojection, coverage, floor/support, and collision-probe results under at least one real task/site profile;
- an intentional failure showing deterministic abstention and the smallest requested recapture;
- calibration pass and fail trials against the known rig;
- release archive, privacy/permission, upload/retry, and supported-device checks.

Until those artifacts exist, the correct claim is “implementation ready for physical launch qualification,” not “perfect reconstruction” or “launch qualified.”
