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
import {
  buildPoseIndex,
  chooseKeyframeCandidate,
  evaluateQualityGate,
  findClosestPoseByTime,
  parsePoseRows,
  percentile,
  type PoseRow,
  type PoseIndex,
} from "./bridge.js";

const storage = new Storage();

type StorageBucket = ReturnType<typeof storage.bucket>;

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
  const index = buildPoseIndex(rows);
  logger.info("Loaded ARKit pose entries", { posesObjectName, count: rows.length });
  return index;
}

type CapturePathInfo = {
  mode: "scenes" | "targets";
  sceneId: string;
  captureSourcePath: string;
  captureId: string;
  scenePrefix: string;
  capturePrefix: string;
  rawPrefix: string;
  framesPrefix: string;
  capturesPrefix: string;
  keyframeObjectName: string;
  sceneRequestObjectName: string;
};

function parseCapturePath(objectName: string, generation: string): CapturePathInfo | null {
  const parts = objectName.split("/");
  if (parts.length >= 6 && parts[0] === "scenes" && parts[4] === "raw") {
    const sceneId = parts[1];
    const captureSourcePath = parts[2];
    const captureId = parts[3];
    const scenePrefix = `scenes/${sceneId}`;
    const capturePrefix = `${scenePrefix}/${captureSourcePath}/${captureId}`;
    return {
      mode: "scenes",
      sceneId,
      captureSourcePath,
      captureId,
      scenePrefix,
      capturePrefix,
      rawPrefix: `${capturePrefix}/raw`,
      framesPrefix: `${capturePrefix}/frames`,
      capturesPrefix: `${scenePrefix}/captures/${captureId}`,
      keyframeObjectName: `${scenePrefix}/images/${captureId}_keyframe.jpg`,
      sceneRequestObjectName: `${scenePrefix}/prompts/scene_request.json`,
    };
  }
  if (parts.length >= 4 && parts[0] === "targets" && parts[2] === "raw") {
    const sceneId = parts[1];
    const captureId = `legacy-${generation || Date.now()}`;
    const scenePrefix = `targets/${sceneId}`;
    const capturePrefix = `${scenePrefix}`;
    return {
      mode: "targets",
      sceneId,
      captureSourcePath: "unknown",
      captureId,
      scenePrefix,
      capturePrefix,
      rawPrefix: `${capturePrefix}/raw`,
      framesPrefix: `${capturePrefix}/frames`,
      capturesPrefix: `${scenePrefix}/captures/${captureId}`,
      keyframeObjectName: `${scenePrefix}/images/${captureId}_keyframe.jpg`,
      sceneRequestObjectName: `${scenePrefix}/prompts/scene_request.json`,
    };
  }
  return null;
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitForObjectExists(
  bucket: StorageBucket,
  objectName: string,
  timeoutMs: number,
  intervalMs: number
): Promise<boolean> {
  const started = Date.now();
  while (Date.now() - started <= timeoutMs) {
    try {
      const [exists] = await bucket.file(objectName).exists();
      if (exists) return true;
    } catch (error) {
      logger.warn("Failed checking object existence", { objectName, error });
    }
    await sleep(intervalMs);
  }
  return false;
}

async function loadJsonObject(
  bucket: StorageBucket,
  objectName: string,
  tmpDir: string
): Promise<Record<string, unknown> | null> {
  const localPath = join(tmpDir, `json-${Date.now()}-${basename(objectName)}`);
  try {
    await bucket.file(objectName).download({ destination: localPath });
    const raw = readFileSync(localPath, "utf8");
    const parsed = JSON.parse(raw) as Record<string, unknown>;
    if (typeof parsed !== "object" || parsed === null) return null;
    return parsed;
  } catch (error) {
    logger.warn("Failed to load JSON object", { objectName, error });
    return null;
  }
}

function gsUri(bucketName: string, objectName: string): string {
  return `gs://${bucketName}/${objectName}`;
}

function asFiniteNumber(value: unknown): number | undefined {
  if (typeof value !== "number" || !Number.isFinite(value)) return undefined;
  return value;
}

function asString(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

function validateManifest(manifest: Record<string, unknown> | null): {
  valid: boolean;
  missingRequired: string[];
  warnings: string[];
} {
  if (!manifest) {
    return { valid: false, missingRequired: ["manifest"], warnings: [] };
  }

  const missingRequired: string[] = [];
  const warnings: string[] = [];
  const requiredStringFields = ["scene_id", "video_uri", "device_model", "os_version"];
  const requiredNumberFields = ["fps_source", "width", "height", "capture_start_epoch_ms"];
  const requiredBooleanFields = ["has_lidar"];

  for (const field of requiredStringFields) {
    if (!asString(manifest[field])) {
      missingRequired.push(field);
    }
  }
  for (const field of requiredNumberFields) {
    if (asFiniteNumber(manifest[field]) === undefined) {
      missingRequired.push(field);
    }
  }
  for (const field of requiredBooleanFields) {
    if (typeof manifest[field] !== "boolean") {
      missingRequired.push(field);
    }
  }

  const bridgeFields = ["capture_schema_version", "capture_source", "capture_tier_hint"];
  for (const field of bridgeFields) {
    if (!asString(manifest[field])) {
      warnings.push(`missing_${field}`);
    }
  }

  return {
    valid: missingRequired.length === 0,
    missingRequired,
    warnings,
  };
}

/**
 * extractFrames
 * - Trigger: scenes/<scene>/<source>/<capture_id>/raw/walkthrough.mov (iOS uploader format)
 *   OR: targets/<scene>/raw/walkthrough.mov (legacy format)
 * - Output: <same_prefix>/frames/*.jpg + index.jsonl
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
    const objectGeneration =
      event.data?.generation !== undefined && event.data?.generation !== null
        ? String(event.data.generation)
        : "0";

    if (!objectName.endsWith("/raw/walkthrough.mov")) {
      logger.info("Skipping object (not a walkthrough.mov upload)", { objectName, contentType });
      return;
    }

    const pathInfo = parseCapturePath(objectName, objectGeneration);
    if (!pathInfo) {
      logger.info("Skipping object (unsupported walkthrough.mov path)", { objectName });
      return;
    }

    logger.info("Starting frame extraction", {
      bucketName,
      objectName,
      sceneId: pathInfo.sceneId,
      captureId: pathInfo.captureId,
      mode: pathInfo.mode,
    });

    const bucket = storage.bucket(bucketName);
    const tmp = tmpdir();
    const localVideo = join(tmp, `video-${Date.now()}.mov`);
    const framesDir = join(tmp, `frames-${Date.now()}`);
    mkdirSync(framesDir, { recursive: true });

    const manifestObjectName = `${pathInfo.rawPrefix}/manifest.json`;
    const walkthroughExists = await waitForObjectExists(bucket, objectName, 3000, 1000);
    const manifestExists = await waitForObjectExists(bucket, manifestObjectName, 45000, 3000);
    const manifest = manifestExists ? await loadJsonObject(bucket, manifestObjectName, tmp) : null;
    const manifestValidation = validateManifest(manifest);

    const poseIndex = await loadArkitPoses(bucket, pathInfo.rawPrefix, tmp);
    const file = bucket.file(objectName);

    await file.download({ destination: localVideo });
    logger.info("Downloaded video to temp", { localVideo });

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

    const sortedFiles = readdirSync(framesDir)
      .filter((f) => f.toLowerCase().endsWith(".jpg"))
      .sort();

    const indexEntries: Record<string, unknown>[] = [];
    const posesByFrameId = poseIndex.byFrameId;
    const posesByTime = poseIndex.byTime;
    let matchedPoseCount = 0;
    const poseDeltaSecValues: number[] = [];

    for (let i = 0; i < sortedFiles.length; i++) {
      const frameId = zeroPad(i + 1, 6);
      const t = i < ptsTimes.length ? ptsTimes[i] : i / 5.0;
      const tVideoSec = Number(t.toFixed(6));

      const entry: Record<string, unknown> = {
        frame_id: frameId,
        t_video_sec: tVideoSec,
      };

      let poseMatchType: PoseMatchType | undefined;
      let pose: PoseRow | undefined = posesByFrameId.get(frameId);
      if (pose) {
        poseMatchType = "frame_id";
      } else if (posesByTime.length > 0) {
        pose = findClosestPoseByTime(posesByTime, tVideoSec);
        if (pose) {
          poseMatchType = "time";
        }
      }

      if (pose) {
        matchedPoseCount += 1;
        const arkitPose: Record<string, unknown> = {};

        if (typeof pose.frame_id === "string") {
          arkitPose.pose_frame_id = pose.frame_id;
          if (pose.frame_id !== frameId) {
            arkitPose.frame_id_mismatch = true;
          }
        }

        if (typeof pose.pose_schema_version === "string") {
          arkitPose.pose_schema_version = pose.pose_schema_version;
        }

        if (typeof pose.source_schema === "string") {
          arkitPose.source_schema = pose.source_schema;
        }

        if (Array.isArray(pose.T_world_camera)) {
          arkitPose.T_world_camera = pose.T_world_camera;
        }

        if (typeof pose.t_device_sec === "number" && Number.isFinite(pose.t_device_sec)) {
          const tDevice = Number(pose.t_device_sec.toFixed(6));
          arkitPose.t_device_sec = tDevice;
          const delta = Math.abs(tDevice - tVideoSec);
          const roundedDelta = Number(delta.toFixed(6));
          arkitPose.delta_sec = roundedDelta;
          poseDeltaSecValues.push(roundedDelta);
        }

        if (poseMatchType) {
          arkitPose.match_type = poseMatchType;
        }

        if (Object.keys(arkitPose).length > 0) {
          entry.arkit_pose = arkitPose;
        }
      }

      indexEntries.push(entry);
    }

    const indexPath = join(framesDir, "index.jsonl");
    writeFileSync(
      indexPath,
      indexEntries.map((row) => JSON.stringify(row)).join("\n"),
      { encoding: "utf8" }
    );

    const uploads: Promise<unknown>[] = [];
    for (const fname of readdirSync(framesDir)) {
      const localPath = join(framesDir, fname);
      const dest = `${pathInfo.framesPrefix}/${fname}`;
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

    const keyframeCandidate = chooseKeyframeCandidate(sortedFiles, (fileName) =>
      statSync(join(framesDir, fileName)).size
    );
    let keyframeUri: string | null = null;
    if (keyframeCandidate) {
      await bucket.upload(join(framesDir, keyframeCandidate.fileName), {
        destination: pathInfo.keyframeObjectName,
        metadata: { contentType: "image/jpeg" },
      });
      keyframeUri = gsUri(bucketName, pathInfo.keyframeObjectName);
    }

    const captureSourceRaw =
      asString(manifest?.capture_source) ??
      (pathInfo.captureSourcePath === "iphone" || pathInfo.captureSourcePath === "glasses"
        ? pathInfo.captureSourcePath
        : "unknown");
    const captureSource: "iphone" | "glasses" | "unknown" =
      captureSourceRaw === "iphone"
        ? "iphone"
        : captureSourceRaw === "glasses"
        ? "glasses"
        : "unknown";
    const poseMatchRate =
      sortedFiles.length > 0 ? Number((matchedPoseCount / sortedFiles.length).toFixed(6)) : 0;
    const p95PoseDeltaRaw = percentile(poseDeltaSecValues, 95);
    const p95PoseDeltaSec =
      p95PoseDeltaRaw === null ? null : Number(p95PoseDeltaRaw.toFixed(6));
    const qualityGate = evaluateQualityGate({
      captureSource,
      manifestPresent: manifestExists,
      manifestValid: manifestValidation.valid,
      requiredFiles: {
        walkthrough: walkthroughExists,
        manifest: manifestExists,
      },
      frameCount: sortedFiles.length,
      poseMatchRate,
      p95PoseDeltaSec,
    });

    const finalReasons = [...qualityGate.reasons];
    const finalWarnings = [...manifestValidation.warnings, ...qualityGate.warnings];
    let finalStatus = qualityGate.status;
    let autoTriggered = false;
    let triggerError: string | null = null;

    const rawPrefixUri = gsUri(bucketName, pathInfo.rawPrefix);
    const framesIndexUri = gsUri(bucketName, `${pathInfo.framesPrefix}/index.jsonl`);
    const descriptorUri = gsUri(bucketName, `${pathInfo.capturesPrefix}/capture_descriptor.json`);
    const qaReportUri = gsUri(bucketName, `${pathInfo.capturesPrefix}/qa_report.json`);

    const captureDescriptor: Record<string, unknown> = {
      schema_version: "v1",
      scene_id: pathInfo.sceneId,
      capture_id: pathInfo.captureId,
      capture_source: captureSource,
      capture_tier: qualityGate.captureTier,
      raw_prefix_uri: rawPrefixUri,
      frames_index_uri: framesIndexUri,
      keyframe_uri: keyframeUri,
      nurec_mode: qualityGate.nurecMode,
      swap_focus: ["kitchen", "warehouse"],
      intended_space_type: asString(manifest?.intended_space_type) ?? "unknown",
      quality: {
        pose_match_rate: poseMatchRate,
        p95_pose_delta_sec: p95PoseDeltaSec,
        frame_count: sortedFiles.length,
      },
      capture_bundle: {
        arkit_poses_uri: gsUri(bucketName, `${pathInfo.rawPrefix}/arkit/poses.jsonl`),
        arkit_intrinsics_uri: gsUri(bucketName, `${pathInfo.rawPrefix}/arkit/intrinsics.json`),
        arkit_depth_prefix_uri: gsUri(bucketName, `${pathInfo.rawPrefix}/arkit/depth`),
        arkit_confidence_prefix_uri: gsUri(bucketName, `${pathInfo.rawPrefix}/arkit/confidence`),
      },
      generated_at: new Date().toISOString(),
    };

    if (finalStatus === "passed" && pathInfo.mode === "scenes") {
      if (!keyframeUri) {
        finalStatus = "blocked";
        finalReasons.push("missing_keyframe");
      } else {
        const sceneRequestPayload = {
          schema_version: "v1",
          scene_id: pathInfo.sceneId,
          source_mode: "image",
          quality_tier: "standard",
          image: {
            gcs_uri: keyframeUri,
            generation: objectGeneration,
          },
          constraints: {
            capture_bundle: {
              scene_id: pathInfo.sceneId,
              capture_id: pathInfo.captureId,
              capture_source: captureSource,
              capture_tier: qualityGate.captureTier,
              nurec_mode: qualityGate.nurecMode,
              raw_prefix_uri: rawPrefixUri,
              frames_index_uri: framesIndexUri,
              keyframe_uri: keyframeUri,
              descriptor_uri: descriptorUri,
              qa_report_uri: qaReportUri,
              swap_focus: ["kitchen", "warehouse"],
            },
          },
          provider_policy: "openai_primary",
          fallback: {
            allow_image_fallback: false,
          },
        };
        try {
          await bucket
            .file(pathInfo.sceneRequestObjectName)
            .save(JSON.stringify(sceneRequestPayload, null, 2), {
              contentType: "application/json",
            });
          autoTriggered = true;
        } catch (error) {
          finalStatus = "blocked";
          finalReasons.push("scene_request_write_failed");
          triggerError = error instanceof Error ? error.message : "unknown_error";
        }
      }
    } else if (pathInfo.mode !== "scenes") {
      finalWarnings.push("legacy_targets_path_no_source_orchestrator_trigger");
    }

    const qaReport: Record<string, unknown> = {
      schema_version: "v1",
      scene_id: pathInfo.sceneId,
      capture_id: pathInfo.captureId,
      capture_source: captureSource,
      capture_tier_initial:
        asString(manifest?.capture_tier_hint) ??
        (captureSource === "iphone" ? "tier1_iphone" : "tier2_glasses"),
      capture_tier_final: qualityGate.captureTier,
      nurec_mode: qualityGate.nurecMode,
      status: finalStatus,
      required_files: {
        walkthrough: walkthroughExists,
        manifest: manifestExists,
      },
      manifest_validation: {
        valid: manifestValidation.valid,
        missing_required: manifestValidation.missingRequired,
        warnings: manifestValidation.warnings,
      },
      quality: {
        frame_count: sortedFiles.length,
        pose_matches: matchedPoseCount,
        pose_match_rate: poseMatchRate,
        p95_pose_delta_sec: p95PoseDeltaSec,
      },
      reasons: finalReasons,
      warnings: finalWarnings,
      auto_triggered: autoTriggered,
      trigger_error: triggerError,
      generated_at: new Date().toISOString(),
    };

    captureDescriptor.qa_status = finalStatus;
    captureDescriptor.qa_report_uri = qaReportUri;
    captureDescriptor.auto_triggered = autoTriggered;

    await bucket
      .file(`${pathInfo.capturesPrefix}/capture_descriptor.json`)
      .save(JSON.stringify(captureDescriptor, null, 2), {
        contentType: "application/json",
      });
    await bucket
      .file(`${pathInfo.capturesPrefix}/qa_report.json`)
      .save(JSON.stringify(qaReport, null, 2), {
        contentType: "application/json",
      });

    logger.info("Uploaded frames, descriptor, and QA report", {
      framesPrefix: pathInfo.framesPrefix,
      frameCount: sortedFiles.length,
      captureId: pathInfo.captureId,
      sceneId: pathInfo.sceneId,
      qaStatus: finalStatus,
      autoTriggered,
    });
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
 * - Trigger: scenes/<scene>/<source>/<capture_id>/raw/roomplan.zip (iOS uploader format)
 *   OR: targets/<scene>/raw/roomplan.zip (legacy format)
 * - Looks for RoomPlanParametric.usdz inside the zip
 * - Writes RoomPlanArchitectureOnly.usdz with Object_grp removed
 * - Re-zips and uploads to <same_prefix>/processed/roomplan.zip
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

    // Handle both path formats:
    // - scenes/<scene_id>/<source>/<capture_id>/raw/roomplan.zip (iOS uploader)
    // - targets/<scene_id>/raw/roomplan.zip (legacy)
    const isScenesPath = objectName.startsWith("scenes/") && objectName.endsWith("/raw/roomplan.zip");
    const isTargetsPath = objectName.startsWith("targets/") && objectName.endsWith("/raw/roomplan.zip");

    if (!isScenesPath && !isTargetsPath) {
      logger.info("Skipping object (not a roomplan.zip under scenes/*/.../raw/ or targets/*/raw/)", {
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

    // Output to processed/ folder next to raw/
    // scenes/<scene>/<source>/<capture_id>/raw/roomplan.zip -> scenes/<scene>/<source>/<capture_id>/processed/roomplan.zip
    // targets/<scene>/raw/roomplan.zip -> targets/<scene>/processed/roomplan.zip
    const capturePrefix = dirname(dirname(objectName)); // Everything before /raw/
    const processedObjectName = `${capturePrefix}/processed/roomplan.zip`;

    await bucket.upload(processedZipPath, {
      destination: processedObjectName,
      metadata: { contentType: "application/zip" },
    });

    logger.info("Uploaded processed RoomPlan zip with architecture-only USDZ", {
      processedObjectName,
    });
  }
);
