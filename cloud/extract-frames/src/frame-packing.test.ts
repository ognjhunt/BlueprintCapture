import test from "node:test";
import assert from "node:assert/strict";

import {
  DEFAULT_FRAMES_PER_ARCHIVE,
  FRAMES_INDEX_SCHEMA_V2,
  buildPackingManifest,
  buildTarArchive,
  framePackingEnabled,
  framesPerArchive,
  planFramePacking,
  readTarArchive,
} from "./frame-packing.js";

function frameNames(count: number): string[] {
  return Array.from({ length: count }, (_, i) =>
    `${String(i + 1).padStart(6, "0")}.jpg`
  );
}

test("packing stays opt-in until the pipeline reader is verified", () => {
  assert.equal(framePackingEnabled({}), false);
  assert.equal(framePackingEnabled({ BLUEPRINT_EXTRACT_FRAMES_PACKING_ENABLED: "0" }), false);
  assert.equal(framePackingEnabled({ BLUEPRINT_EXTRACT_FRAMES_PACKING_ENABLED: "1" }), true);
  assert.equal(framesPerArchive({}), DEFAULT_FRAMES_PER_ARCHIVE);
  assert.equal(framesPerArchive({ BLUEPRINT_EXTRACT_FRAMES_PER_ARCHIVE: "50" }), 50);
});

test("planFramePacking groups a 900-frame capture into 5 archives of 200", () => {
  const plan = planFramePacking(frameNames(900), 200);
  assert.equal(plan.archives.length, 5);
  assert.deepEqual(
    plan.archives.map((a) => a.archiveName),
    ["frames_000.tar", "frames_001.tar", "frames_002.tar", "frames_003.tar", "frames_004.tar"]
  );
  assert.equal(plan.archives[0].members.length, 200);
  assert.equal(plan.archives[4].members.length, 100);
  assert.equal(plan.memberToArchive.get("000001.jpg"), "frames_000.tar");
  assert.equal(plan.memberToArchive.get("000201.jpg"), "frames_001.tar");
  assert.equal(plan.memberToArchive.get("000900.jpg"), "frames_004.tar");
  assert.equal(plan.memberToArchive.size, 900);
});

test("tar round-trip preserves member names and exact bytes", () => {
  const members = [
    { name: "000001.jpg", data: Buffer.from([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]) },
    { name: "000002.jpg", data: Buffer.from("second frame payload") },
    { name: "000003.jpg", data: Buffer.alloc(0) },
  ];
  const archive = buildTarArchive(members);
  // Blocked to 512 with a 1024-byte terminator.
  assert.equal(archive.length % 512, 0);

  const restored = readTarArchive(archive);
  assert.deepEqual(Array.from(restored.keys()), ["000001.jpg", "000002.jpg", "000003.jpg"]);
  for (const member of members) {
    assert.deepEqual(restored.get(member.name), member.data);
  }
});

test("tar output is deterministic for identical inputs", () => {
  const members = [{ name: "000001.jpg", data: Buffer.from("same bytes") }];
  assert.deepEqual(buildTarArchive(members), buildTarArchive(members));
});

test("packing manifest declares the v2 schema and archive inventory", () => {
  const plan = planFramePacking(frameNames(450), 200);
  const manifest = buildPackingManifest(plan, 200);
  assert.equal(manifest.schema_version, FRAMES_INDEX_SCHEMA_V2);
  assert.equal(manifest.packaging, "tar");
  assert.equal(manifest.frame_count, 450);
  assert.deepEqual(manifest.archives, [
    { archive: "frames_000.tar", member_count: 200 },
    { archive: "frames_001.tar", member_count: 200 },
    { archive: "frames_002.tar", member_count: 50 },
  ]);
});
