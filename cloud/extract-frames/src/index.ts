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
  validateRawCaptureBundleV3,
  type RawCaptureBundleV3ValidationResult,
} from "./raw-contract-v3.js";

const storage = new Storage();
const pubsub = new PubSub();

const PIPELINE_HANDOFF_TOPIC =
  process.env.BLUEPRINT_CAPTURE_PIPELINE_TOPIC ?? "blueprint-capture-pipeline-handoff";

type StorageBucket = ReturnType<typeof storage.bucket>;

type PoseMatchType = "frame_id" | "time";
type CaptureObjectKind = "walkthrough" | "completion_marker" | "other";

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

function parseJsonLines(content: string): Record<string, unknown>[] {
  return content
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
    .flatMap((line) => {
      try {
        const parsed = JSON.parse(line) as Record<string, unknown>;
        return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? [parsed] : [];
      } catch {
        return [];
      }
    });
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
    const rows = parseJsonLines(raw);
    const byFrameId = new Map<string, Record<string, unknown>>();
    for (const row of rows) {
      const frameId = asString(row.frame_id) ?? asString(row.frameId);
      if (frameId) {
        byFrameId.set(frameId, row);
      }
    }
    return byFrameId;
  } catch (error) {
    logger.warn("Failed to load ARKit frame log", { frameLogObjectName, error });
    return new Map();
  }
}

type CapturePathInfo = {
  mode: "scenes" | "targets";
  sceneId: string;
  captureSourcePath: string | null;
  captureId: string;
  scenePrefix: string;
  capturePrefix: string;
  rawPrefix: string;
  framesPrefix: string;
  capturesPrefix: string;
  keyframeObjectName: string;
};

export function parseCapturePath(objectName: string, generation: string): CapturePathInfo | null {
  const parts = objectName.split("/");
  if (
    parts.length >= 6 &&
    parts[0] === "scenes" &&
    parts[2] === "captures" &&
    parts[4] === "raw"
  ) {
    const sceneId = parts[1];
    const captureId = parts[3];
    const scenePrefix = `scenes/${sceneId}`;
    const capturePrefix = `${scenePrefix}/captures/${captureId}`;
    return {
      mode: "scenes",
      sceneId,
      captureSourcePath: null,
      captureId,
      scenePrefix,
      capturePrefix,
      rawPrefix: `${capturePrefix}/raw`,
      framesPrefix: `${capturePrefix}/frames`,
      capturesPrefix: `${scenePrefix}/captures/${captureId}`,
      keyframeObjectName: `${scenePrefix}/images/${captureId}_keyframe.jpg`,
    };
  }
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

async function loadJsonLinesObject(
  bucket: StorageBucket,
  objectName: string,
  tmpDir: string
): Promise<Record<string, unknown>[]> {
  const localPath = join(tmpDir, `jsonl-${Date.now()}-${basename(objectName)}`);
  try {
    await bucket.file(objectName).download({ destination: localPath });
    const raw = readFileSync(localPath, "utf8");
    return parseJsonLines(raw);
  } catch (error) {
    logger.warn("Failed to load JSONL object", { objectName, error });
    return [];
  }
}

async function listRawFilesPresent(bucket: StorageBucket, rawPrefix: string): Promise<Set<string>> {
  const filesPresent = new Set<string>();
  const canonicalPrefix = `${rawPrefix}/`;
  try {
    const [files] = await bucket.getFiles({ prefix: canonicalPrefix });
    for (const file of files) {
      if (!file.name.startsWith(canonicalPrefix)) continue;
      const relativePath = file.name.slice(canonicalPrefix.length);
      if (relativePath.length === 0 || relativePath.endsWith("/")) continue;
      filesPresent.add(relativePath);
    }
  } catch (error) {
    logger.warn("Failed to enumerate raw capture files for V3 validation", { rawPrefix, error });
  }
  return filesPresent;
}

export function mergeManifestWithSidecars(
  manifest: Record<string, unknown> | null,
  sidecars: {
    siteIdentity?: Record<string, unknown> | null;
    captureTopology?: Record<string, unknown> | null;
    captureMode?: Record<string, unknown> | null;
    routeAnchors?: Record<string, unknown> | null;
    checkpointEvents?: Record<string, unknown> | null;
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

function asStringArray(value: unknown): string[] | undefined {
  if (!Array.isArray(value)) return undefined;
  const parsed = value
    .filter((item): item is string => typeof item === "string")
    .map((item) => item.trim())
    .filter((item) => item.length > 0);
  return parsed.length > 0 ? parsed : [];
}

function hasStringArray(value: unknown): boolean {
  return Array.isArray(value) && value.every((item) => typeof item === "string");
}

function captureObjectKind(objectName: string): CaptureObjectKind {
  const fileName = basename(objectName);
  if (fileName === "walkthrough.mov" || fileName === "walkthrough.mp4") return "walkthrough";
  if (fileName === "capture_upload_complete.json") return "completion_marker";
  return "other";
}

export function deriveRequestedRouting(manifest: Record<string, unknown> | null): {
  requestedOutputs: string[];
  requestedLanes: string[];
  previewSimulationRequested: boolean;
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
      default:
        requestedLanes.add(output);
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
  };
}

export function buildWorldlabsPreviewFields(
  bucketName: string,
  pathInfo: CapturePathInfo,
  previewSimulationRequested: boolean
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
      ? gsUri(bucketName, `${pathInfo.rawPrefix}/walkthrough.mov`)
      : null,
  };
}

export function buildTaskSiteContext(manifest: Record<string, unknown> | null): Record<string, unknown> {
  const captureProfile = asRecord(manifest?.capture_profile);
  const environmentVariability = asRecord(manifest?.environment_variability);
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
  };
}

function validateIdentityMapping(input: {
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

  const blockReasons: string[] = [];
  const warnings: string[] = [];

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
  if (!siteSubmissionId) {
    warnings.push("missing_site_submission_id");
  }
  if (!buyerRequestId && !captureJobId) {
    warnings.push("missing_business_request_identifier");
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
      site_submission_id: siteSubmissionId,
      buyer_request_id: buyerRequestId,
      capture_job_id: captureJobId,
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
      preview_simulation_requested:
        payload.preview_simulation_requested === true ? "true" : "false",
    },
  });
  return messageId;
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
    const v3RequiredStrings = [
      "capture_id",
      "coordinate_frame_session_id",
      "app_version",
      "app_build",
      "ios_version",
      "ios_build",
      "hardware_model_identifier",
      "device_model_marketing",
    ];
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
    // V3.1 additive fields: capture_profile_id and capture_capabilities
    if (!asString(manifest.capture_profile_id)) {
      missingRequired.push("capture_profile_id");
    }
    if (!manifest.capture_capabilities || typeof manifest.capture_capabilities !== "object" || Array.isArray(manifest.capture_capabilities)) {
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

function validateRawContractV3OrDefault(input: {
  shouldValidate: boolean;
  manifest: Record<string, unknown> | null;
  provenance: Record<string, unknown> | null;
  rightsConsent: Record<string, unknown> | null;
  captureContext: Record<string, unknown> | null;
  recordingSession: Record<string, unknown> | null;
  captureTopology: Record<string, unknown> | null;
  completionMarker: Record<string, unknown> | null;
  hashes: Record<string, unknown> | null;
  sessionIntrinsics: Record<string, unknown> | null;
  depthManifest: Record<string, unknown> | null;
  confidenceManifest: Record<string, unknown> | null;
  poses: Record<string, unknown>[];
  frames: Record<string, unknown>[];
  frameQuality: Record<string, unknown>[];
  syncMap: Record<string, unknown>[];
  filesPresent: Set<string>;
}): RawCaptureBundleV3ValidationResult {
  if (!input.shouldValidate) {
    return { valid: true, blockers: [], warnings: [] };
  }
  return validateRawCaptureBundleV3({
    manifest: input.manifest,
    provenance: input.provenance,
    rightsConsent: input.rightsConsent,
    captureContext: input.captureContext,
    recordingSession: input.recordingSession,
    captureTopology: input.captureTopology,
    completionMarker: input.completionMarker,
    hashes: input.hashes,
    sessionIntrinsics: input.sessionIntrinsics,
    depthManifest: input.depthManifest,
    confidenceManifest: input.confidenceManifest,
    poses: input.poses,
    frames: input.frames,
    frameQuality: input.frameQuality,
    syncMap: input.syncMap,
    filesPresent: input.filesPresent,
  });
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
    const intrinsicsObjectName = `${pathInfo.rawPrefix}/arkit/intrinsics.json`;

    // Resolve walkthrough video: prefer manifest video_uri, fall back to canonical names
    const manifestExists = await waitForObjectExists(bucket, manifestObjectName, 45000, 3000);
    const rawManifest = manifestExists ? await loadJsonObject(bucket, manifestObjectName, tmp) : null;
    const manifestVideoUri = asString(rawManifest?.video_uri as string | undefined);
    let walkthroughObjectName: string | null = null;
    if (manifestVideoUri && manifestVideoUri.length > 0) {
      // manifest video_uri is relative to the capture root (e.g. "raw/walkthrough.mp4")
      const normalized = manifestVideoUri.replace(/^raw\//, "");
      walkthroughObjectName = `${pathInfo.rawPrefix}/${normalized}`;
      if (!(await fileExists(bucket, walkthroughObjectName))) {
        walkthroughObjectName = null;
      }
    }
    if (!walkthroughObjectName) {
      // Legacy fallback: try .mov then .mp4
      const movPath = `${pathInfo.rawPrefix}/walkthrough.mov`;
      if (await fileExists(bucket, movPath)) {
        walkthroughObjectName = movPath;
      } else {
        const mp4Path = `${pathInfo.rawPrefix}/walkthrough.mp4`;
        if (await fileExists(bucket, mp4Path)) {
          walkthroughObjectName = mp4Path;
        }
      }
    }
    if (!walkthroughObjectName) {
      logger.error("No walkthrough video found", { rawPrefix: pathInfo.rawPrefix });
      return;
    }
    const walkthroughExists = walkthroughObjectName !== null;
    const sidecarSiteIdentity = await loadJsonObject(bucket, siteIdentityObjectName, tmp);
    const sidecarCaptureTopology = await loadJsonObject(bucket, captureTopologyObjectName, tmp);
    const sidecarCaptureMode = await loadJsonObject(bucket, captureModeObjectName, tmp);
    const sidecarRouteAnchors = await loadJsonObject(bucket, routeAnchorsObjectName, tmp);
    const sidecarCheckpointEvents = await loadJsonObject(bucket, checkpointEventsObjectName, tmp);
    const manifest = mergeManifestWithSidecars(rawManifest, {
      siteIdentity: sidecarSiteIdentity,
      captureTopology: sidecarCaptureTopology,
      captureMode: sidecarCaptureMode,
      routeAnchors: sidecarRouteAnchors,
      checkpointEvents: sidecarCheckpointEvents,
    });
    const completionMarker =
      objectKind === "completion_marker"
        ? await loadJsonObject(bucket, completionMarkerObjectName, tmp)
        : null;
    const manifestValidation = validateManifest(manifest);
    const shouldValidateRawContractV3 =
      objectKind === "completion_marker" &&
      (asString(rawManifest?.schema_version) === "v3" ||
        (asString(rawManifest?.capture_schema_version)?.startsWith("3.") ?? false));
    const [
      rawProvenance,
      rawRightsConsent,
      rawCaptureContext,
      rawRecordingSession,
      rawHashes,
      rawSessionIntrinsics,
      rawDepthManifest,
      rawConfidenceManifest,
      rawPoses,
      rawFrames,
      rawFrameQuality,
      rawSyncMap,
      rawFilesPresent,
    ] = shouldValidateRawContractV3
      ? await Promise.all([
          loadJsonObject(bucket, `${pathInfo.rawPrefix}/provenance.json`, tmp),
          loadJsonObject(bucket, `${pathInfo.rawPrefix}/rights_consent.json`, tmp),
          loadJsonObject(bucket, `${pathInfo.rawPrefix}/capture_context.json`, tmp),
          loadJsonObject(bucket, `${pathInfo.rawPrefix}/recording_session.json`, tmp),
          loadJsonObject(bucket, `${pathInfo.rawPrefix}/hashes.json`, tmp),
          loadJsonObject(bucket, `${pathInfo.rawPrefix}/arkit/session_intrinsics.json`, tmp),
          loadJsonObject(bucket, `${pathInfo.rawPrefix}/arkit/depth_manifest.json`, tmp),
          loadJsonObject(bucket, `${pathInfo.rawPrefix}/arkit/confidence_manifest.json`, tmp),
          loadJsonLinesObject(bucket, `${pathInfo.rawPrefix}/arkit/poses.jsonl`, tmp),
          loadJsonLinesObject(bucket, `${pathInfo.rawPrefix}/arkit/frames.jsonl`, tmp),
          loadJsonLinesObject(bucket, `${pathInfo.rawPrefix}/arkit/frame_quality.jsonl`, tmp),
          loadJsonLinesObject(bucket, `${pathInfo.rawPrefix}/sync_map.jsonl`, tmp),
          listRawFilesPresent(bucket, pathInfo.rawPrefix),
        ])
      : [
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          [],
          [],
          [],
          [],
          new Set<string>(),
        ];
    const rawContractV3Validation = validateRawContractV3OrDefault({
      shouldValidate: shouldValidateRawContractV3,
      manifest: rawManifest,
      provenance: rawProvenance,
      rightsConsent: rawRightsConsent,
      captureContext: rawCaptureContext,
      recordingSession: rawRecordingSession,
      captureTopology: sidecarCaptureTopology,
      completionMarker,
      hashes: rawHashes,
      sessionIntrinsics: rawSessionIntrinsics,
      depthManifest: rawDepthManifest,
      confidenceManifest: rawConfidenceManifest,
      poses: rawPoses,
      frames: rawFrames,
      frameQuality: rawFrameQuality,
      syncMap: rawSyncMap,
      filesPresent: rawFilesPresent,
    });

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
    const captureSource: "iphone" | "android" | "glasses" | "unknown" =
      captureSourceRaw === "iphone"
        ? "iphone"
        : captureSourceRaw === "android" || captureSourceRaw === "android_phone"
        ? "android"
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
    const finalWarnings = [
      ...manifestValidation.warnings,
      ...qualityGate.warnings,
      ...rawContractV3Validation.warnings.map((warning) => `raw_contract_v3:${warning}`),
    ];
    let finalStatus = qualityGate.status;
    if (!rawContractV3Validation.valid) {
      finalStatus = "blocked";
      finalReasons.push(...rawContractV3Validation.blockers.map((blocker) => `raw_contract_v3:${blocker}`));
    }

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
    const routeAnchors = normalizedRouteAnchors(manifest);
    const checkpointEvents = normalizedCheckpointEvents(manifest);
    // worldModelCandidate is computed AFTER actualAvailability is known (see below).
    const routing = deriveRequestedRouting(manifest);
    const taskSiteContext = buildTaskSiteContext(manifest);
    const worldlabsPreview = buildWorldlabsPreviewFields(
      bucketName,
      pathInfo,
      routing.previewSimulationRequested
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
    const deferGeometry =
      captureSource !== "iphone" &&
      requestedMode === "site_world_candidate" &&
      captureRights.derived_scene_generation_allowed === true;
    const resolvedMode =
      worldModelCandidate || deferGeometry ? "site_world_candidate" : "qualification_only";
    const captureMode = {
      requested_mode: requestedMode,
      resolved_mode: resolvedMode,
      downgrade_reason:
        requestedMode === "site_world_candidate" && resolvedMode === "qualification_only"
          ? "awaiting_geometry_stage"
          : null,
      geometry_status: deferGeometry && !worldModelCandidate ? "awaiting_geometry_stage" : null,
    };

    const runtimeBuildBlockers = [
      ...(captureSource === "iphone" ? [] : ["geometry_ready=false"]),
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
      capture_profile_id: asString(manifest?.capture_profile_id) ?? null,
      capture_capabilities: manifest?.capture_capabilities ?? {},
      capture_tier: qualityGate.captureTier,
      processing_profile: qualityGate.processingProfile,
      raw_prefix_uri: rawPrefixUri,
      frames_index_uri: framesIndexUri,
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
      site_identity: siteIdentity,
      capture_topology: captureTopology,
      route_anchors: routeAnchors,
      checkpoint_events: checkpointEvents,
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
        site_identity: siteIdentity,
        capture_topology: captureTopology,
        route_anchors: routeAnchors,
        checkpoint_events: checkpointEvents,
        capture_mode: captureMode,
      },
      ...worldlabsPreview,
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
      raw_contract_v3_validation: {
        validated: shouldValidateRawContractV3,
        valid: rawContractV3Validation.valid,
        blockers: rawContractV3Validation.blockers,
        warnings: rawContractV3Validation.warnings,
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

    const pipelineHandoffPayload: Record<string, unknown> = {
      schema_version: "v1",
      handoff_source: "BlueprintCapture.extractFrames",
      handoff_topic: PIPELINE_HANDOFF_TOPIC,
      handoff_trigger_object: objectName,
      handoff_trigger_kind: objectKind,
      scene_id: pathInfo.sceneId,
      capture_id: pathInfo.captureId,
      site_submission_id: asString(manifest?.site_submission_id) ?? null,
      buyer_request_id: asString(manifest?.buyer_request_id) ?? null,
      capture_job_id: asString(manifest?.capture_job_id) ?? null,
      region_id: asString(manifest?.region_id) ?? null,
      rights_profile: asString(manifest?.rights_profile) ?? null,
      capture_source: captureSource,
      qa_status: finalStatus,
      requested_outputs: routing.requestedOutputs,
      requested_lanes: routing.requestedLanes,
      raw_prefix_uri: rawPrefixUri,
      frames_index_uri: framesIndexUri,
      capture_descriptor_uri: captureDescriptorUri,
      qa_report_uri: qaReportUri,
      keyframe_uri: keyframeUri,
      task_site_context: taskSiteContext,
      scene_memory_capture: sceneMemoryCapture,
      capture_rights: captureRights,
      identity: identityValidation.identity,
      ...worldlabsPreview,
      generated_at: new Date().toISOString(),
    };

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

      handoffMessageId = await publishPipelineHandoff(pipelineHandoffPayload);
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
