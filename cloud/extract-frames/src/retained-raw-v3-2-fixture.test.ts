import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync, readdirSync } from "node:fs";
import path from "node:path";
import test from "node:test";

import { buildDownstreamCandidateIndex } from "./bridge.js";
import { validateRawCaptureBundleV3 } from "./raw-contract-v3.js";

const fixtureRoot = path.resolve(
  process.cwd(),
  "../../docs/fixtures/capture_raw_contract_v3_2_postshot_transport/raw",
);

function json(relativePath: string): Record<string, unknown> {
  return JSON.parse(readFileSync(path.join(fixtureRoot, relativePath), "utf8"));
}

function jsonl(relativePath: string): Record<string, unknown>[] {
  return readFileSync(path.join(fixtureRoot, relativePath), "utf8")
    .split("\n")
    .filter(Boolean)
    .map((line) => JSON.parse(line));
}

function fixtureFiles(directory = fixtureRoot, prefix = ""): string[] {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const absolutePath = path.join(directory, entry.name);
    const relativePath = path.posix.join(prefix, entry.name);
    return entry.isDirectory()
      ? fixtureFiles(absolutePath, relativePath)
      : [relativePath];
  });
}

function sha256(relativePath: string): string {
  return createHash("sha256")
    .update(readFileSync(path.join(fixtureRoot, relativePath)))
    .digest("hex");
}

test("retained procedural Raw V3.2 fixture is byte-complete and production-valid", () => {
  const filesPresent = new Set(fixtureFiles());
  const hashes = json("hashes.json");
  const artifacts = hashes.artifacts as Record<string, string>;

  assert.deepEqual(
    Object.keys(artifacts).sort(),
    [...filesPresent].filter((file) => file !== "hashes.json").sort(),
  );
  for (const [relativePath, expectedDigest] of Object.entries(artifacts)) {
    assert.equal(sha256(relativePath), expectedDigest, relativePath);
  }

  const validation = validateRawCaptureBundleV3({
    filesPresent,
    manifest: json("manifest.json"),
    provenance: json("provenance.json"),
    rightsConsent: json("rights_consent.json"),
    captureContext: json("capture_context.json"),
    recordingSession: json("recording_session.json"),
    captureTopology: json("capture_topology.json"),
    completionMarker: json("capture_upload_complete.json"),
    hashes,
    sessionIntrinsics: json("arkit/session_intrinsics.json"),
    depthManifest: json("arkit/depth_manifest.json"),
    confidenceManifest: json("arkit/confidence_manifest.json"),
    poses: jsonl("arkit/poses.jsonl"),
    frames: jsonl("arkit/frames.jsonl"),
    frameQuality: jsonl("arkit/frame_quality.jsonl"),
    syncMap: jsonl("sync_map.jsonl"),
    motion: jsonl("motion.jsonl"),
    semanticAnchorObservations: jsonl("semantic_anchor_observations.jsonl"),
  });
  assert.deepEqual(validation, { valid: true, blockers: [], warnings: [] });

  const candidateIndex = buildDownstreamCandidateIndex(
    json("downstream_candidate_manifest.json"),
  );
  assert.equal(candidateIndex.valid, true);
  assert.deepEqual(candidateIndex.errors, []);
  assert.equal(candidateIndex.byDecodedFrameOrdinal.size, 24);
});
