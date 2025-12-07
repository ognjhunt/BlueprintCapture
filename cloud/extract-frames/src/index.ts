import { onObjectFinalized } from "firebase-functions/v2/storage";
import * as logger from "firebase-functions/logger";
import { Storage } from "@google-cloud/storage";
import { tmpdir } from "os";
import { join, dirname, basename } from "path";
import {
  mkdirSync,
  writeFileSync,
  readdirSync,
  statSync,
  readFileSync,
  createWriteStream,
} from "fs";
import { spawn } from "child_process";
import ffmpegInstaller from "@ffmpeg-installer/ffmpeg";
import ffprobeInstaller from "@ffprobe-installer/ffprobe";
import AdmZip from "adm-zip";
import archiver from "archiver";

const storage = new Storage();

type StorageBucket = ReturnType<typeof storage.bucket>;

type PoseRow = {
  frame_id?: string;
  t_device_sec?: number;
  T_world_camera?: number[][];
  [key: string]: unknown;
};

type PoseIndex = {
  byFrameId: Map<string, PoseRow>;
  byTime: PoseRow[];
};

type PoseMatchType = "frame_id" | "time";

function zeroPad(n: number, width: number): string {
  const s = String(n);
  return s.length >= width ? s : "0".repeat(width - s.length) + s;
}

async function runCommand(
  cmd: string,
  args: string[],
  opts: { cwd?: string; env?: NodeJS.ProcessEnv } = {}
): Promise<{ stdout: string; stderr: string; code: number | null }> {
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, args, { stdio: ["ignore", "pipe", "pipe"], ...opts });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (d) => (stdout += d.toString()));
    child.stderr.on("data", (d) => (stderr += d.toString()));
    child.on("error", reject);
    child.on("close", (code) => resolve({ stdout, stderr, code }));
  });
}

function parsePoseRows(content: string): PoseRow[] {
  const rows: PoseRow[] = [];
  const lines = content.split(/\r?\n/);
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();
    if (!line) continue;
    try {
      const parsed = JSON.parse(line) as PoseRow;
      rows.push(parsed);
    } catch (error) {
      logger.warn("Failed to parse ARKit pose row", { lineNumber: i + 1, error });
    }
  }
  return rows;
}

async function loadArkitPoses(
  bucket: StorageBucket,
  rawPrefix: string,
  tmpDir: string
): Promise<PoseIndex> {
  const posesObjectName = `${rawPrefix}/arkit/poses.jsonl`;
  const posesFile = bucket.file(posesObjectName);
  let exists = false;
  try {
    [exists] = await posesFile.exists();
  } catch (error) {
    logger.error("Failed to check existence of ARKit poses", { posesObjectName, error });
    return { byFrameId: new Map(), byTime: [] };
  }
  if (!exists) {
    logger.info("No ARKit pose log found", { posesObjectName });
    return { byFrameId: new Map(), byTime: [] };
  }

  const localPosesPath = join(tmpDir, `arkit-poses-${Date.now()}.jsonl`);
  try {
    await posesFile.download({ destination: localPosesPath });
  } catch (error) {
    logger.error("Failed to download ARKit pose log", { posesObjectName, error });
    return { byFrameId: new Map(), byTime: [] };
  }

  let content: string;
  try {
    content = readFileSync(localPosesPath, { encoding: "utf8" });
  } catch (error) {
    logger.error("Failed to read downloaded ARKit pose log", { posesObjectName, error });
    return { byFrameId: new Map(), byTime: [] };
  }

  const rows = parsePoseRows(content);
  const byFrameId = new Map<string, PoseRow>();
  const byTime: PoseRow[] = [];
  for (const row of rows) {
    if (typeof row.frame_id === "string") {
      byFrameId.set(row.frame_id, row);
    }
    if (typeof row.t_device_sec === "number") {
      byTime.push(row);
    }
  }
  byTime.sort((a, b) => (a.t_device_sec ?? 0) - (b.t_device_sec ?? 0));
  logger.info("Loaded ARKit pose entries", { posesObjectName, count: rows.length });
  return { byFrameId, byTime };
}

function findClosestPoseByTime(poses: PoseRow[], targetTime: number): PoseRow | undefined {
  if (!poses.length) return undefined;
  let low = 0;
  let high = poses.length - 1;
  while (low < high) {
    const mid = Math.floor((low + high) / 2);
    const midTime = poses[mid].t_device_sec ?? Number.NEGATIVE_INFINITY;
    if (midTime < targetTime) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  let best = poses[low];
  const bestTime = best.t_device_sec;
  const bestDiff =
    bestTime !== undefined ? Math.abs(bestTime - targetTime) : Number.POSITIVE_INFINITY;
  const prev = low > 0 ? poses[low - 1] : undefined;
  if (prev && prev.t_device_sec !== undefined) {
    const prevDiff = Math.abs(prev.t_device_sec - targetTime);
    if (prevDiff <= bestDiff) {
      best = prev;
    }
  }
  return best;
}

/**
 * extractFrames
 * - Trigger: targets/<scene>/raw/walkthrough.mov
 * - Output: targets/<scene>/frames/*.jpg + index.jsonl
 * - FPS: 5
 * - Includes best-matching ARKit pose per frame when available.
 */
export const extractFrames = onObjectFinalized(
  {
    region: "us-central1",
    memory: "2GiB",
    timeoutSeconds: 540,
    cpu: 2,
  },
  async (event) => {
    const bucketName = event.bucket;
    const objectName = event.data?.name || "";
    const contentType = event.data?.contentType || "";

    // Only handle: targets/<scene_id>/raw/walkthrough.mov
    if (!objectName.endsWith("/raw/walkthrough.mov") || !objectName.startsWith("targets/")) {
      logger.info("Skipping object (not a walkthrough.mov under targets/*/raw/)", {
        objectName,
        contentType,
      });
      return;
    }

    logger.info("Starting frame extraction", { bucketName, objectName });

    const tmp = tmpdir();
    const localVideo = join(tmp, `video-${Date.now()}.mov`);
    const framesDir = join(tmp, `frames-${Date.now()}`);
    mkdirSync(framesDir, { recursive: true });

    const bucket = storage.bucket(bucketName);
    const file = bucket.file(objectName);
    const rawPrefix = dirname(objectName); // targets/<scene>/raw

    // Load ARKit poses (if present)
    const poseIndex = await loadArkitPoses(bucket, rawPrefix, tmp);

    // Download video
    await file.download({ destination: localVideo });
    logger.info("Downloaded video to temp", { localVideo });

    // Extract frames using ffmpeg fps=5 and scale longest side to 512 with Lanczos
    // Also include showinfo after fps so pts_time corresponds to output frames
    const outputPattern = join(framesDir, "%06d.jpg");
    const ffmpegArgs = [
      "-hide_banner",
      "-loglevel",
      "info",
      "-y",
      "-i",
      localVideo,
      "-vf",
      "fps=5,scale=512:-2:flags=lanczos,showinfo",
      "-qscale:v",
      "2",
      "-start_number",
      "1",
      outputPattern,
    ];

    const env = {
      ...process.env,
      FFMPEG_PATH: ffmpegInstaller.path,
      FFPROBE_PATH: ffprobeInstaller.path,
    };
    const { stderr, code } = await runCommand(ffmpegInstaller.path, ffmpegArgs, { env });
    if (code !== 0) {
      logger.error("ffmpeg failed", { code, stderr: stderr.slice(-4000) });
      throw new Error(`ffmpeg failed with code ${code}`);
    }

    // Parse pts_time values from showinfo lines
    const timeRegex = /showinfo.*pts_time:([0-9]+\.?[0-9]*)/g;
    const ptsTimes: number[] = [];
    for (const line of stderr.split(/\r?\n/)) {
      let m: RegExpExecArray | null;
      timeRegex.lastIndex = 0;
      while ((m = timeRegex.exec(line)) !== null) {
        const t = parseFloat(m[1]);
        if (!Number.isNaN(t)) ptsTimes.push(t);
      }
    }

    // Build index.jsonl mapping frame_id -> t_video_sec (+ ARKit pose match)
    const sortedFiles = readdirSync(framesDir)
      .filter((f) => f.toLowerCase().endsWith(".jpg"))
      .sort();

    const indexLines: string[] = [];
    const posesByFrameId = poseIndex.byFrameId;
    const posesByTime = poseIndex.byTime;

    for (let i = 0; i < sortedFiles.length; i++) {
      const frameId = zeroPad(i + 1, 6);
      const t = i < ptsTimes.length ? ptsTimes[i] : i / 5.0;
      const tVideoSec = Number(t.toFixed(6));

      const entry: Record<string, unknown> = {
        frame_id: frameId,
        t_video_sec: tVideoSec,
      };

      let poseMatchType: PoseMatchType | undefined;
      let pose = posesByFrameId.get(frameId);
      if (pose) {
        poseMatchType = "frame_id";
      } else if (posesByTime.length > 0) {
        pose = findClosestPoseByTime(posesByTime, tVideoSec);
        if (pose) {
          poseMatchType = "time";
        }
      }

      if (pose) {
        const arkitPose: Record<string, unknown> = {};
        const poseFrameId = typeof pose.frame_id === "string" ? pose.frameId : pose.frame_id;

        if (typeof pose.frame_id === "string") {
          arkitPose.pose_frame_id = pose.frame_id;
          if (pose.frame_id !== frameId) {
            arkitPose.frame_id_mismatch = true;
          }
        }

        if (Array.isArray(pose.T_world_camera)) {
          arkitPose.T_world_camera = pose.T_world_camera;
        }

        if (typeof pose.t_device_sec === "number" && Number.isFinite(pose.t_device_sec)) {
          const tDevice = Number(pose.t_device_sec.toFixed(6));
          arkitPose.t_device_sec = tDevice;
          const delta = Math.abs(tDevice - tVideoSec);
          arkitPose.delta_sec = Number(delta.toFixed(6));
        }

        if (poseMatchType) {
          arkitPose.match_type = poseMatchType;
        }

        if (Object.keys(arkitPose).length > 0) {
          entry.arkit_pose = arkitPose;
        }
      }

      indexLines.push(JSON.stringify(entry));
    }

    const indexPath = join(framesDir, "index.jsonl");
    writeFileSync(indexPath, indexLines.join("\n"), { encoding: "utf8" });

    // Upload all frames and index.jsonl to frames/ prefix next to raw/
    // Input: targets/<scene>/raw/walkthrough.mov -> Output: targets/<scene>/frames/<files>
    const scenePrefix = dirname(dirname(objectName)); // targets/<scene>
    const framesPrefix = `${scenePrefix}/frames`;
    const uploads: Promise<any>[] = [];
    for (const fname of readdirSync(framesDir)) {
      const localPath = join(framesDir, fname);
      const dest = `${framesPrefix}/${fname}`;
      const ct = fname.endsWith(".jpg")
        ? "image/jpeg"
        : fname.endsWith(".jsonl")
        ? "application/json"
        : undefined;
      uploads.push(
        bucket.upload(localPath, {
          destination: dest,
          metadata: ct ? { contentType: ct } : undefined,
        })
      );
    }
    await Promise.all(uploads);
    logger.info("Uploaded frames and index", { framesPrefix, count: sortedFiles.length });
  }
);

/* ---------- RoomPlan cleaning helpers ---------- */

function addDirToZip(zip: AdmZip, rootDir: string, currentDir: string) {
  const entries = readdirSync(currentDir);
  for (const name of entries) {
    const full = join(currentDir, name);
    const relPath = full.substring(rootDir.length + 1);
    const stats = statSync(full);
    if (stats.isDirectory()) {
      addDirToZip(zip, rootDir, full);
    } else {
      zip.addLocalFile(full, dirname(relPath), name);
    }
  }
}

function findFileRecursive(rootDir: string, targetFileName: string): string | null {
  const entries = readdirSync(rootDir);
  for (const name of entries) {
    const full = join(rootDir, name);
    const stats = statSync(full);
    if (stats.isDirectory()) {
      const found = findFileRecursive(full, targetFileName);
      if (found) {
        return found;
      }
    } else if (name === targetFileName) {
      return full;
    }
  }
  return null;
}

function removeObjectGrpFromUsd(usdContent: string): string {
  const lines = usdContent.split("\n");
  const output: string[] = [];
  let insideObjectGrp = false;
  let braceDepth = 0;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const trimmed = line.trim();

    if (insideObjectGrp) {
      const openBraces = (line.match(/{/g) || []).length;
      const closeBraces = (line.match(/}/g) || []).length;
      braceDepth += openBraces - closeBraces;

      if (braceDepth <= 0) {
        insideObjectGrp = false;
        braceDepth = 0;
      }
      continue;
    }

    if (trimmed.startsWith("def ") && trimmed.includes('"Object_grp"')) {
      insideObjectGrp = true;
      const openBraces = (line.match(/{/g) || []).length;
      const closeBraces = (line.match(/}/g) || []).length;
      braceDepth = openBraces - closeBraces;
      continue;
    }

    if (trimmed.startsWith("over ") && trimmed.includes('"Object_grp"')) {
      insideObjectGrp = true;
      const openBraces = (line.match(/{/g) || []).length;
      const closeBraces = (line.match(/}/g) || []).length;
      braceDepth = openBraces - closeBraces;
      continue;
    }

    output.push(line);
  }

  return output.join("\n");
}

function getAllFilesInDir(dir: string, fileList: string[] = []): string[] {
  const files = readdirSync(dir);
  for (const file of files) {
    const filePath = join(dir, file);
    const stats = statSync(filePath);
    if (stats.isDirectory()) {
      getAllFilesInDir(filePath, fileList);
    } else {
      fileList.push(filePath);
    }
  }
  return fileList;
}

async function createUncompressedUsdz(sourceDir: string, outputPath: string): Promise<void> {
  return new Promise((resolve, reject) => {
    const output = createWriteStream(outputPath);
    const archive = archiver("zip", {
      store: true,
      zlib: { level: 0 },
    });

    output.on("close", () => {
      logger.info(`Created USDZ with ${archive.pointer()} bytes`);
      resolve();
    });

    archive.on("error", (err) => {
      reject(err);
    });

    archive.pipe(output);

    const allFiles = getAllFilesInDir(sourceDir);
    const usdFiles = allFiles.filter((f) => f.endsWith(".usdc") || f.endsWith(".usda"));
    const otherFiles = allFiles.filter((f) => !f.endsWith(".usdc") && !f.endsWith(".usda"));

    if (usdFiles.length > 0) {
      const firstFile = usdFiles[0];
      const relativePath = firstFile.substring(sourceDir.length + 1);
      archive.file(firstFile, { name: relativePath });
    }

    const sortedOtherFiles = [...usdFiles.slice(1), ...otherFiles].sort();
    for (const file of sortedOtherFiles) {
      const relativePath = file.substring(sourceDir.length + 1);
      archive.file(file, { name: relativePath });
    }

    archive.finalize();
  });
}

async function processUsdzToRemoveObjects(
  usdzPath: string,
  outputPath: string
): Promise<void> {
  const extractDir = join(dirname(usdzPath), `usdz-extract-${Date.now()}`);
  mkdirSync(extractDir, { recursive: true });

  const zip = new AdmZip(usdzPath);
  zip.extractAllTo(extractDir, true);

  const allFiles = getAllFilesInDir(extractDir);
  for (const filePath of allFiles) {
    const fileName = basename(filePath);
    if (fileName.endsWith(".usda") || fileName.endsWith(".usd")) {
      try {
        const content = readFileSync(filePath, "utf8");
        const modified = removeObjectGrpFromUsd(content);
        writeFileSync(filePath, modified, "utf8");
        logger.info(`Modified USD file: ${fileName}`);
      } catch (err) {
        logger.warn(`Could not read/modify ${fileName} as text, skipping`, { error: err });
      }
    }
  }

  await createUncompressedUsdz(extractDir, outputPath);
  logger.info(`Created modified USDZ: ${outputPath}`);
}

/**
 * cleanRoomplan
 * - Trigger: targets/<scene>/raw/roomplan.zip
 * - Looks for RoomPlanParametric.usdz inside the zip
 * - Writes RoomPlanArchitectureOnly.usdz with Object_grp removed
 * - Re-zips and uploads to targets/<scene>/processed/roomplan.zip
 */
export const cleanRoomplan = onObjectFinalized(
  {
    region: "us-central1",
    memory: "2GiB",
    timeoutSeconds: 540,
    cpu: 2,
  },
  async (event) => {
    const bucketName = event.bucket;
    const objectName = event.data?.name || "";
    const contentType = event.data?.contentType || "";

    if (!objectName.startsWith("targets/") || !objectName.endsWith("/raw/roomplan.zip")) {
      logger.info("Skipping object (not a roomplan.zip under targets/*/raw/)", {
        objectName,
        contentType,
      });
      return;
    }

    logger.info("Starting RoomPlan cleanup", { bucketName, objectName });

    const bucket = storage.bucket(bucketName);
    const tmp = tmpdir();
    const localZip = join(tmp, `roomplan-${Date.now()}.zip`);
    const extractDir = join(tmp, `roomplan-extract-${Date.now()}`);
    mkdirSync(extractDir, { recursive: true });

    await bucket.file(objectName).download({ destination: localZip });

    const zip = new AdmZip(localZip);
    zip.extractAllTo(extractDir, true);

    const usdzPath = findFileRecursive(extractDir, "RoomPlanParametric.usdz");
    if (!usdzPath) {
      logger.error("RoomPlanParametric.usdz not found after unzip", {
        extractDir,
      });
      return;
    }

    const roomplanDir = dirname(usdzPath);
    logger.info("Found RoomPlanParametric.usdz", {
      usdzPath,
      roomplanDir,
    });

    const architectureOnlyPath = join(roomplanDir, "RoomPlanArchitectureOnly.usdz");
    await processUsdzToRemoveObjects(usdzPath, architectureOnlyPath);

    const processedZipPath = join(tmp, `roomplan-processed-${Date.now()}.zip`);
    const newZip = new AdmZip();
    addDirToZip(newZip, extractDir, extractDir);
    newZip.writeZip(processedZipPath);

    const scenePrefix = dirname(dirname(objectName)); // targets/<scene>
    const processedObjectName = `${scenePrefix}/processed/roomplan.zip`;

    await bucket.upload(processedZipPath, {
      destination: processedObjectName,
      metadata: { contentType: "application/zip" },
    });

    logger.info("Uploaded processed RoomPlan zip with architecture-only USDZ", {
      processedObjectName,
    });
  }
);
