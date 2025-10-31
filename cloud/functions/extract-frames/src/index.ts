import { onObjectFinalized } from "firebase-functions/v2/storage";
import * as logger from "firebase-functions/logger";
import { Storage } from "@google-cloud/storage";
import { tmpdir } from "os";
import { join, dirname } from "path";
import { mkdirSync, writeFileSync, readdirSync, createReadStream, existsSync } from "fs";
import { spawn } from "child_process";
import ffmpegInstaller from "@ffmpeg-installer/ffmpeg";
import ffprobeInstaller from "@ffprobe-installer/ffprobe";

const storage = new Storage();

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
  for (let i = 0; i < sortedFiles.length; i++) {
    const frameId = zeroPad(i + 1, 6);
    const t = i < ptsTimes.length ? ptsTimes[i] : (i / 10.0);
    indexLines.push(JSON.stringify({ frame_id: frameId, t_video_sec: Number(t.toFixed(6)) }));
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


