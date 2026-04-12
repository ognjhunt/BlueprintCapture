import test from "node:test";
import assert from "node:assert/strict";

import { validateRawCaptureBundleV3, type RawCaptureBundleV3Input } from "./raw-contract-v3.js";

function makeValidInput(): RawCaptureBundleV3Input {
  const filesPresent = new Set<string>([
    "manifest.json",
    "provenance.json",
    "rights_consent.json",
    "capture_context.json",
    "intake_packet.json",
    "task_hypothesis.json",
    "recording_session.json",
    "capture_topology.json",
    "route_anchors.json",
    "checkpoint_events.json",
    "relocalization_events.json",
    "overlap_graph.json",
    "video_track.json",
    "walkthrough.mov",
    "motion.jsonl",
    "semantic_anchor_observations.jsonl",
    "capture_upload_complete.json",
    "hashes.json",
    "sync_map.jsonl",
    "arkit/poses.jsonl",
    "arkit/frames.jsonl",
    "arkit/frame_quality.jsonl",
    "arkit/per_frame_camera_state.jsonl",
    "arkit/session_intrinsics.json",
    "arkit/depth_manifest.json",
    "arkit/confidence_manifest.json",
    "arkit/depth/000001.png",
    "arkit/confidence/000001.png",
  ]);

  return {
    filesPresent,
    manifest: {
      schema_version: "v3",
      capture_schema_version: "3.0.0",
      scene_id: "scene-1",
      capture_id: "capture-1",
      capture_source: "iphone",
      capture_tier_hint: "tier1_iphone",
      coordinate_frame_session_id: "cfs-1",
      video_uri: "raw/walkthrough.mov",
      capture_start_epoch_ms: 1700000000000,
      app_version: "1.0.0",
      app_build: "100",
      ios_version: "18.3.1",
      ios_build: "22D68",
      hardware_model_identifier: "iPhone16,2",
      device_model_marketing: "iPhone 15 Pro",
      capture_profile_id: "iphone_arkit_v3",
      has_lidar: true,
      depth_supported: true,
      fps_source: 30,
      width: 1920,
      height: 1440,
    },
    provenance: { scene_id: "scene-1", capture_id: "capture-1" },
    rightsConsent: { scene_id: "scene-1", capture_id: "capture-1", redaction_required: true },
    captureContext: { scene_id: "scene-1", capture_id: "capture-1" },
    recordingSession: { coordinate_frame_session_id: "cfs-1" },
    captureTopology: { coordinate_frame_session_id: "cfs-1" },
    completionMarker: { scene_id: "scene-1", capture_id: "capture-1" },
    hashes: { artifacts: { "arkit/depth/000001.png": "hash" } },
    sessionIntrinsics: { coordinate_frame_session_id: "cfs-1" },
    depthManifest: {
      frames: [
        {
          frame_id: "000001",
          depth_path: "arkit/depth/000001.png",
          paired_confidence_path: "arkit/confidence/000001.png",
        },
      ],
    },
    confidenceManifest: {
      frames: [
        {
          frame_id: "000001",
          confidence_path: "arkit/confidence/000001.png",
          paired_depth_path: "arkit/depth/000001.png",
        },
      ],
    },
    poses: [
      {
        frame_id: "000001",
        t_capture_sec: 0.0,
        coordinate_frame_session_id: "cfs-1",
        T_world_camera: [
          [1, 0, 0, 0],
          [0, 1, 0, 0],
          [0, 0, 1, 0],
          [0, 0, 0, 1],
        ],
      },
    ],
    frames: [{ frame_id: "000001", t_capture_sec: 0.0 }],
    frameQuality: [{ frame_id: "000001", t_capture_sec: 0.0 }],
    syncMap: [{ frame_id: "000001", t_capture_sec: 0.0 }],
    motion: [],
    semanticAnchorObservations: [],
  };
}

test("validateRawCaptureBundleV3 accepts a coherent canonical bundle", () => {
  const result = validateRawCaptureBundleV3(makeValidInput());
  assert.equal(result.valid, true);
  assert.deepEqual(result.blockers, []);
});

test("validateRawCaptureBundleV3 rejects coordinate frame mismatches and missing references", () => {
  const input = makeValidInput();
  input.recordingSession = { coordinate_frame_session_id: "cfs-2" };
  input.filesPresent.delete("arkit/confidence/000001.png");

  const result = validateRawCaptureBundleV3(input);
  assert.equal(result.valid, false);
  assert.ok(result.blockers.includes("coordinate_frame_session_mismatch:recording_session"));
  assert.ok(
    result.blockers.includes(
      "referenced_artifact_missing:depth:000001:arkit/confidence/000001.png"
    )
  );
});

test("validateRawCaptureBundleV3 rejects missing canonical V3 files", () => {
  const input = makeValidInput();
  input.filesPresent.delete("route_anchors.json");

  const result = validateRawCaptureBundleV3(input);
  assert.equal(result.valid, false);
  assert.ok(result.blockers.includes("missing_required_file:route_anchors.json"));
});

test("validateRawCaptureBundleV3 rejects malformed motion.jsonl rows", () => {
  const input = makeValidInput();
  input.motion = [{ timestamp: 1.0 }]; // missing required fields

  const result = validateRawCaptureBundleV3(input);
  assert.equal(result.valid, false);
  assert.ok(result.blockers.some((b) => b.startsWith("motion_missing_field:")));
});

test("validateRawCaptureBundleV3 rejects motion attitude with missing sub-fields", () => {
  const input = makeValidInput();
  input.motion = [
    {
      timestamp: 1.0,
      t_capture_sec: 0.0,
      t_monotonic_ns: 0,
      wall_time: "2026-03-20T14:00:29.857Z",
      motion_provenance: "test",
      attitude: { roll: 0.1 }, // missing pitch, yaw, quaternion
      rotation_rate: { x: 0, y: 0, z: 0 },
      gravity: { x: 0, y: 0, z: 0 },
      user_acceleration: { x: 0, y: 0, z: 0 },
    },
  ];

  const result = validateRawCaptureBundleV3(input);
  assert.equal(result.valid, false);
  assert.ok(result.blockers.includes("motion_attitude_missing_field:pitch:line_1"));
  assert.ok(result.blockers.includes("motion_attitude_missing_field:quaternion:line_1"));
});

test("validateRawCaptureBundleV3 rejects malformed semantic_anchor_observations rows", () => {
  const input = makeValidInput();
  input.semanticAnchorObservations = [{ anchor_instance_id: "a1" }]; // missing required fields

  const result = validateRawCaptureBundleV3(input);
  assert.equal(result.valid, false);
  assert.ok(result.blockers.some((b) => b.startsWith("semantic_anchor_missing_field:")));
});
