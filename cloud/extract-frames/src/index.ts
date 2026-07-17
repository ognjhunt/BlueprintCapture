import { onObjectFinalized } from "firebase-functions/v2/storage";
import * as logger from "firebase-functions/logger";
import { Storage } from "@google-cloud/storage";
import { PubSub } from "@google-cloud/pubsub";
import { tmpdir } from "os";
import { join, basename } from "path";
import { mkdirSync, writeFileSync, readdirSync, statSync, readFileSync } from "fs";
import { spawn } from "child_process";
import ffmpegInstaller from "@ffmpeg-installer/ffmpeg";
import ffprobeInstaller from "@ffprobe-installer/ffprobe";
import {
  buildCaptureBundleReferences,
  buildPoseIndex,
  chooseKeyframeCandidate,
  evaluateClaimedArtifacts,
  evaluateQualityGate,
  findClosestPoseByTime,
  parsePoseRows,
  percentile,
  type ArtifactAvailability,
  type PoseRow,
  type PoseIndex,
} from "./bridge.js";
import {
  captureObjectKind,
  parseCapturePath,
  resolveWalkthroughObjectName,
  type CapturePathInfo,
} from "./capture-paths.js";
import { isDeterministicJsonlError, parseStrictJsonLines } from "./jsonl.js";

export {
  captureObjectKind,
  parseCapturePath,
  resolveWalkthroughObjectName,
} from "./capture-paths.js";
export type { CapturePathInfo } from "./capture-paths.js";

const storage = new Storage();
const pubsub = new PubSub();

const PIPELINE_HANDOFF_TOPIC =
  process.env.BLUEPRINT_CAPTURE_PIPELINE_TOPIC ?? "blueprint-capture-pipeline-handoff";
const ALLOW_REVIEW_ONLY_HANDOFF_WITHOUT_UPSTREAM_IDS =
  process.env.BLUEPRINT_ALLOW_REVIEW_ONLY_HANDOFF_WITHOUT_UPSTREAM_IDS === "true";
// Cloud Functions v2 runs on Cloud Run where /tmp is an in-memory tmpfs that
// counts against the instance memory limit. The inline ceiling must leave room
// for the downloaded video + extracted JPEG frames + node heap inside the
// function's memory setting (4GiB): 1GB video + ~1.5GB frames + heap fits with
// margin. Larger captures are BLOCKED by the size gate with a documented
// artifact trail (required_action: segmented/Cloud Run ingest) instead of
// OOM-crash-looping mid-extraction; the segmented path must pick them up.
export const DEFAULT_MAX_INLINE_EXTRACT_FRAMES_VIDEO_BYTES = 1_000_000_000;

type StorageBucket = ReturnType<typeof storage.bucket>;

type PoseMatchType = "frame_id" | "time";
type InlineFrameExtractionSizeGate = {
  inlineAllowed: boolean;
  blockCode: string | null;
  reasons: string[];
  rawVideoSizeBytes: number | null;
  maxInlineVideoBytes: number;
};

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
    const content = readFileSync(localPosesPath, { encoding: "utf8" });
    const rows = parsePoseRows(content);
    const index = buildPoseIndex(rows);
    logger.info("Loaded ARKit pose entries", { posesObjectName, count: rows.length });
    return index;
  } catch (error) {
    // A malformed line is deterministic — retrying the trigger can never
    // succeed, so degrade to "poses unavailable" instead of crash-looping the
    // whole capture. Transient download errors still rethrow so the
    // at-least-once trigger retries them.
    if (isDeterministicJsonlError(error)) {
      logger.error("ARKit pose log is malformed; continuing without poses", {
        posesObjectName,
        error,
      });
      return { byFrameId: new Map(), byTime: [] };
    }
    logger.error("Failed to load ARKit pose log", { posesObjectName, error });
    throw error;
  }
}

async function loadArkitFrameQuality(
  bucket: StorageBucket,
  rawPrefix: string,
  tmpDir: string
): Promise<Map<string, Record<string, unknown>>> {
  const frameLogObjectName = `${rawPrefix}/arkit/frames.jsonl`;
  const frameLogFile = bucket.file(frameLogObjectName);
  let exists = false;
  try {
    [exists] = await frameLogFile.exists();
  } catch (error) {
    logger.warn("Failed to check existence of ARKit frame log", { frameLogObjectName, error });
    return new Map();
  }
  if (!exists) {
    return new Map();
  }

  const localFrameLogPath = join(tmpDir, `arkit-frames-${Date.now()}.jsonl`);
  try {
    await frameLogFile.download({ destination: localFrameLogPath });
    const raw = readFileSync(localFrameLogPath, "utf8");
    const rows = parseStrictJsonLines(raw, "arkit/frames.jsonl");
    const byFrameId = new Map<string, Record<string, unknown>>();
    for (const row of rows) {
      const frameId = asString(row.frame_id) ?? asString(row.frameId);
      if (frameId) {
        byFrameId.set(frameId, row);
      }
    }
    return byFrameId;
  } catch (error) {
    if (isDeterministicJsonlError(error)) {
      logger.error("ARKit frame log is malformed; continuing without frame quality", {
        frameLogObjectName,
        error,
      });
      return new Map();
    }
    logger.error("Failed to load ARKit frame log", { frameLogObjectName, error });
    throw error;
  }
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

export function mergeManifestWithSidecars(
  manifest: Record<string, unknown> | null,
  sidecars: {
    siteIdentity?: Record<string, unknown> | null;
    captureTopology?: Record<string, unknown> | null;
    captureMode?: Record<string, unknown> | null;
    routeAnchors?: Record<string, unknown> | null;
    checkpointEvents?: Record<string, unknown> | null;
    relocalizationEvents?: Record<string, unknown> | null;
  }
): Record<string, unknown> | null {
  const base = asRecord(manifest) || {};
  return {
    ...base,
    site_identity: asRecord(base.site_identity) || sidecars.siteIdentity || null,
    capture_topology: asRecord(base.capture_topology) || sidecars.captureTopology || null,
    capture_mode: asRecord(base.capture_mode) || sidecars.captureMode || null,
    route_anchors: asRecord(base.route_anchors) || sidecars.routeAnchors || null,
    checkpoint_events: asRecord(base.checkpoint_events) || sidecars.checkpointEvents || null,
    relocalization_events:
      asRecord(base.relocalization_events) || sidecars.relocalizationEvents || null,
  };
}

async function prefixHasObjects(bucket: StorageBucket, prefix: string): Promise<boolean> {
  try {
    const [files] = await bucket.getFiles({ prefix, maxResults: 1 });
    return files.some((file) => file.name !== prefix && !file.name.endsWith("/"));
  } catch (error) {
    logger.warn("Failed to inspect prefix objects", { prefix, error });
    return false;
  }
}

async function fileHasContent(bucket: StorageBucket, objectName: string): Promise<boolean> {
  try {
    const [metadata] = await bucket.file(objectName).getMetadata();
    const size = Number(metadata.size ?? 0);
    return Number.isFinite(size) && size > 0;
  } catch (error) {
    logger.warn("Failed to inspect file content", { objectName, error });
    return false;
  }
}

async function fileExists(bucket: StorageBucket, objectName: string): Promise<boolean> {
  try {
    const [exists] = await bucket.file(objectName).exists();
    return exists;
  } catch (error) {
    logger.warn("Failed to inspect file existence", { objectName, error });
    return false;
  }
}

function isValidIntrinsicsPayload(value: Record<string, unknown> | null): boolean {
  const fx = asFiniteNumber(value?.fx);
  const fy = asFiniteNumber(value?.fy);
  const cx = asFiniteNumber(value?.cx);
  const cy = asFiniteNumber(value?.cy);
  const width = asFiniteNumber(value?.width);
  const height = asFiniteNumber(value?.height);
  return (
    fx !== undefined &&
    fx > 0 &&
    fy !== undefined &&
    fy > 0 &&
    cx !== undefined &&
    cy !== undefined &&
    width !== undefined &&
    width > 0 &&
    height !== undefined &&
    height > 0
  );
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

function asRecord(value: unknown): Record<string, unknown> | undefined {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return undefined;
  }
  return value as Record<string, unknown>;
}

export function maxInlineExtractFramesVideoBytes(): number {
  const raw = process.env.BLUEPRINT_EXTRACT_FRAMES_MAX_INLINE_VIDEO_BYTES;
  if (!raw) return DEFAULT_MAX_INLINE_EXTRACT_FRAMES_VIDEO_BYTES;
  const parsed = Number(raw);
  if (!Number.isSafeInteger(parsed) || parsed <= 0) {
    return DEFAULT_MAX_INLINE_EXTRACT_FRAMES_VIDEO_BYTES;
  }
  return parsed;
}

export function parseStorageObjectSize(value: unknown): number | null {
  if (typeof value === "number") {
    return Number.isFinite(value) && value >= 0 ? value : null;
  }
  if (typeof value === "string") {
    const trimmed = value.trim();
    if (!/^[0-9]+$/.test(trimmed)) return null;
    const parsed = Number(trimmed);
    return Number.isSafeInteger(parsed) && parsed >= 0 ? parsed : null;
  }
  return null;
}

export function inlineFrameExtractionSizeGate(
  rawVideoSizeBytes: number | null,
  maxInlineVideoBytes: number = maxInlineExtractFramesVideoBytes()
): InlineFrameExtractionSizeGate {
  if (!Number.isSafeInteger(maxInlineVideoBytes) || maxInlineVideoBytes <= 0) {
    maxInlineVideoBytes = DEFAULT_MAX_INLINE_EXTRACT_FRAMES_VIDEO_BYTES;
  }
  if (rawVideoSizeBytes === null) {
    return {
      inlineAllowed: false,
      blockCode: "blocked_raw_walkthrough_video_size_unavailable",
      reasons: ["raw_walkthrough_video_size_unavailable"],
      rawVideoSizeBytes: null,
      maxInlineVideoBytes,
    };
  }
  if (rawVideoSizeBytes > maxInlineVideoBytes) {
    return {
      inlineAllowed: false,
      blockCode: "blocked_large_video_requires_segmented_ingest",
      reasons: ["raw_walkthrough_video_exceeds_extract_frames_inline_limit"],
      rawVideoSizeBytes,
      maxInlineVideoBytes,
    };
  }
  return {
    inlineAllowed: true,
    blockCode: null,
    reasons: [],
    rawVideoSizeBytes,
    maxInlineVideoBytes,
  };
}

export function buildLargeVideoIngestBlockedArtifacts(input: {
  bucketName: string;
  pathInfo: CapturePathInfo;
  objectName: string;
  objectKind: string;
  walkthroughObjectName: string;
  manifestExists: boolean;
  walkthroughExists: boolean;
  manifestValidation: {
    valid: boolean;
    missingRequired: string[];
    warnings: string[];
  };
  sizeGate: InlineFrameExtractionSizeGate;
  generatedAt?: string;
}): {
  blockReport: Record<string, unknown>;
  qaReport: Record<string, unknown>;
  pipelineStatusEvent: Record<string, unknown>;
} {
  const generatedAt = input.generatedAt ?? new Date().toISOString();
  const blockReportUri = gsUri(
    input.bucketName,
    `${input.pathInfo.capturesPrefix}/large_video_ingest_blocked.json`
  );
  const qaReportUri = gsUri(input.bucketName, `${input.pathInfo.capturesPrefix}/qa_report.json`);
  const rawVideoUri = gsUri(input.bucketName, input.walkthroughObjectName);
  const blockCode = input.sizeGate.blockCode ?? "blocked_large_video_requires_segmented_ingest";
  const base = {
    scene_id: input.pathInfo.sceneId,
    capture_id: input.pathInfo.captureId,
    raw_prefix: input.pathInfo.rawPrefix,
    raw_prefix_uri: gsUri(input.bucketName, input.pathInfo.rawPrefix),
    trigger_object: input.objectName,
    trigger_kind: input.objectKind,
    raw_video_uri: rawVideoUri,
    raw_video_object: input.walkthroughObjectName,
    raw_video_size_bytes: input.sizeGate.rawVideoSizeBytes,
    max_inline_video_bytes: input.sizeGate.maxInlineVideoBytes,
    block_code: blockCode,
    reasons: input.sizeGate.reasons,
    generated_at: generatedAt,
  };
  const blockReport = {
    schema_version: "extract_frames_large_video_block.v1",
    status: "blocked",
    stage: "extract_frames.pre_download_size_gate",
    ...base,
    inline_frame_extraction_attempted: false,
    ffmpeg_attempted: false,
    required_action: "route_capture_to_segmented_or_cloud_run_video_ingest",
    recommended_next_stage: "large_video_cloud_run_ingest",
    qa_report_uri: qaReportUri,
    claim_boundary:
      "blocked_report_only_no_frames_descriptor_pipeline_handoff_or_policy_success_were_generated",
  };
  const qaReport = {
    schema_version: "v1",
    status: "blocked",
    ...base,
    block_report_uri: blockReportUri,
    required_files: {
      walkthrough: input.walkthroughExists,
      manifest: input.manifestExists,
    },
    manifest_validation: {
      valid: input.manifestValidation.valid,
      missing_required: input.manifestValidation.missingRequired,
      warnings: input.manifestValidation.warnings,
    },
    quality: {
      frame_count: 0,
      pose_matches: 0,
      pose_match_rate: 0,
      p95_pose_delta_sec: null,
    },
    warnings: [
      ...input.manifestValidation.warnings,
      "extract_frames_inline_video_guard_blocked_download",
    ],
    recommended_next_stage: "large_video_cloud_run_ingest",
    claim_boundary:
      "qa_report_describes_pre_download_block_only_and_does_not_validate_task_or_scene_success",
  };
  const pipelineStatusEvent = {
    event_type: "capture.raw_video_ingest_blocked.v1",
    qa_status: "blocked",
    block_report_uri: blockReportUri,
    qa_report_uri: qaReportUri,
    ...base,
  };
  return { blockReport, qaReport, pipelineStatusEvent };
}

function asRecordArray(value: unknown): Record<string, unknown>[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((item) => asRecord(item))
    .filter((item): item is Record<string, unknown> => item !== undefined)
    .map((item) => ({ ...item }));
}

function asStringArray(value: unknown): string[] | undefined {
  if (!Array.isArray(value)) return undefined;
  const parsed = value
    .filter((item): item is string => typeof item === "string")
    .map((item) => item.trim())
    .filter((item) => item.length > 0);
  return parsed.length > 0 ? parsed : [];
}

const UPSTREAM_PLACEHOLDER_PREFIXES = [
  "placeholder",
  "replace_me",
  "dummy",
  "sample",
  "example",
  "mock",
];

function invalidUpstreamIdBlockers(
  fieldName: string,
  value: string | null,
  pathInfo: CapturePathInfo
): string[] {
  if (!value) return [];
  const normalized = value.toLowerCase();
  const blockers: string[] = [];
  if (
    UPSTREAM_PLACEHOLDER_PREFIXES.some(
      (prefix) =>
        normalized === prefix ||
        normalized.startsWith(`${prefix}-`) ||
        normalized.startsWith(`${prefix}_`)
    )
  ) {
    blockers.push(`invalid_${fieldName}_placeholder`);
  }
  if (value === pathInfo.captureId) {
    blockers.push(`invalid_${fieldName}_matches_capture_id`);
  }
  return blockers;
}

function normalizeCaptureSource(value: string | undefined): "iphone" | "android" | "glasses" | "unknown" {
  const normalized = (value ?? "").trim().toLowerCase();
  if (normalized === "iphone") return "iphone";
  if (normalized === "android" || normalized === "android_phone") return "android";
  if (
    normalized === "glasses" ||
    normalized === "meta_glasses" ||
    normalized === "metaglasses" ||
    normalized === "rayban_meta" ||
    normalized === "ray-ban_meta"
  ) {
    return "glasses";
  }
  return "unknown";
}

function hasStringArray(value: unknown): boolean {
  return Array.isArray(value) && value.every((item) => typeof item === "string");
}

export function deriveRequestedRouting(manifest: Record<string, unknown> | null): {
  requestedOutputs: string[];
  requestedLanes: string[];
  previewSimulationRequested: boolean;
  robotEvalDatasetRequested: boolean;
  robotEvalPublicationGateRequired: boolean;
} {
  const requestedOutputs = asStringArray(manifest?.requested_outputs) ?? [];
  const requestedLanes = new Set<string>();

  for (const output of requestedOutputs) {
    switch (output) {
      case "qualification":
        requestedLanes.add("qualification");
        break;
      case "review_intake":
        requestedLanes.add("qualification");
        requestedLanes.add("review_intake");
        break;
      case "scene_memory":
        requestedLanes.add("scene_memory");
        break;
      case "preview_simulation":
        requestedLanes.add("scene_memory");
        requestedLanes.add("preview_simulation");
        break;
      case "robot_eval_dataset":
        requestedLanes.add("evaluation_prep");
        requestedLanes.add("robot_eval_dataset");
        break;
      case "task_evaluation_run":
        requestedLanes.add("evaluation_prep");
        requestedLanes.add("robot_eval_dataset");
        requestedLanes.add("task_evaluation_run");
        break;
      // Remaining canonical client outputs (see iOS CaptureRequestedOutputs)
      // pass through as their own lanes so the pipeline contract is unchanged.
      case "deeper_evaluation":
      case "scaniverse_assisted_capture":
        requestedLanes.add(output);
        break;
      default:
        // Non-canonical client-supplied outputs must not become downstream
        // lane labels; keep them in requestedOutputs (recorded truth) but do
        // not route on them.
        break;
    }
  }

  if (requestedLanes.size === 0) {
    requestedLanes.add("qualification");
    requestedLanes.add("scene_memory");
  }

  return {
    requestedOutputs,
    requestedLanes: Array.from(requestedLanes),
    previewSimulationRequested: requestedOutputs.includes("preview_simulation"),
    robotEvalDatasetRequested:
      requestedOutputs.includes("robot_eval_dataset") ||
      requestedOutputs.includes("task_evaluation_run"),
    robotEvalPublicationGateRequired:
      requestedOutputs.includes("robot_eval_dataset") ||
      requestedOutputs.includes("task_evaluation_run"),
  };
}

export function buildWorldlabsPreviewFields(
  bucketName: string,
  pathInfo: CapturePathInfo,
  previewSimulationRequested: boolean,
  videoObjectName: string = `${pathInfo.rawPrefix}/walkthrough.mov`
): Record<string, unknown> {
  return {
    preview_simulation_requested: previewSimulationRequested,
    worldlabs_request_manifest_uri: previewSimulationRequested
      ? gsUri(bucketName, `${pathInfo.capturesPrefix}/worldlabs/request_manifest.json`)
      : null,
    worldlabs_input_manifest_uri: previewSimulationRequested
      ? gsUri(bucketName, `${pathInfo.capturesPrefix}/worldlabs/input_manifest.json`)
      : null,
    worldlabs_input_video_uri: previewSimulationRequested
      ? gsUri(bucketName, videoObjectName)
      : null,
  };
}

export function buildRawCaptureLineageFields(
  bucketName: string,
  pathInfo: CapturePathInfo,
  manifest: Record<string, unknown> | null,
  captureSource: "iphone" | "android" | "glasses" | "unknown",
  walkthroughObjectName: string
): Record<string, unknown> {
  const sourceDeviceRaw =
    asString(manifest?.source_device) ??
    asString(manifest?.device_source) ??
    asString(manifest?.capture_source);
  const sourceDevice =
    normalizeCaptureSource(sourceDeviceRaw) === "glasses" && sourceDeviceRaw?.toLowerCase().includes("meta")
      ? "meta_glasses"
      : sourceDeviceRaw ?? (captureSource === "glasses" ? "non_arkit_video" : captureSource);
  const captureModality =
    asString(manifest?.capture_modality) ??
    asString(manifest?.capture_profile_id) ??
    (captureSource === "glasses" ? "glasses_video_only" : null);
  const frameTimestampsObject =
    asString(manifest?.frame_timestamps_object) ??
    (captureSource === "glasses" ? `${pathInfo.rawPrefix}/glasses/frame_timestamps.jsonl` : null);
  const streamMetadataObject =
    asString(manifest?.stream_metadata_object) ??
    (captureSource === "glasses" ? `${pathInfo.rawPrefix}/glasses/stream_metadata.json` : null);
  const rawVideoUri = gsUri(bucketName, walkthroughObjectName);
  return {
    source_device: sourceDevice,
    capture_modality: captureModality,
    raw_video_uri: rawVideoUri,
    privacy_lineage: asRecord(manifest?.privacy_lineage) ?? null,
    provenance_lineage: asRecord(manifest?.provenance_lineage) ?? null,
    media_metadata: {
      source_device: sourceDevice,
      original_video_uri: rawVideoUri,
      original_video_object: walkthroughObjectName,
      frame_timestamps_uri: frameTimestampsObject ? gsUri(bucketName, frameTimestampsObject) : null,
      stream_metadata_uri: streamMetadataObject ? gsUri(bucketName, streamMetadataObject) : null,
      width: asFiniteNumber(manifest?.width) ?? null,
      height: asFiniteNumber(manifest?.height) ?? null,
      fps_source: asFiniteNumber(manifest?.fps_source) ?? null,
      device_model: asString(manifest?.device_model) ?? null,
      device_model_marketing: asString(manifest?.device_model_marketing) ?? null,
      capture_start_epoch_ms: asFiniteNumber(manifest?.capture_start_epoch_ms) ?? null,
    },
  };
}

export function buildTaskSiteContext(manifest: Record<string, unknown> | null): Record<string, unknown> {
  const captureProfile = asRecord(manifest?.capture_profile);
  const environmentVariability = asRecord(manifest?.environment_variability);
  const routeAnchors = asRecord(manifest?.route_anchors);
  return {
    workflow_name: asString(manifest?.task_text_hint) ?? null,
    task_steps: asStringArray(manifest?.task_steps) ?? [],
    target_kpi: asString(manifest?.target_kpi) ?? null,
    zone: asString(manifest?.zone) ?? null,
    shift: asString(manifest?.shift) ?? null,
    owner: asString(manifest?.owner) ?? null,
    facility_template: asString(captureProfile?.facility_template) ?? null,
    required_coverage_areas: asStringArray(captureProfile?.required_coverage_areas) ?? [],
    benchmark_stations: asStringArray(captureProfile?.benchmark_stations) ?? [],
    adjacent_systems: asStringArray(captureProfile?.adjacent_systems) ?? [],
    privacy_security_limits: asStringArray(captureProfile?.privacy_security_limits) ?? [],
    known_blockers: asStringArray(captureProfile?.known_blockers) ?? [],
    non_routine_modes: asStringArray(captureProfile?.non_routine_modes) ?? [],
    people_traffic_notes: asStringArray(captureProfile?.people_traffic_notes) ?? [],
    capture_restrictions: asStringArray(captureProfile?.capture_restrictions) ?? [],
    lighting_windows: asStringArray(environmentVariability?.lighting_windows) ?? [],
    shift_traffic_windows: asStringArray(environmentVariability?.shift_traffic_windows) ?? [],
    movable_obstacles: asStringArray(environmentVariability?.movable_obstacles) ?? [],
    floor_condition_notes: asStringArray(environmentVariability?.floor_condition_notes) ?? [],
    reflective_surface_notes: asStringArray(environmentVariability?.reflective_surface_notes) ?? [],
    access_rules: asStringArray(environmentVariability?.access_rules) ?? [],
    robot_eval_task_anchor_candidates: [
      ...asRecordArray(manifest?.robot_eval_task_anchors),
      ...asRecordArray(manifest?.task_anchor_candidates),
    ],
    robot_eval_scene_asset_hints: [
      ...asRecordArray(manifest?.robot_eval_scene_assets),
      ...asRecordArray(manifest?.scene_asset_hints),
    ],
    robot_eval_robot_profile_candidates: [
      ...asRecordArray(manifest?.robot_eval_robot_profiles),
      ...asRecordArray(manifest?.robot_profiles),
    ],
    robot_eval_route_anchor_candidates: asRecordArray(routeAnchors?.route_anchors),
  };
}

export function buildRobotEvalHandoffFields(input: {
  routing: {
    robotEvalDatasetRequested?: boolean;
    robotEvalPublicationGateRequired?: boolean;
  };
  taskSiteContext: Record<string, unknown>;
  identity: Record<string, unknown>;
}): Record<string, unknown> {
  const requested = input.routing.robotEvalDatasetRequested === true;
  const targetKpi = asString(input.taskSiteContext.target_kpi) ?? null;
  const zone = asString(input.taskSiteContext.zone) ?? null;
  const hostedReviewBlockers = asStringArray(input.identity.hosted_review_blockers) ?? [];
  const taskAnchorCandidates = asRecordArray(
    input.taskSiteContext.robot_eval_task_anchor_candidates
  );
  const sceneAssetHints = asRecordArray(input.taskSiteContext.robot_eval_scene_asset_hints);
  const robotProfileCandidates = asRecordArray(
    input.taskSiteContext.robot_eval_robot_profile_candidates
  );
  const routeAnchorCandidates = asRecordArray(
    input.taskSiteContext.robot_eval_route_anchor_candidates
  );
  return {
    robot_eval_dataset_requested: requested,
    robot_eval_publication_gate_required:
      requested && input.routing.robotEvalPublicationGateRequired === true,
    robot_eval_required_artifacts: [
      "site_card",
      "task_cards",
      "scenario_cards",
      "eval_cards",
      "task_ontology_v1",
      "scenario_family_library",
      "scoring_methodology",
      "proof_boundaries",
      "task_thresholds",
      "publication_readiness",
    ],
    robot_eval_missing_proof_labels: [
      "needs_robot_pov",
      "needs_human_demo",
      "needs_action_logs",
      "needs_actual_outcome",
      "needs_policy_api_endpoint_ref",
      "needs_docker_container_ref",
      "needs_recorded_action_trace_ref",
      "needs_high_level_skill_trace_ref",
      "needs_teleop_demo_ref",
      "needs_sim_controller_plugin_ref",
    ],
    robot_eval_task_thresholds: {
      threshold_source: targetKpi
        ? "capture_manifest_target_kpi"
        : "pipeline_default_publication_gate",
      target_kpi: targetKpi,
      zone,
      claim_boundary: "capture_target_kpi_is_threshold_context_not_rank_fidelity_proof",
    },
    robot_eval_cpu_preflight_inputs: {
      task_anchor_candidates: taskAnchorCandidates,
      scene_asset_hints: sceneAssetHints,
      robot_profile_candidates: robotProfileCandidates,
      route_anchor_candidates: routeAnchorCandidates,
      source_policy:
        "capture_handoff_candidates_only_raw_capture_and_pipeline_validators_remain_authoritative",
      claim_boundary:
        "cpu_preflight_inputs_are_advisory_and_do_not_prove_scene_scale_collision_or_rank_fidelity",
    },
    robot_eval_episode_spec_inputs: {
      task_anchor_candidate_count: taskAnchorCandidates.length,
      scene_asset_hint_count: sceneAssetHints.length,
      robot_profile_candidate_count: robotProfileCandidates.length,
      route_anchor_candidate_count: routeAnchorCandidates.length,
      review_required: true,
      claim_boundary:
        "episode_spec_inputs_can_seed_pipeline_review_but_cannot_set_proof_booleans",
    },
    robot_eval_publication_blockers: hostedReviewBlockers,
  };
}

export function buildPipelineStatusEvent(input: {
  bucketName: string;
  pathInfo: CapturePathInfo;
  objectName: string;
  objectKind: string;
  qaStatus: string;
  pipelineHandoffUri: string;
}): Record<string, unknown> {
  return {
    event_type: "capture.raw_upload_complete.v1",
    scene_id: input.pathInfo.sceneId,
    capture_id: input.pathInfo.captureId,
    raw_prefix: input.pathInfo.rawPrefix,
    raw_prefix_uri: gsUri(input.bucketName, input.pathInfo.rawPrefix),
    upload_completion_marker_uri: gsUri(
      input.bucketName,
      `${input.pathInfo.rawPrefix}/capture_upload_complete.json`
    ),
    trigger_object: input.objectName,
    trigger_kind: input.objectKind,
    qa_status: input.qaStatus,
    pipeline_handoff_uri: input.pipelineHandoffUri,
  };
}

export function buildPipelineHandoffPayload(input: {
  bucketName: string;
  pathInfo: CapturePathInfo;
  objectName: string;
  objectKind: string;
  manifest: Record<string, unknown> | null;
  captureSource: string;
  rawCaptureLineage: Record<string, unknown>;
  qaStatus: string;
  routing: {
    requestedOutputs: string[];
    requestedLanes: string[];
  };
  rawPrefixUri: string;
  framesIndexUri: string;
  captureDescriptorUri: string;
  qaReportUri: string;
  pipelineHandoffUri: string;
  keyframeUri: string | null;
  pipelineStatusEvent: Record<string, unknown>;
  taskSiteContext: Record<string, unknown>;
  sceneMemoryCapture: Record<string, unknown>;
  captureRights: Record<string, unknown>;
  identity: Record<string, unknown>;
  worldlabsPreview: Record<string, unknown>;
  robotEvalHandoff: Record<string, unknown>;
  generatedAt?: string;
}): Record<string, unknown> {
  return {
    schema_version: "v1",
    handoff_source: "BlueprintCapture.extractFrames",
    handoff_topic: PIPELINE_HANDOFF_TOPIC,
    handoff_trigger_object: input.objectName,
    handoff_trigger_kind: input.objectKind,
    scene_id: input.pathInfo.sceneId,
    capture_id: input.pathInfo.captureId,
    site_submission_id: asString(input.manifest?.site_submission_id) ?? null,
    buyer_request_id: asString(input.manifest?.buyer_request_id) ?? null,
    capture_job_id: asString(input.manifest?.capture_job_id) ?? null,
    region_id: asString(input.manifest?.region_id) ?? null,
    rights_profile: asString(input.manifest?.rights_profile) ?? null,
    capture_source: input.captureSource,
    source_device: input.rawCaptureLineage.source_device,
    capture_modality: input.rawCaptureLineage.capture_modality,
    raw_video_uri: input.rawCaptureLineage.raw_video_uri,
    media_metadata: input.rawCaptureLineage.media_metadata,
    qa_status: input.qaStatus,
    requested_outputs: input.routing.requestedOutputs,
    requested_lanes: input.routing.requestedLanes,
    raw_prefix_uri: input.rawPrefixUri,
    raw_prefix: input.pathInfo.rawPrefix,
    frames_index_uri: input.framesIndexUri,
    capture_descriptor_uri: input.captureDescriptorUri,
    qa_report_uri: input.qaReportUri,
    pipeline_handoff_uri: input.pipelineHandoffUri,
    keyframe_uri: input.keyframeUri,
    pipeline_status_event: input.pipelineStatusEvent,
    task_site_context: input.taskSiteContext,
    scene_memory_capture: input.sceneMemoryCapture,
    capture_rights: input.captureRights,
    privacy_lineage: input.rawCaptureLineage.privacy_lineage,
    provenance_lineage: input.rawCaptureLineage.provenance_lineage,
    identity: input.identity,
    ...input.worldlabsPreview,
    ...input.robotEvalHandoff,
    generated_at: input.generatedAt ?? new Date().toISOString(),
  };
}

export function validateIdentityMapping(input: {
  manifest: Record<string, unknown> | null;
  completionMarker: Record<string, unknown> | null;
  pathInfo: CapturePathInfo;
}): {
  blockReasons: string[];
  warnings: string[];
  identity: Record<string, unknown>;
} {
  const { manifest, completionMarker, pathInfo } = input;
  const manifestSceneId = asString(manifest?.scene_id) ?? null;
  const manifestCaptureId = asString(manifest?.capture_id) ?? null;
  const completionSceneId = asString(completionMarker?.scene_id) ?? null;
  const completionCaptureId = asString(completionMarker?.capture_id) ?? null;
  const completionRawPrefix = asString(completionMarker?.raw_prefix) ?? null;
  const siteSubmissionId = asString(manifest?.site_submission_id) ?? null;
  const buyerRequestId = asString(manifest?.buyer_request_id) ?? null;
  const captureJobId = asString(manifest?.capture_job_id) ?? null;
  const upstreamHandoff = asRecord(manifest?.upstream_handoff) ?? null;
  const upstreamHandoffBlockers = asStringArray(upstreamHandoff?.blockers) ?? [];
  const invalidSiteSubmissionIdBlockers = invalidUpstreamIdBlockers(
    "site_submission_id",
    siteSubmissionId,
    pathInfo
  );
  const invalidBuyerRequestIdBlockers = invalidUpstreamIdBlockers(
    "buyer_request_id",
    buyerRequestId,
    pathInfo
  );
  const invalidCaptureJobIdBlockers = invalidUpstreamIdBlockers(
    "capture_job_id",
    captureJobId,
    pathInfo
  );
  const invalidUpstreamBlockers = [
    ...invalidSiteSubmissionIdBlockers,
    ...invalidBuyerRequestIdBlockers,
    ...invalidCaptureJobIdBlockers,
  ];
  const safeSiteSubmissionId =
    invalidSiteSubmissionIdBlockers.length === 0 ? siteSubmissionId : null;
  const safeBuyerRequestId =
    invalidBuyerRequestIdBlockers.length === 0 ? buyerRequestId : null;
  const safeCaptureJobId = invalidCaptureJobIdBlockers.length === 0 ? captureJobId : null;

  const blockReasons: string[] = [];
  const warnings: string[] = [];
  const requiredUpstreamBlockers: string[] = [];

  if (manifestSceneId !== null && manifestSceneId !== pathInfo.sceneId) {
    blockReasons.push("manifest_scene_id_mismatch");
  }
  if (manifestCaptureId !== null && manifestCaptureId !== pathInfo.captureId) {
    blockReasons.push("manifest_capture_id_mismatch");
  }
  if (completionSceneId !== null && completionSceneId !== pathInfo.sceneId) {
    blockReasons.push("completion_scene_id_mismatch");
  }
  if (completionCaptureId !== null && completionCaptureId !== pathInfo.captureId) {
    blockReasons.push("completion_capture_id_mismatch");
  }
  if (completionRawPrefix !== null && completionRawPrefix !== pathInfo.rawPrefix) {
    blockReasons.push("completion_raw_prefix_mismatch");
  }
  if (!safeSiteSubmissionId && invalidSiteSubmissionIdBlockers.length === 0) {
    requiredUpstreamBlockers.push("missing_site_submission_id");
    if (ALLOW_REVIEW_ONLY_HANDOFF_WITHOUT_UPSTREAM_IDS) {
      warnings.push("missing_site_submission_id");
    } else {
      blockReasons.push("missing_site_submission_id");
    }
  }
  if (!safeBuyerRequestId && invalidBuyerRequestIdBlockers.length === 0) {
    warnings.push("missing_buyer_request_id");
    requiredUpstreamBlockers.push("missing_buyer_request_id");
  }
  if (!safeCaptureJobId && invalidCaptureJobIdBlockers.length === 0) {
    requiredUpstreamBlockers.push("missing_capture_job_id");
    if (ALLOW_REVIEW_ONLY_HANDOFF_WITHOUT_UPSTREAM_IDS) {
      warnings.push("missing_capture_job_id");
    } else {
      blockReasons.push("missing_capture_job_id");
    }
  }
  blockReasons.push(...invalidUpstreamBlockers);
  if (!safeBuyerRequestId && !safeCaptureJobId) {
    warnings.push("missing_business_request_identifier");
  }
  const hostedReviewBlockers = Array.from(
    new Set([...requiredUpstreamBlockers, ...invalidUpstreamBlockers, ...upstreamHandoffBlockers])
  );
  for (const blocker of hostedReviewBlockers) {
    warnings.push(`hosted_review_blocker:${blocker}`);
  }

  return {
    blockReasons,
    warnings,
    identity: {
      scene_id: pathInfo.sceneId,
      capture_id: pathInfo.captureId,
      manifest_scene_id: manifestSceneId,
      manifest_capture_id: manifestCaptureId,
      completion_scene_id: completionSceneId,
      completion_capture_id: completionCaptureId,
      site_submission_id: safeSiteSubmissionId,
      buyer_request_id: safeBuyerRequestId,
      capture_job_id: safeCaptureJobId,
      upstream_handoff: upstreamHandoff,
      hosted_review_blockers: hostedReviewBlockers,
      completion_raw_prefix: completionRawPrefix,
    },
  };
}

async function publishPipelineHandoff(payload: Record<string, unknown>): Promise<string> {
  const topic = pubsub.topic(PIPELINE_HANDOFF_TOPIC);
  const messageBuffer = Buffer.from(JSON.stringify(payload));
  const messageId = await topic.publishMessage({
    data: messageBuffer,
    attributes: {
      scene_id: String(payload.scene_id ?? ""),
      capture_id: String(payload.capture_id ?? ""),
      qa_status: String(payload.qa_status ?? ""),
      raw_prefix_uri: String(payload.raw_prefix_uri ?? ""),
      status_event_type: String(
        asRecord(payload.pipeline_status_event)?.event_type ?? "capture.raw_upload_complete.v1"
      ),
      preview_simulation_requested:
        payload.preview_simulation_requested === true ? "true" : "false",
    },
  });
  return messageId;
}

async function loadExistingHandoffReceipt(
  bucket: StorageBucket,
  capturesPrefix: string
): Promise<Record<string, unknown> | null> {
  const receipt = await loadJsonObject(
    bucket,
    `${capturesPrefix}/pipeline_handoff_pubsub_receipt.json`,
    tmpdir()
  );
  if (receipt?.status === "published" && typeof receipt.message_id === "string") {
    return receipt;
  }
  return null;
}

async function savePipelineHandoffPublishReceipt(
  bucket: StorageBucket,
  capturesPrefix: string,
  payload: Record<string, unknown>
): Promise<void> {
  await bucket.file(`${capturesPrefix}/pipeline_handoff_pubsub_receipt.json`).save(
    JSON.stringify(payload, null, 2),
    {
      contentType: "application/json",
    }
  );
}

export type HandoffReceiptAction =
  | { kind: "return_published"; messageId: string }
  | { kind: "claim_new" }
  | { kind: "takeover"; ifGenerationMatch: string }
  | { kind: "wait" };

export const HANDOFF_PUBLISHING_CLAIM_STALE_MS = 15 * 60 * 1000;

/**
 * Pure decision for the atomic handoff-publish claim. The receipt object in
 * GCS doubles as the lock: "publishing" is an in-flight claim, "published" is
 * terminal, and anything else (publish_failed, corrupt) may be taken over via
 * a generation-preconditioned overwrite so retries can republish without
 * racing a concurrent first run into duplicate Pub/Sub messages.
 */
export function decideHandoffReceiptAction(
  receipt: Record<string, unknown> | null,
  receiptGeneration: string | null,
  nowMs: number,
  staleMs: number = HANDOFF_PUBLISHING_CLAIM_STALE_MS
): HandoffReceiptAction {
  if (!receipt) return { kind: "claim_new" };
  if (receipt.status === "published") {
    // A published receipt is terminal even if message_id was lost to a
    // partial write — republishing would duplicate the downstream handoff.
    return {
      kind: "return_published",
      messageId:
        typeof receipt.message_id === "string" && receipt.message_id.length > 0
          ? receipt.message_id
          : "unknown_prior_publish",
    };
  }
  if (receipt.status === "publishing") {
    const claimedAt =
      typeof receipt.claimed_at === "string" ? Date.parse(receipt.claimed_at) : Number.NaN;
    const isStale = !Number.isFinite(claimedAt) || nowMs - claimedAt > staleMs;
    if (isStale && receiptGeneration) {
      return { kind: "takeover", ifGenerationMatch: receiptGeneration };
    }
    return isStale ? { kind: "claim_new" } : { kind: "wait" };
  }
  return receiptGeneration
    ? { kind: "takeover", ifGenerationMatch: receiptGeneration }
    : { kind: "claim_new" };
}

async function readHandoffReceiptWithGeneration(
  bucket: StorageBucket,
  capturesPrefix: string
): Promise<{ receipt: Record<string, unknown> | null; generation: string | null }> {
  const objectName = `${capturesPrefix}/pipeline_handoff_pubsub_receipt.json`;
  const file = bucket.file(objectName);

  // Read the generation FIRST, then download content pinned to that exact
  // generation. Downloading and reading metadata separately would let a
  // concurrent overwrite pair stale content with a newer generation, and a
  // takeover conditioned on that generation would clobber the live claim.
  let generation: string | null = null;
  try {
    const [metadata] = await file.getMetadata();
    generation =
      metadata.generation !== undefined && metadata.generation !== null
        ? String(metadata.generation)
        : null;
  } catch (error) {
    if ((error as { code?: number }).code === 404) {
      return { receipt: null, generation: null };
    }
    throw error;
  }

  try {
    const pinned = generation
      ? bucket.file(objectName, { generation: Number(generation) })
      : file;
    const [contents] = await pinned.download();
    let receipt: Record<string, unknown>;
    try {
      receipt = JSON.parse(contents.toString("utf8")) as Record<string, unknown>;
    } catch {
      receipt = { status: "corrupt" };
    }
    return { receipt, generation };
  } catch (error) {
    const code = (error as { code?: number }).code;
    if (code === 404 || code === 412) {
      // The pinned generation vanished — another invocation overwrote the
      // receipt between our reads. Surface a fresh in-flight claim so the
      // caller waits and re-reads instead of taking over on stale state.
      return {
        receipt: { status: "publishing", claimed_at: new Date().toISOString() },
        generation: null,
      };
    }
    throw error;
  }
}

async function tryWriteHandoffReceiptWithPrecondition(
  bucket: StorageBucket,
  capturesPrefix: string,
  payload: Record<string, unknown>,
  ifGenerationMatch: number
): Promise<boolean> {
  try {
    await bucket.file(`${capturesPrefix}/pipeline_handoff_pubsub_receipt.json`).save(
      JSON.stringify(payload, null, 2),
      {
        contentType: "application/json",
        preconditionOpts: { ifGenerationMatch },
      }
    );
    return true;
  } catch (error) {
    if ((error as { code?: number }).code === 412) {
      return false;
    }
    throw error;
  }
}

function sleepMs(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function publishPipelineHandoffOnce(
  bucket: StorageBucket,
  capturesPrefix: string,
  payload: Record<string, unknown>
): Promise<string> {
  for (let attempt = 0; attempt < 6; attempt += 1) {
    const { receipt, generation } = await readHandoffReceiptWithGeneration(
      bucket,
      capturesPrefix
    );
    const action = decideHandoffReceiptAction(receipt, generation, Date.now());

    if (action.kind === "return_published") {
      return action.messageId;
    }
    if (action.kind === "wait") {
      await sleepMs(2000);
      continue;
    }

    const claimed = await tryWriteHandoffReceiptWithPrecondition(
      bucket,
      capturesPrefix,
      {
        schema_version: "v1",
        status: "publishing",
        claimed_at: new Date().toISOString(),
        topic: PIPELINE_HANDOFF_TOPIC,
        scene_id: payload.scene_id ?? null,
        capture_id: payload.capture_id ?? null,
      },
      action.kind === "takeover" ? Number(action.ifGenerationMatch) : 0
    );
    if (!claimed) {
      // Lost the race; re-read to observe the winner's state.
      continue;
    }

    return await publishClaimedPipelineHandoff(bucket, capturesPrefix, payload);
  }

  throw new Error(
    "pipeline_handoff_publish_contended: another invocation holds the publish claim; retry later"
  );
}

async function publishClaimedPipelineHandoff(
  bucket: StorageBucket,
  capturesPrefix: string,
  payload: Record<string, unknown>
): Promise<string> {
  try {
    const messageId = await publishPipelineHandoff(payload);
    await savePipelineHandoffPublishReceipt(bucket, capturesPrefix, {
      schema_version: "v1",
      status: "published",
      message_id: messageId,
      topic: PIPELINE_HANDOFF_TOPIC,
      published_at: new Date().toISOString(),
      scene_id: payload.scene_id ?? null,
      capture_id: payload.capture_id ?? null,
      pipeline_handoff_uri: payload.pipeline_handoff_uri ?? null,
    });
    return messageId;
  } catch (error) {
    await savePipelineHandoffPublishReceipt(bucket, capturesPrefix, {
      schema_version: "v1",
      status: "publish_failed",
      topic: PIPELINE_HANDOFF_TOPIC,
      failed_at: new Date().toISOString(),
      scene_id: payload.scene_id ?? null,
      capture_id: payload.capture_id ?? null,
      pipeline_handoff_uri: payload.pipeline_handoff_uri ?? null,
      error: error instanceof Error ? error.message : String(error),
      retry_policy:
        "cloud_function_retry_must_republish_from_pipeline_handoff_json_without_reextracting_truth",
    });
    throw error;
  }
}

function normalizedSceneMemoryCapture(manifest: Record<string, unknown> | null): Record<string, unknown> {
  const raw = asRecord(manifest?.scene_memory_capture);
  const sensorAvailability = asRecord(raw?.sensor_availability);
  return {
    continuity_score: asFiniteNumber(raw?.continuity_score) ?? null,
    lighting_consistency: asString(raw?.lighting_consistency) ?? "unknown",
    dynamic_object_density: asString(raw?.dynamic_object_density) ?? "unknown",
    sensor_availability: {
      arkit_poses: sensorAvailability?.arkit_poses === true,
      arkit_intrinsics: sensorAvailability?.arkit_intrinsics === true,
      arkit_depth: sensorAvailability?.arkit_depth === true,
      arkit_confidence: sensorAvailability?.arkit_confidence === true,
      arkit_meshes: sensorAvailability?.arkit_meshes === true,
      motion: sensorAvailability?.motion === true,
    },
    operator_notes: hasStringArray(raw?.operator_notes) ? raw?.operator_notes : [],
    inaccessible_areas: hasStringArray(raw?.inaccessible_areas) ? raw?.inaccessible_areas : [],
    semantic_anchors_observed: hasStringArray(raw?.semantic_anchors_observed)
      ? raw?.semantic_anchors_observed
      : [],
    relocalization_count: typeof raw?.relocalization_count === "number" ? raw?.relocalization_count : null,
    overlap_checkpoint_count:
      typeof raw?.overlap_checkpoint_count === "number" ? raw?.overlap_checkpoint_count : null,
    // world_model_candidate is NOT read from the raw manifest here. It is computed
    // deterministically from actual artifact presence and capture_mode after the bridge
    // has verified GCS artifacts. See canonicalWorldModelCandidate() below.
    world_model_candidate_reasoning: Array.isArray(raw?.world_model_candidate_reasoning)
      ? (raw?.world_model_candidate_reasoning as string[])
      : [],
    motion_provenance: asString(raw?.motion_provenance) ?? null,
    motion_timestamps_capture_relative: raw?.motion_timestamps_capture_relative === true,
  };
}

function normalizedSiteIdentity(manifest: Record<string, unknown> | null): Record<string, unknown> | null {
  const raw = asRecord(manifest?.site_identity);
  if (!raw) return null;
  const geo = asRecord(raw.geo);
  return {
    site_id: asString(raw.site_id) ?? null,
    site_id_source: asString(raw.site_id_source) ?? "unknown",
    place_id: asString(raw.place_id) ?? null,
    site_name: asString(raw.site_name) ?? null,
    address_full: asString(raw.address_full) ?? null,
    geo: geo
      ? {
          latitude: typeof geo.latitude === "number" ? geo.latitude : null,
          longitude: typeof geo.longitude === "number" ? geo.longitude : null,
          accuracy_m: typeof geo.accuracy_m === "number" ? geo.accuracy_m : null,
        }
      : null,
    building_id: asString(raw.building_id) ?? null,
    floor_id: asString(raw.floor_id) ?? null,
    room_id: asString(raw.room_id) ?? null,
    zone_id: asString(raw.zone_id) ?? null,
  };
}

function normalizedCaptureTopology(manifest: Record<string, unknown> | null): Record<string, unknown> | null {
  const raw = asRecord(manifest?.capture_topology);
  if (!raw) return null;
  return {
    capture_session_id: asString(raw.capture_session_id) ?? null,
    site_visit_id: asString(raw.site_visit_id) ?? asString(raw.capture_session_id) ?? null,
    route_id: asString(raw.route_id) ?? null,
    pass_id: asString(raw.pass_id) ?? null,
    pass_index: typeof raw.pass_index === "number" ? raw.pass_index : null,
    intended_pass_role: asString(raw.intended_pass_role) ?? "primary",
    entry_anchor_id: asString(raw.entry_anchor_id) ?? null,
    return_anchor_id: asString(raw.return_anchor_id) ?? null,
    coordinate_frame_session_id:
      asString(raw.coordinate_frame_session_id) ?? asString(raw.capture_session_id) ?? null,
    arkit_session_id:
      asString(raw.arkit_session_id) ??
      asString(raw.coordinate_frame_session_id) ??
      asString(raw.capture_session_id) ??
      null,
    entry_anchor_t_capture_sec:
      typeof raw.entry_anchor_t_capture_sec === "number" ? raw.entry_anchor_t_capture_sec : null,
    entry_anchor_hold_duration_sec:
      typeof raw.entry_anchor_hold_duration_sec === "number" ? raw.entry_anchor_hold_duration_sec : null,
  };
}

function normalizedRouteAnchors(manifest: Record<string, unknown> | null): Record<string, unknown> | null {
  const raw = asRecord(manifest?.route_anchors);
  if (!raw) return null;
  const routeAnchors = Array.isArray(raw.route_anchors)
    ? raw.route_anchors
        .filter((item): item is Record<string, unknown> => typeof item === "object" && item !== null)
        .map((item) => ({
          anchor_id: asString(item.anchor_id) ?? null,
          anchor_type: asString(item.anchor_type) ?? null,
          label: asString(item.label) ?? null,
          expected_observation: asString(item.expected_observation) ?? null,
          required_in_primary_pass: item.required_in_primary_pass === true,
          required_in_revisit_pass: item.required_in_revisit_pass === true,
        }))
    : [];
  return {
    schema_version: asString(raw.schema_version) ?? "v1",
    route_anchors: routeAnchors,
  };
}

function normalizedCheckpointEvents(manifest: Record<string, unknown> | null): Record<string, unknown> | null {
  const raw = asRecord(manifest?.checkpoint_events);
  if (!raw) return null;
  const checkpointEvents = Array.isArray(raw.checkpoint_events)
    ? raw.checkpoint_events
        .filter((item): item is Record<string, unknown> => typeof item === "object" && item !== null)
        .map((item) => ({
          anchor_id: asString(item.anchor_id) ?? null,
          pass_id: asString(item.pass_id) ?? null,
          t_capture_sec: typeof item.t_capture_sec === "number" ? item.t_capture_sec : null,
          hold_duration_sec: typeof item.hold_duration_sec === "number" ? item.hold_duration_sec : null,
          completed: item.completed === true,
        }))
    : [];
  return {
    schema_version: asString(raw.schema_version) ?? "v1",
    checkpoint_events: checkpointEvents,
  };
}

function normalizedRelocalizationEvents(manifest: Record<string, unknown> | null): Record<string, unknown> | null {
  const raw = asRecord(manifest?.relocalization_events);
  if (!raw) return null;
  const relocalizationEvents = Array.isArray(raw.relocalization_events)
    ? raw.relocalization_events
        .filter((item): item is Record<string, unknown> => typeof item === "object" && item !== null)
        .map((item) => ({
          event_id: asString(item.event_id) ?? null,
          pass_id: asString(item.pass_id) ?? null,
          route_id: asString(item.route_id) ?? null,
          t_capture_sec: typeof item.t_capture_sec === "number" ? item.t_capture_sec : null,
          status: asString(item.status) ?? null,
          anchor_id: asString(item.anchor_id) ?? null,
          coordinate_frame_session_id: asString(item.coordinate_frame_session_id) ?? null,
        }))
    : [];
  return {
    schema_version: asString(raw.schema_version) ?? "v1",
    relocalization_events: relocalizationEvents,
  };
}

/**
 * Canonical world_model_candidate rule — shared across iOS finalizer, cloud bridge,
 * and local pipeline. Must be kept in sync.
 *
 * capture_mode.resolved_mode == "site_world_candidate"
 *   AND arkit_poses present (actual GCS artifact check)
 *   AND arkit_intrinsics present
 *   AND arkit_depth present
 *   AND pose alignment quality is pose_assisted (implies poseMatchRate >= 0.65 AND p95 <= 0.2)
 *   AND derived_scene_generation_allowed
 */
export function canonicalWorldModelCandidate({
  manifest,
  actualAvailability,
  processingProfile,
  captureRights,
  captureSource,
}: {
  manifest: Record<string, unknown> | null;
  actualAvailability: { arkit_poses: boolean; arkit_intrinsics: boolean; arkit_depth: boolean };
  processingProfile: string;
  captureRights: Record<string, unknown>;
  captureSource: "iphone" | "android" | "glasses" | "unknown";
}): { candidate: boolean; reasoning: string[] } {
  const captureMode = asRecord(manifest?.capture_mode);
  const siteIdentity = asRecord(manifest?.site_identity);
  const siteIdPresent = Boolean(asString(siteIdentity?.site_id));
  const resolvedMode = asString(captureMode?.resolved_mode) ?? "qualification_only";
  const requestedMode = asString(captureMode?.requested_mode) ?? "qualification_only";
  const arkitReady =
    actualAvailability.arkit_poses &&
    actualAvailability.arkit_intrinsics &&
    actualAvailability.arkit_depth &&
    processingProfile === "pose_assisted";
  const nonArkitDeferred =
    captureSource !== "iphone" &&
    requestedMode === "site_world_candidate" &&
    captureRights.derived_scene_generation_allowed === true;
  const reasoning: string[] = [
    `capture_mode_site_world_candidate:${resolvedMode === "site_world_candidate"}`,
    `site_id_present:${siteIdPresent}`,
    `capture_source:${captureSource}`,
    `arkit_poses_valid:${actualAvailability.arkit_poses}`,
    `arkit_intrinsics_valid:${actualAvailability.arkit_intrinsics}`,
    `depth_coverage_ok:${actualAvailability.arkit_depth}`,
    `pose_alignment_ok:${processingProfile === "pose_assisted"}`,
    `geometry_ready:false`,
    `geometry_source:none`,
    `derived_scene_generation_allowed:${captureRights.derived_scene_generation_allowed === true}`,
    `awaiting_geometry_stage:${nonArkitDeferred}`,
  ];
  const candidate =
    siteIdPresent &&
    resolvedMode === "site_world_candidate" &&
    arkitReady &&
    captureRights.derived_scene_generation_allowed === true;
  return { candidate, reasoning };
}

function normalizedCaptureRights(manifest: Record<string, unknown> | null): Record<string, unknown> {
  const raw = asRecord(manifest?.capture_rights);
  return {
    derived_scene_generation_allowed: raw?.derived_scene_generation_allowed === true,
    data_licensing_allowed: raw?.data_licensing_allowed === true,
    capture_contributor_payout_eligible: raw?.capture_contributor_payout_eligible === true,
    consent_status: asString(raw?.consent_status) ?? "unknown",
    permission_document_uri: asString(raw?.permission_document_uri) ?? null,
    consent_scope: hasStringArray(raw?.consent_scope) ? raw?.consent_scope : [],
    consent_notes: hasStringArray(raw?.consent_notes) ? raw?.consent_notes : [],
  };
}

function validateSceneMemoryCapture(manifest: Record<string, unknown>): string[] {
  const warnings: string[] = [];
  const sceneMemory = asRecord(manifest.scene_memory_capture);
  if (!sceneMemory) {
    warnings.push("missing_scene_memory_capture");
    return warnings;
  }
  const sensors = asRecord(sceneMemory.sensor_availability);
  const hasRequiredArrays =
    hasStringArray(sceneMemory.operator_notes) && hasStringArray(sceneMemory.inaccessible_areas);
  const hasRequiredSensors =
    sensors !== undefined &&
    typeof sensors.arkit_poses === "boolean" &&
    typeof sensors.arkit_intrinsics === "boolean" &&
    typeof sensors.arkit_depth === "boolean" &&
    typeof sensors.arkit_confidence === "boolean" &&
    typeof sensors.arkit_meshes === "boolean" &&
    typeof sensors.motion === "boolean";
  if (!hasRequiredArrays || !hasRequiredSensors) {
    warnings.push("malformed_scene_memory_capture");
  }
  return warnings;
}

function validateCaptureRights(manifest: Record<string, unknown>): string[] {
  const warnings: string[] = [];
  const captureRights = asRecord(manifest.capture_rights);
  if (!captureRights) {
    warnings.push("missing_capture_rights");
    return warnings;
  }
  const consentStatus = asString(captureRights.consent_status);
  const validConsentStatus =
    consentStatus === "documented" || consentStatus === "policy_only" || consentStatus === "unknown";
  const hasValidScope = hasStringArray(captureRights.consent_scope);
  const hasValidNotes = hasStringArray(captureRights.consent_notes);
  if (!validConsentStatus || !hasValidScope || !hasValidNotes) {
    warnings.push("malformed_capture_rights");
  }
  return warnings;
}

export function validateManifest(manifest: Record<string, unknown> | null): {
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
  const schemaVersion = asString(manifest.schema_version);
  if (schemaVersion === "v3" || (asString(manifest.capture_schema_version)?.startsWith("3.") ?? false)) {
    const captureSource = asString(manifest.capture_source);
    const v3RequiredStrings = [
      "capture_id",
      "coordinate_frame_session_id",
      "app_version",
      "app_build",
      "hardware_model_identifier",
      "device_model_marketing",
      "capture_profile_id",
    ];
    if (captureSource === "iphone") {
      v3RequiredStrings.push("ios_version", "ios_build");
    }
    const v3RequiredBooleans = ["depth_supported"];
    for (const field of v3RequiredStrings) {
      if (!asString(manifest[field])) {
        missingRequired.push(field);
      }
    }
    for (const field of v3RequiredBooleans) {
      if (typeof manifest[field] !== "boolean") {
        missingRequired.push(field);
      }
    }
    if (!asRecord(manifest.capture_capabilities)) {
      missingRequired.push("capture_capabilities");
    }
  }
  warnings.push(...validateSceneMemoryCapture(manifest));
  warnings.push(...validateCaptureRights(manifest));

  return {
    valid: missingRequired.length === 0,
    missingRequired,
    warnings,
  };
}

/**
 * extractFrames
 * - Trigger: scenes/<scene>/captures/<capture_id>/raw/walkthrough.mov (canonical iOS uploader format)
 *   OR: scenes/<scene>/<source>/<capture_id>/raw/walkthrough.mov (legacy scenes format)
 *   OR: targets/<scene>/raw/walkthrough.mov (legacy format)
 * - Output: <same_prefix>/frames/*.jpg + index.jsonl
 * - FPS: 5
 * - Includes best-matching ARKit pose per frame when available.
 */
export const extractFrames = onObjectFinalized(
  {
    region: "us-central1",
    // /tmp is tmpfs on Cloud Run and counts against this limit — sized so the
    // inline video ceiling (see DEFAULT_MAX_INLINE_EXTRACT_FRAMES_VIDEO_BYTES)
    // plus extracted frames plus node heap cannot OOM the instance.
    memory: "4GiB",
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

    const objectKind = captureObjectKind(objectName);
    if (objectKind === "other") {
      logger.info("Skipping object (not a supported capture trigger)", { objectName, contentType });
      return;
    }

    const pathInfo = parseCapturePath(objectName, objectGeneration);
    if (!pathInfo) {
      logger.info("Skipping object (unsupported raw capture path)", { objectName });
      return;
    }

    if (objectKind === "walkthrough" && pathInfo.mode !== "targets") {
      logger.info("Skipping walkthrough trigger until upload completion marker arrives", {
        objectName,
        sceneId: pathInfo.sceneId,
        captureId: pathInfo.captureId,
      });
      return;
    }

    logger.info("Starting frame extraction", {
      bucketName,
      objectName,
      objectKind,
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
    const completionMarkerObjectName = `${pathInfo.rawPrefix}/capture_upload_complete.json`;
    const siteIdentityObjectName = `${pathInfo.rawPrefix}/site_identity.json`;
    const captureTopologyObjectName = `${pathInfo.rawPrefix}/capture_topology.json`;
    const captureModeObjectName = `${pathInfo.rawPrefix}/capture_mode.json`;
    const routeAnchorsObjectName = `${pathInfo.rawPrefix}/route_anchors.json`;
    const checkpointEventsObjectName = `${pathInfo.rawPrefix}/checkpoint_events.json`;
    const relocalizationEventsObjectName = `${pathInfo.rawPrefix}/relocalization_events.json`;
    const intrinsicsObjectName = `${pathInfo.rawPrefix}/arkit/intrinsics.json`;
    const existingPipelineHandoff = await loadJsonObject(
      bucket,
      `${pathInfo.capturesPrefix}/pipeline_handoff.json`,
      tmp
    );
    if (existingPipelineHandoff) {
      const handoffMessageId = await publishPipelineHandoffOnce(
        bucket,
        pathInfo.capturesPrefix,
        existingPipelineHandoff
      );
      logger.info("Republished existing pipeline handoff without re-extracting frames", {
        captureId: pathInfo.captureId,
        sceneId: pathInfo.sceneId,
        handoffTopic: PIPELINE_HANDOFF_TOPIC,
        handoffMessageId,
      });
      return;
    }

    const manifestExists = await waitForObjectExists(bucket, manifestObjectName, 45000, 3000);
    const rawManifest = manifestExists ? await loadJsonObject(bucket, manifestObjectName, tmp) : null;
    const sidecarSiteIdentity = await loadJsonObject(bucket, siteIdentityObjectName, tmp);
    const sidecarCaptureTopology = await loadJsonObject(bucket, captureTopologyObjectName, tmp);
    const sidecarCaptureMode = await loadJsonObject(bucket, captureModeObjectName, tmp);
    const sidecarRouteAnchors = await loadJsonObject(bucket, routeAnchorsObjectName, tmp);
    const sidecarCheckpointEvents = await loadJsonObject(bucket, checkpointEventsObjectName, tmp);
    const sidecarRelocalizationEvents = await loadJsonObject(bucket, relocalizationEventsObjectName, tmp);
    const manifest = mergeManifestWithSidecars(rawManifest, {
      siteIdentity: sidecarSiteIdentity,
      captureTopology: sidecarCaptureTopology,
      captureMode: sidecarCaptureMode,
      routeAnchors: sidecarRouteAnchors,
      checkpointEvents: sidecarCheckpointEvents,
      relocalizationEvents: sidecarRelocalizationEvents,
    });
    const completionMarker =
      objectKind === "completion_marker"
        ? await loadJsonObject(bucket, completionMarkerObjectName, tmp)
        : null;
    const manifestValidation = validateManifest(manifest);
    const walkthroughObjectName = resolveWalkthroughObjectName(manifest, pathInfo, objectName);
    const walkthroughExists = await waitForObjectExists(bucket, walkthroughObjectName, 45000, 3000);

    const poseIndex = await loadArkitPoses(bucket, pathInfo.rawPrefix, tmp);
    const arkitFrameQuality = await loadArkitFrameQuality(bucket, pathInfo.rawPrefix, tmp);
    const intrinsics = await loadJsonObject(bucket, intrinsicsObjectName, tmp);
    const actualAvailability: ArtifactAvailability = {
      arkit_poses: poseIndex.byFrameId.size > 0 || poseIndex.byTime.length > 0,
      arkit_intrinsics: isValidIntrinsicsPayload(intrinsics),
      arkit_depth: await prefixHasObjects(bucket, `${pathInfo.rawPrefix}/arkit/depth/`),
      arkit_confidence: await prefixHasObjects(bucket, `${pathInfo.rawPrefix}/arkit/confidence/`),
      arkit_meshes: await prefixHasObjects(bucket, `${pathInfo.rawPrefix}/arkit/meshes/`),
      motion: await fileHasContent(bucket, `${pathInfo.rawPrefix}/motion.jsonl`),
      camera_pose: await fileHasContent(bucket, `${pathInfo.rawPrefix}/arcore/poses.jsonl`),
      camera_intrinsics: isValidIntrinsicsPayload(
        await loadJsonObject(bucket, `${pathInfo.rawPrefix}/arcore/session_intrinsics.json`, tmp)
      ),
      depth:
        (await fileExists(bucket, `${pathInfo.rawPrefix}/arcore/depth_manifest.json`)) ||
        (await prefixHasObjects(bucket, `${pathInfo.rawPrefix}/arcore/depth/`)),
      depth_confidence:
        (await fileExists(bucket, `${pathInfo.rawPrefix}/arcore/confidence_manifest.json`)) ||
        (await prefixHasObjects(bucket, `${pathInfo.rawPrefix}/arcore/confidence/`)),
      point_cloud: await fileHasContent(bucket, `${pathInfo.rawPrefix}/arcore/point_cloud.jsonl`),
      planes: await fileHasContent(bucket, `${pathInfo.rawPrefix}/arcore/planes.jsonl`),
      tracking_state: await fileHasContent(bucket, `${pathInfo.rawPrefix}/arcore/tracking_state.jsonl`),
      light_estimate: await fileHasContent(bucket, `${pathInfo.rawPrefix}/arcore/light_estimates.jsonl`),
      geospatial: await fileHasContent(bucket, `${pathInfo.rawPrefix}/arcore/geospatial.jsonl`),
      companion_phone_pose: await fileHasContent(bucket, `${pathInfo.rawPrefix}/companion_phone/poses.jsonl`),
      companion_phone_intrinsics: isValidIntrinsicsPayload(
        await loadJsonObject(bucket, `${pathInfo.rawPrefix}/companion_phone/session_intrinsics.json`, tmp)
      ),
      companion_phone_calibration: await fileExists(
        bucket,
        `${pathInfo.rawPrefix}/companion_phone/calibration.json`
      ),
    };
    const file = bucket.file(walkthroughObjectName);
    if (walkthroughExists) {
      let rawVideoSizeBytes: number | null = null;
      try {
        const [metadata] = await file.getMetadata();
        rawVideoSizeBytes = parseStorageObjectSize(metadata.size);
      } catch (error) {
        logger.warn("Failed to inspect raw walkthrough video size before download", {
          walkthroughObjectName,
          error,
        });
      }
      const sizeGate = inlineFrameExtractionSizeGate(rawVideoSizeBytes);
      if (!sizeGate.inlineAllowed) {
        const { blockReport, qaReport, pipelineStatusEvent } = buildLargeVideoIngestBlockedArtifacts({
          bucketName,
          pathInfo,
          objectName,
          objectKind,
          walkthroughObjectName,
          manifestExists,
          walkthroughExists,
          manifestValidation,
          sizeGate,
        });
        await Promise.all([
          bucket
            .file(`${pathInfo.capturesPrefix}/large_video_ingest_blocked.json`)
            .save(JSON.stringify(blockReport, null, 2), { contentType: "application/json" }),
          bucket
            .file(`${pathInfo.capturesPrefix}/qa_report.json`)
            .save(JSON.stringify(qaReport, null, 2), { contentType: "application/json" }),
          bucket
            .file(`${pathInfo.capturesPrefix}/pipeline_status_event.json`)
            .save(JSON.stringify(pipelineStatusEvent, null, 2), {
              contentType: "application/json",
            }),
        ]);
        logger.warn("Blocked inline frame extraction before downloading raw walkthrough video", {
          captureId: pathInfo.captureId,
          sceneId: pathInfo.sceneId,
          walkthroughObjectName,
          blockCode: sizeGate.blockCode,
          rawVideoSizeBytes: sizeGate.rawVideoSizeBytes,
          maxInlineVideoBytes: sizeGate.maxInlineVideoBytes,
        });
        return;
      }
    }

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

        const poseFrameId = asString(pose.frame_id);
        const frameQuality =
          (poseFrameId ? arkitFrameQuality.get(poseFrameId) : undefined) ??
          arkitFrameQuality.get(frameId);
        if (frameQuality) {
          const sceneDepthFile =
            asString(frameQuality.sceneDepthFile) ?? asString(frameQuality.scene_depth_file);
          const smoothedSceneDepthFile =
            asString(frameQuality.smoothedSceneDepthFile) ??
            asString(frameQuality.smoothed_scene_depth_file);
          const confidenceFile =
            asString(frameQuality.confidenceFile) ?? asString(frameQuality.confidence_file);
          const arkitFrame: Record<string, unknown> = {
            frame_id: poseFrameId ?? frameId,
            tracking_state:
              asString(frameQuality.trackingState) ?? asString(frameQuality.tracking_state) ?? null,
            tracking_reason:
              asString(frameQuality.trackingReason) ?? asString(frameQuality.tracking_reason) ?? null,
            world_mapping_status:
              asString(frameQuality.worldMappingStatus) ??
              asString(frameQuality.world_mapping_status) ??
              null,
            relocalization_event:
              frameQuality.relocalizationEvent === true || frameQuality.relocalization_event === true,
            sharpness_score:
              asFiniteNumber(frameQuality.sharpnessScore) ??
              asFiniteNumber(frameQuality.sharpness_score) ??
              null,
            depth_source:
              asString(frameQuality.depthSource) ?? asString(frameQuality.depth_source) ?? null,
            depth_valid_fraction:
              asFiniteNumber(frameQuality.depthValidFraction) ??
              asFiniteNumber(frameQuality.depth_valid_fraction) ??
              null,
            missing_depth_fraction:
              asFiniteNumber(frameQuality.missingDepthFraction) ??
              asFiniteNumber(frameQuality.missing_depth_fraction) ??
              null,
            anchor_observations:
              asStringArray(frameQuality.anchorObservations) ??
              asStringArray(frameQuality.anchor_observations) ??
              [],
            exposure_duration_s:
              asFiniteNumber(frameQuality.exposureDurationS) ??
              asFiniteNumber(frameQuality.exposure_duration_s) ??
              null,
            iso: asFiniteNumber(frameQuality.iso) ?? null,
            exposure_target_bias:
              asFiniteNumber(frameQuality.exposureTargetBias) ??
              asFiniteNumber(frameQuality.exposure_target_bias) ??
              null,
            white_balance_gains:
              asRecord(frameQuality.whiteBalanceGains) ??
              asRecord(frameQuality.white_balance_gains) ??
              null,
            depth_uri: smoothedSceneDepthFile
              ? gsUri(bucketName, `${pathInfo.rawPrefix}/${smoothedSceneDepthFile}`)
              : sceneDepthFile
              ? gsUri(bucketName, `${pathInfo.rawPrefix}/${sceneDepthFile}`)
              : null,
            confidence_uri: confidenceFile
              ? gsUri(bucketName, `${pathInfo.rawPrefix}/${confidenceFile}`)
              : null,
          };
          entry.arkit_frame = arkitFrame;
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
      (pathInfo.captureSourcePath === "iphone" ||
      pathInfo.captureSourcePath === "glasses" ||
      pathInfo.captureSourcePath === "android" ||
      pathInfo.captureSourcePath === "android_phone"
        ? pathInfo.captureSourcePath
        : "unknown");
    const captureSource = normalizeCaptureSource(captureSourceRaw);
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

    const rawPrefixUri = gsUri(bucketName, pathInfo.rawPrefix);
    const framesIndexUri = gsUri(bucketName, `${pathInfo.framesPrefix}/index.jsonl`);
    const qaReportUri = gsUri(bucketName, `${pathInfo.capturesPrefix}/qa_report.json`);
    const captureDescriptorUri = gsUri(
      bucketName,
      `${pathInfo.capturesPrefix}/capture_descriptor.json`
    );
    const pipelineHandoffUri = gsUri(bucketName, `${pathInfo.capturesPrefix}/pipeline_handoff.json`);
    const sceneMemoryCapture = normalizedSceneMemoryCapture(manifest);
    const captureRights = normalizedCaptureRights(manifest);
    const siteIdentity = normalizedSiteIdentity(manifest);
    const captureTopology = normalizedCaptureTopology(manifest);
    const rawCaptureLineage = buildRawCaptureLineageFields(
      bucketName,
      pathInfo,
      manifest,
      captureSource,
      walkthroughObjectName
    );
    const routeAnchors = normalizedRouteAnchors(manifest);
    const checkpointEvents = normalizedCheckpointEvents(manifest);
    const relocalizationEvents = normalizedRelocalizationEvents(manifest);
    // worldModelCandidate is computed AFTER actualAvailability is known (see below).
    const routing = deriveRequestedRouting(manifest);
    const taskSiteContext = buildTaskSiteContext(manifest);
    const worldlabsPreview = buildWorldlabsPreviewFields(
      bucketName,
      pathInfo,
      routing.previewSimulationRequested,
      walkthroughObjectName
    );
    const claimedSensorRecord =
      typeof sceneMemoryCapture.sensor_availability === "object" && sceneMemoryCapture.sensor_availability
        ? (sceneMemoryCapture.sensor_availability as Record<string, unknown>)
        : {};
    const claimedCapabilities =
      typeof manifest?.capture_capabilities === "object" && manifest?.capture_capabilities
        ? (manifest?.capture_capabilities as Record<string, unknown>)
        : {};
    const claimedAvailability: ArtifactAvailability = {
      arkit_poses: claimedSensorRecord.arkit_poses === true,
      arkit_intrinsics: claimedSensorRecord.arkit_intrinsics === true,
      arkit_depth: claimedSensorRecord.arkit_depth === true,
      arkit_confidence: claimedSensorRecord.arkit_confidence === true,
      arkit_meshes: claimedSensorRecord.arkit_meshes === true,
      motion:
        claimedCapabilities.motion === true || claimedSensorRecord.motion === true,
      camera_pose: claimedCapabilities.camera_pose === true,
      camera_intrinsics: claimedCapabilities.camera_intrinsics === true,
      depth: claimedCapabilities.depth === true,
      depth_confidence: claimedCapabilities.depth_confidence === true,
      point_cloud: claimedCapabilities.point_cloud === true,
      planes: claimedCapabilities.planes === true,
      tracking_state: claimedCapabilities.tracking_state === true,
      light_estimate: claimedCapabilities.light_estimate === true,
      geospatial: claimedCapabilities.geospatial === true,
      companion_phone_pose: claimedCapabilities.companion_phone_pose === true,
      companion_phone_intrinsics: claimedCapabilities.companion_phone_intrinsics === true,
      companion_phone_calibration: claimedCapabilities.companion_phone_calibration === true,
    };
    const claimedArtifactEvaluation = evaluateClaimedArtifacts({
      claimed: claimedAvailability,
      actual: actualAvailability,
    });
    finalWarnings.push(...claimedArtifactEvaluation.warnings);
    if (claimedArtifactEvaluation.blockers.length > 0) {
      finalStatus = "blocked";
      finalReasons.push(...claimedArtifactEvaluation.blockers);
    }
    const identityValidation = validateIdentityMapping({
      manifest,
      completionMarker,
      pathInfo,
    });
    if (identityValidation.blockReasons.length > 0) {
      finalStatus = "blocked";
      finalReasons.push(...identityValidation.blockReasons);
    }
    finalWarnings.push(...identityValidation.warnings);
    sceneMemoryCapture.sensor_availability = claimedArtifactEvaluation.valid;
    const robotEvalHandoff = buildRobotEvalHandoffFields({
      routing,
      taskSiteContext,
      identity: identityValidation.identity,
    });

    // Compute world_model_candidate deterministically from actual artifact presence.
    // This is the canonical rule shared with iOS finalizer and local pipeline.
    const { candidate: worldModelCandidate, reasoning: worldModelCandidateReasoning } =
      canonicalWorldModelCandidate({
        manifest,
        actualAvailability: {
          arkit_poses: claimedArtifactEvaluation.valid.arkit_poses === true,
          arkit_intrinsics: claimedArtifactEvaluation.valid.arkit_intrinsics === true,
          arkit_depth: claimedArtifactEvaluation.valid.arkit_depth === true,
        },
        processingProfile: qualityGate.processingProfile,
        captureRights,
        captureSource,
      });
    sceneMemoryCapture.world_model_candidate = worldModelCandidate;
    sceneMemoryCapture.world_model_candidate_reasoning = worldModelCandidateReasoning;
    sceneMemoryCapture.geometry_source = null;
    sceneMemoryCapture.geometry_ready = false;

    // Resolve capture_mode with source-aware semantics.
    const rawCaptureMode = asRecord(manifest?.capture_mode);
    const requestedMode = asString(rawCaptureMode?.requested_mode) ?? "qualification_only";
    const stableSiteIdPresent = Boolean(asString(siteIdentity?.site_id));
    const deferGeometry =
      captureSource !== "iphone" &&
      requestedMode === "site_world_candidate" &&
      stableSiteIdPresent &&
      captureRights.derived_scene_generation_allowed === true;
    const resolvedMode =
      worldModelCandidate || deferGeometry ? "site_world_candidate" : "qualification_only";
    const captureMode = {
      requested_mode: requestedMode,
      resolved_mode: resolvedMode,
      downgrade_reason:
        requestedMode === "site_world_candidate" && resolvedMode === "qualification_only"
          ? stableSiteIdPresent
            ? "awaiting_geometry_stage"
            : "missing_site_id"
          : null,
      geometry_status: deferGeometry && !worldModelCandidate ? "awaiting_geometry_stage" : null,
    };

    const runtimeBuildBlockers = [
      ...(captureSource === "iphone" ? [] : ["geometry_ready=false"]),
      ...(stableSiteIdPresent ? [] : ["missing_site_id"]),
      ...(worldModelCandidate ? [] : ["world_model_candidate=false"]),
      ...(walkthroughExists ? [] : ["missing_walkthrough"]),
      ...(sortedFiles.length > 0 ? [] : ["missing_frames_index"]),
    ];
    const runtimeBuildEligible = finalStatus === "passed" && runtimeBuildBlockers.length === 0;

    const captureDescriptor: Record<string, unknown> = {
      schema_version: "v1",
      scene_id: pathInfo.sceneId,
      capture_id: pathInfo.captureId,
      capture_source: captureSource,
      source_device: rawCaptureLineage.source_device,
      capture_modality: rawCaptureLineage.capture_modality,
      capture_profile_id: asString(manifest?.capture_profile_id) ?? null,
      capture_capabilities: manifest?.capture_capabilities ?? {},
      capture_tier: qualityGate.captureTier,
      processing_profile: qualityGate.processingProfile,
      raw_video_uri: rawCaptureLineage.raw_video_uri,
      raw_prefix_uri: rawPrefixUri,
      frames_index_uri: framesIndexUri,
      media_metadata: rawCaptureLineage.media_metadata,
      keyframe_uri: keyframeUri,
      intended_space_type: asString(manifest?.intended_space_type) ?? "unknown",
      quality: {
        pose_match_rate: poseMatchRate,
        p95_pose_delta_sec: p95PoseDeltaSec,
        frame_count: sortedFiles.length,
      },
      capture_bundle: buildCaptureBundleReferences({
        bucketName,
        rawPrefix: pathInfo.rawPrefix,
        availability: claimedArtifactEvaluation.valid,
      }),
      site_submission_id: asString(manifest?.site_submission_id) ?? null,
      buyer_request_id: asString(manifest?.buyer_request_id) ?? null,
      capture_job_id: asString(manifest?.capture_job_id) ?? null,
      region_id: asString(manifest?.region_id) ?? null,
      rights_profile: asString(manifest?.rights_profile) ?? null,
      requested_outputs: routing.requestedOutputs,
      scene_memory_capture: sceneMemoryCapture,
      capture_rights: captureRights,
      privacy_lineage: rawCaptureLineage.privacy_lineage,
      provenance_lineage: rawCaptureLineage.provenance_lineage,
      upstream_handoff: asRecord(manifest?.upstream_handoff) ?? null,
      site_identity: siteIdentity,
      capture_topology: captureTopology,
      route_anchors: routeAnchors,
      checkpoint_events: checkpointEvents,
      relocalization_events: relocalizationEvents,
      capture_mode: captureMode,
      site_visit_id:
        asString(captureTopology?.site_visit_id) ??
        asString(captureTopology?.capture_session_id) ??
        null,
      geometry_source: null,
      geometry_ready: false,
      coordinate_frame_session_id:
        asString(captureTopology?.coordinate_frame_session_id) ??
        asString(captureTopology?.arkit_session_id) ??
        asString(captureTopology?.capture_session_id) ??
        asString(captureTopology?.captureSessionId) ??
        pathInfo.captureId,
      task_site_context: taskSiteContext,
      identity: identityValidation.identity,
      neoverse_runtime: {
        launchable_site_world_candidate: runtimeBuildEligible,
        blockers: runtimeBuildBlockers,
        required_spatial_conditioning: ["arkit_poses", "arkit_intrinsics"],
      },
      requested_lanes: routing.requestedLanes,
      metadata: {
        scene_memory_capture: sceneMemoryCapture,
        capture_rights: captureRights,
        privacy_lineage: rawCaptureLineage.privacy_lineage,
        provenance_lineage: rawCaptureLineage.provenance_lineage,
        media_metadata: rawCaptureLineage.media_metadata,
        source_device: rawCaptureLineage.source_device,
        upstream_handoff: asRecord(manifest?.upstream_handoff) ?? null,
        site_identity: siteIdentity,
        capture_topology: captureTopology,
        route_anchors: routeAnchors,
        checkpoint_events: checkpointEvents,
        relocalization_events: relocalizationEvents,
        capture_mode: captureMode,
      },
      ...worldlabsPreview,
      ...robotEvalHandoff,
      generated_at: new Date().toISOString(),
    };

    if (!keyframeUri) {
      finalWarnings.push("missing_keyframe");
    }
    if (pathInfo.mode === "targets") {
      finalWarnings.push("legacy_targets_path");
    }

    const qaReport: Record<string, unknown> = {
      schema_version: "v1",
      scene_id: pathInfo.sceneId,
      capture_id: pathInfo.captureId,
      capture_source: captureSource,
      capture_tier_initial:
        asString(manifest?.capture_tier_hint) ??
        (
          captureSource === "iphone"
            ? "tier1_iphone"
            : captureSource === "android"
            ? "tier2_android"
            : "tier2_glasses"
        ),
      capture_tier_final: qualityGate.captureTier,
      processing_profile: qualityGate.processingProfile,
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
      scene_memory_readiness: {
        world_model_candidate: worldModelCandidate,
        recommended_lane: finalStatus === "passed" ? "scene_memory" : "qualification",
        derived_only: true,
        runtime_build_eligible: runtimeBuildEligible,
        runtime_build_blockers: runtimeBuildBlockers,
      },
      identity: identityValidation.identity,
      reasons: finalReasons,
      warnings: finalWarnings,
      generated_at: new Date().toISOString(),
    };

    captureDescriptor.qa_status = finalStatus;
    captureDescriptor.qa_report_uri = qaReportUri;
    captureDescriptor.pipeline_handoff_uri = pipelineHandoffUri;
    const pipelineStatusEvent = buildPipelineStatusEvent({
      bucketName,
      pathInfo,
      objectName,
      objectKind,
      qaStatus: finalStatus,
      pipelineHandoffUri,
    });
    captureDescriptor.pipeline_status_event = pipelineStatusEvent;

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

    const pipelineHandoffPayload = buildPipelineHandoffPayload({
      bucketName,
      pathInfo,
      objectName,
      objectKind,
      manifest,
      captureSource,
      rawCaptureLineage,
      qaStatus: finalStatus,
      routing,
      rawPrefixUri,
      framesIndexUri,
      captureDescriptorUri,
      qaReportUri,
      pipelineHandoffUri,
      keyframeUri,
      pipelineStatusEvent,
      taskSiteContext,
      sceneMemoryCapture,
      captureRights,
      identity: identityValidation.identity,
      worldlabsPreview,
      robotEvalHandoff,
    });

    let handoffMessageId: string;
    try {
      await bucket
        .file(`${pathInfo.capturesPrefix}/pipeline_handoff.json`)
        .save(JSON.stringify(pipelineHandoffPayload, null, 2), {
          contentType: "application/json",
        });
      logger.info("Saved pipeline handoff payload", {
        captureId: pathInfo.captureId,
        sceneId: pathInfo.sceneId,
        pipelineHandoffUri,
        handoffTopic: PIPELINE_HANDOFF_TOPIC,
      });

      handoffMessageId = await publishPipelineHandoffOnce(
        bucket,
        pathInfo.capturesPrefix,
        pipelineHandoffPayload
      );
      logger.info("Published pipeline handoff payload", {
        captureId: pathInfo.captureId,
        sceneId: pathInfo.sceneId,
        handoffTopic: PIPELINE_HANDOFF_TOPIC,
        handoffMessageId,
      });
    } catch (error) {
      logger.error("Pipeline handoff publish failed", {
        captureId: pathInfo.captureId,
        sceneId: pathInfo.sceneId,
        handoffTopic: PIPELINE_HANDOFF_TOPIC,
        pipelineHandoffUri,
        error: error instanceof Error ? error.message : String(error),
      });
      throw error;
    }

    logger.info("Uploaded frames, descriptor, QA report, and pipeline handoff", {
      framesPrefix: pathInfo.framesPrefix,
      frameCount: sortedFiles.length,
      captureId: pathInfo.captureId,
      sceneId: pathInfo.sceneId,
      qaStatus: finalStatus,
      handoffTopic: PIPELINE_HANDOFF_TOPIC,
      handoffMessageId,
    });
  }
);
