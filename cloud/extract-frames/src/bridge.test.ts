import test from "node:test";
import assert from "node:assert/strict";

import {
  buildPoseIndex,
  chooseKeyframeCandidate,
  evaluateQualityGate,
  findClosestPoseByTime,
  parsePoseRows,
} from "./bridge.js";

test("parsePoseRows supports legacy schema and derives frame_id/t_device_sec", () => {
  const content = [
    JSON.stringify({
      frameIndex: 0,
      timestamp: 100.0,
      transform: [
        [1, 0, 0, 0],
        [0, 1, 0, 0],
        [0, 0, 1, 0],
        [0, 0, 0, 1],
      ],
    }),
    JSON.stringify({
      frameIndex: 1,
      timestamp: 100.033,
      transform: [
        [1, 0, 0, 0.1],
        [0, 1, 0, 0.2],
        [0, 0, 1, 0.3],
        [0, 0, 0, 1],
      ],
    }),
  ].join("\n");

  const rows = parsePoseRows(content);
  assert.equal(rows.length, 2);
  assert.equal(rows[0].frame_id, "000001");
  assert.equal(rows[1].frame_id, "000002");
  assert.equal(rows[0].t_device_sec, 0);
  assert.equal(rows[1].t_device_sec, 0.033);
  assert.equal(rows[0].source_schema, "legacy");
});

test("parsePoseRows supports v2 schema and preserves frame_id/t_device_sec", () => {
  const content = JSON.stringify({
    pose_schema_version: "2.0",
    frameIndex: 7,
    timestamp: 12.34,
    transform: [
      [1, 0, 0, 0],
      [0, 1, 0, 0],
      [0, 0, 1, 0],
      [0, 0, 0, 1],
    ],
    frame_id: "000008",
    t_device_sec: 0.267,
    T_world_camera: [
      [1, 0, 0, 0],
      [0, 1, 0, 0],
      [0, 0, 1, 0],
      [0, 0, 0, 1],
    ],
  });

  const rows = parsePoseRows(content);
  assert.equal(rows.length, 1);
  assert.equal(rows[0].frame_id, "000008");
  assert.equal(rows[0].t_device_sec, 0.267);
  assert.equal(rows[0].pose_schema_version, "2.0");
});

test("findClosestPoseByTime falls back to nearest timestamp", () => {
  const rows = parsePoseRows(
    [
      JSON.stringify({ frame_id: "000001", t_device_sec: 0.0 }),
      JSON.stringify({ frame_id: "000002", t_device_sec: 0.2 }),
      JSON.stringify({ frame_id: "000003", t_device_sec: 0.4 }),
    ].join("\n")
  );
  const index = buildPoseIndex(rows);
  const pose = findClosestPoseByTime(index.byTime, 0.31);
  assert.equal(pose?.frame_id, "000003");
});

test("chooseKeyframeCandidate uses middle-third and sharpness proxy", () => {
  const files = ["000001.jpg", "000002.jpg", "000003.jpg", "000004.jpg", "000005.jpg", "000006.jpg"];
  const sizes: Record<string, number> = {
    "000001.jpg": 1000,
    "000002.jpg": 1200,
    "000003.jpg": 4000,
    "000004.jpg": 3500,
    "000005.jpg": 1500,
    "000006.jpg": 900,
  };
  const candidate = chooseKeyframeCandidate(files, (name) => sizes[name]);
  assert.equal(candidate?.fileName, "000003.jpg");
  assert.equal(candidate?.candidateCount, 2);
});

test("evaluateQualityGate passes tier1 iPhone with strong pose alignment", () => {
  const result = evaluateQualityGate({
    captureSource: "iphone",
    manifestPresent: true,
    manifestValid: true,
    requiredFiles: { walkthrough: true, manifest: true },
    frameCount: 40,
    poseMatchRate: 0.9,
    p95PoseDeltaSec: 0.1,
  });
  assert.equal(result.status, "passed");
  assert.equal(result.captureTier, "tier1_iphone");
  assert.equal(result.nurecMode, "mono_pose_assisted");
});

test("evaluateQualityGate demotes degraded iPhone capture to tier2", () => {
  const result = evaluateQualityGate({
    captureSource: "iphone",
    manifestPresent: true,
    manifestValid: true,
    requiredFiles: { walkthrough: true, manifest: true },
    frameCount: 40,
    poseMatchRate: 0.2,
    p95PoseDeltaSec: 0.5,
  });
  assert.equal(result.status, "passed");
  assert.equal(result.captureTier, "tier2_glasses");
  assert.equal(result.nurecMode, "mono_slam");
  assert.ok(result.warnings.includes("insufficient_arkit_alignment_demoted_to_tier2"));
});

test("evaluateQualityGate blocks invalid manifest", () => {
  const result = evaluateQualityGate({
    captureSource: "glasses",
    manifestPresent: true,
    manifestValid: false,
    requiredFiles: { walkthrough: true, manifest: true },
    frameCount: 50,
    poseMatchRate: 0,
    p95PoseDeltaSec: null,
  });
  assert.equal(result.status, "blocked");
  assert.ok(result.reasons.includes("invalid_manifest"));
});
