/**
 * Frame packing (SCALE2-03): pack extracted JPEG frames into a small number
 * of tar archives per capture instead of one GCS object per frame.
 *
 * At fps=5/512px a 3-minute capture produces ~900 individual objects; at 10k
 * captures that is ~9M small objects with Class-A operation cost and
 * per-object trigger noise. Packing at 200 frames/archive cuts object count
 * per capture from ~900 to ~6.
 *
 * Contract revision (frames_index.v2, coordinated with
 * BlueprintCapturePipeline docs/CAPTURE_BRIDGE_CONTRACT.md):
 *  - frames/index.jsonl entries stay one-per-frame; packed captures add
 *    `packaging: "tar"`, `archive`, `archive_member` per entry.
 *  - frames/packing_manifest.json declares
 *    `schema_version: "frames_index.v2"` + the archive list, so readers can
 *    detect the layout without heuristics. Legacy captures (no manifest, no
 *    `archive` fields) remain readable per-object (v1).
 *  - The capture_bridge_handoff.v1 message shape, the completion-marker
 *    protocol, and the keyframe object are untouched.
 *
 * Rollout: disabled by default behind BLUEPRINT_EXTRACT_FRAMES_PACKING_ENABLED
 * until the pipeline reader (blueprint_pipeline/frames_layout.py) is deployed
 * and verified; then flip the env to "1".
 *
 * Archives are plain USTAR written deterministically (fixed mtime/uid/gid) so
 * re-runs of the same capture produce byte-identical objects.
 */

export const FRAME_PACKING_ENV = "BLUEPRINT_EXTRACT_FRAMES_PACKING_ENABLED";
export const FRAMES_PER_ARCHIVE_ENV = "BLUEPRINT_EXTRACT_FRAMES_PER_ARCHIVE";
export const FRAMES_INDEX_SCHEMA_V2 = "frames_index.v2";
export const DEFAULT_FRAMES_PER_ARCHIVE = 200;

export function framePackingEnabled(env: NodeJS.ProcessEnv = process.env): boolean {
  return String(env[FRAME_PACKING_ENV] || "").trim() === "1";
}

export function framesPerArchive(env: NodeJS.ProcessEnv = process.env): number {
  const raw = Number(env[FRAMES_PER_ARCHIVE_ENV]);
  if (Number.isFinite(raw) && raw >= 1) {
    return Math.floor(raw);
  }
  return DEFAULT_FRAMES_PER_ARCHIVE;
}

export type FrameArchivePlan = {
  archiveName: string;
  members: string[];
};

export type FramePackingPlan = {
  archives: FrameArchivePlan[];
  memberToArchive: Map<string, string>;
};

/**
 * Deterministic packing plan: frames (already sorted) are grouped into
 * archives of `perArchive` members named frames_000.tar, frames_001.tar, …
 */
export function planFramePacking(
  sortedFrameFiles: string[],
  perArchive: number = DEFAULT_FRAMES_PER_ARCHIVE,
): FramePackingPlan {
  if (!Number.isFinite(perArchive) || perArchive < 1) {
    throw new Error(`Invalid frames-per-archive: ${perArchive}`);
  }
  const archives: FrameArchivePlan[] = [];
  const memberToArchive = new Map<string, string>();
  for (let start = 0; start < sortedFrameFiles.length; start += perArchive) {
    const members = sortedFrameFiles.slice(start, start + perArchive);
    const archiveName = `frames_${String(archives.length).padStart(3, "0")}.tar`;
    archives.push({ archiveName, members });
    for (const member of members) {
      memberToArchive.set(member, archiveName);
    }
  }
  return { archives, memberToArchive };
}

const TAR_BLOCK = 512;

function tarHeader(name: string, size: number): Buffer {
  if (Buffer.byteLength(name) > 100) {
    throw new Error(`tar member name too long: ${name}`);
  }
  const header = Buffer.alloc(TAR_BLOCK);
  header.write(name, 0, "utf8");
  header.write("0000644\0", 100, "utf8"); // mode
  header.write("0000000\0", 108, "utf8"); // uid
  header.write("0000000\0", 116, "utf8"); // gid
  header.write(size.toString(8).padStart(11, "0") + "\0", 124, "utf8");
  header.write("00000000000\0", 136, "utf8"); // mtime: epoch, deterministic
  header.write("        ", 148, "utf8"); // checksum placeholder (spaces)
  header.write("0", 156, "utf8"); // typeflag: regular file
  header.write("ustar\0", 257, "utf8"); // magic
  header.write("00", 263, "utf8"); // version
  let checksum = 0;
  for (const byte of header) {
    checksum += byte;
  }
  header.write(checksum.toString(8).padStart(6, "0") + "\0 ", 148, "utf8");
  return header;
}

/** Build a deterministic USTAR archive from named buffers. */
export function buildTarArchive(
  members: Array<{ name: string; data: Buffer }>,
): Buffer {
  const chunks: Buffer[] = [];
  for (const member of members) {
    chunks.push(tarHeader(member.name, member.data.length));
    chunks.push(member.data);
    const remainder = member.data.length % TAR_BLOCK;
    if (remainder !== 0) {
      chunks.push(Buffer.alloc(TAR_BLOCK - remainder));
    }
  }
  chunks.push(Buffer.alloc(TAR_BLOCK * 2)); // end-of-archive
  return Buffer.concat(chunks);
}

/** Minimal USTAR reader (verification + tests). Returns name -> bytes. */
export function readTarArchive(archive: Buffer): Map<string, Buffer> {
  const members = new Map<string, Buffer>();
  let offset = 0;
  while (offset + TAR_BLOCK <= archive.length) {
    const header = archive.subarray(offset, offset + TAR_BLOCK);
    if (header.every((byte) => byte === 0)) {
      break;
    }
    const name = header.subarray(0, 100).toString("utf8").replace(/\0.*$/, "");
    const size = parseInt(
      header.subarray(124, 136).toString("utf8").replace(/\0.*$/, "").trim(),
      8,
    );
    if (!Number.isFinite(size)) {
      throw new Error(`Corrupt tar header at offset ${offset}`);
    }
    const dataStart = offset + TAR_BLOCK;
    members.set(name, Buffer.from(archive.subarray(dataStart, dataStart + size)));
    const dataBlocks = Math.ceil(size / TAR_BLOCK);
    offset = dataStart + dataBlocks * TAR_BLOCK;
  }
  return members;
}

export type PackingManifest = {
  schema_version: typeof FRAMES_INDEX_SCHEMA_V2;
  packaging: "tar";
  frames_per_archive: number;
  frame_count: number;
  archives: Array<{ archive: string; member_count: number }>;
  generated_at: string;
};

export function buildPackingManifest(
  plan: FramePackingPlan,
  perArchive: number,
): PackingManifest {
  return {
    schema_version: FRAMES_INDEX_SCHEMA_V2,
    packaging: "tar",
    frames_per_archive: perArchive,
    frame_count: plan.memberToArchive.size,
    archives: plan.archives.map((archive) => ({
      archive: archive.archiveName,
      member_count: archive.members.length,
    })),
    generated_at: new Date().toISOString(),
  };
}
