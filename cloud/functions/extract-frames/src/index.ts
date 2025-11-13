import { onObjectFinalized } from "firebase-functions/v2/storage";
import * as logger from "firebase-functions/logger";
import { Storage } from "@google-cloud/storage";
import { tmpdir } from "os";
import { join, dirname } from "path";
import { mkdirSync, writeFileSync, readdirSync, readFileSync } from "fs";
import { spawn } from "child_process";
import ffmpegInstaller from "@ffmpeg-installer/ffmpeg";
import ffprobeInstaller from "@ffprobe-installer/ffprobe";

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

async function runCommand(cmd: string, args: string[], opts: { cwd?: string; env?: NodeJS.ProcessEnv } = {}): Promise<{ stdout: string; stderr: string; code: number | null; }> {
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, args, { stdio: ["ignore", "pipe", "pipe"], ...opts });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", d => (stdout += d.toString()));
    child.stderr.on("data", d => (stderr += d.toString()));
    child.on("error", reject);
    child.on("close", code => resolve({ stdout, stderr, code }));
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

async function loadArkitPoses(bucket: StorageBucket, rawPrefix: string, tmpDir: string): Promise<PoseIndex> {
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
  const bestDiff = bestTime !== undefined ? Math.abs(bestTime - targetTime) : Number.POSITIVE_INFINITY;
  const prev = low > 0 ? poses[low - 1] : undefined;
  if (prev && prev.t_device_sec !== undefined) {
    const prevDiff = Math.abs(prev.t_device_sec - targetTime);
    if (prevDiff <= bestDiff) {
      best = prev;
    }
  }
  return best;
}

export const extractFrames = onObjectFinalized({
  region: "us-central1",
  memory: "2GiB",
  timeoutSeconds: 540,
  cpu: 2,
}, async (event) => {
  const bucketName = event.bucket;
  const objectName = event.data?.name || "";
  const contentType = event.data?.contentType || "";

  // Only handle: targets/<scene_id>/raw/walkthrough.mov
  if (!objectName.endsWith("/raw/walkthrough.mov") || !objectName.startsWith("targets/")) {
    logger.info("Skipping object (not a walkthrough.mov under targets/*/raw/)", { objectName, contentType });
    return;
  }

  logger.info("Starting frame extraction", { bucketName, objectName });

  const tmp = tmpdir();
  const localVideo = join(tmp, `video-${Date.now()}.mov`);
  const framesDir = join(tmp, `frames-${Date.now()}`);
  mkdirSync(framesDir, { recursive: true });

  const bucket = storage.bucket(bucketName);
  const file = bucket.file(objectName);
  const rawPrefix = dirname(objectName);

  const poseIndex = await loadArkitPoses(bucket, rawPrefix, tmp);

  // Download video
  await file.download({ destination: localVideo });
  logger.info("Downloaded video to temp", { localVideo });

  // Extract frames using ffmpeg fps=10 and scale longest side to 512 with Lanczos
  // Also include showinfo after fps so pts_time corresponds to output frames
  const outputPattern = join(framesDir, "%06d.jpg");
  const ffmpegArgs = [
    "-hide_banner",
    "-loglevel", "info",
    "-y",
    "-i", localVideo,
    "-vf", "fps=10,scale=512:-2:flags=lanczos,showinfo",
    "-qscale:v", "2",
    "-start_number", "1",
    outputPattern,
  ];

  const env = { ...process.env, FFMPEG_PATH: ffmpegInstaller.path, FFPROBE_PATH: ffprobeInstaller.path };
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

  // Build index.jsonl mapping frame_id -> t_video_sec
  const sortedFiles = readdirSync(framesDir)
    .filter(f => f.toLowerCase().endsWith(".jpg"))
    .sort();

  const indexLines: string[] = [];
  const posesByFrameId = poseIndex.byFrameId;
  const posesByTime = poseIndex.byTime;

  for (let i = 0; i < sortedFiles.length; i++) {
    const frameId = zeroPad(i + 1, 6);
    const t = i < ptsTimes.length ? ptsTimes[i] : (i / 10.0);
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
      const poseFrameId = typeof pose.frame_id === "string" ? pose.frame_id : undefined;
      if (poseFrameId) {
        arkitPose.pose_frame_id = poseFrameId;
        if (poseFrameId !== frameId) {
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
    const contentType = fname.endsWith(".jpg") ? "image/jpeg" : (fname.endsWith(".jsonl") ? "application/json" : undefined);
    uploads.push(bucket.upload(localPath, { destination: dest, metadata: contentType ? { contentType } : undefined }));
  }
  await Promise.all(uploads);
  logger.info("Uploaded frames and index", { framesPrefix, count: sortedFiles.length });
});


