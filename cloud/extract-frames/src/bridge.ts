import { parseStrictJsonLines } from "./jsonl.js";
import { createHash } from "node:crypto";

export type PoseRow = {
  pose_schema_version?: string;
  frame_id?: string;
  t_device_sec?: number;
  t_monotonic_ns?: number;
  T_world_camera?: number[][];
  frameIndex?: number;
  frame_index?: number;
  timestamp?: number;
  transform?: number[][];
  source_schema: "v2" | "legacy" | "mixed";
};

export type PoseIndex = {
  byFrameId: Map<string, PoseRow>;
  byTime: PoseRow[];
};

export type VideoSyncRow = {
  frame_id: string;
  pose_frame_id?: string;
  encoded_frame_index?: number;
  t_video_sec: number;
  t_capture_sec?: number;
  sync_status?: string;
  delta_ms?: number;
};

export type VideoSyncIndex = {
  byVideoTime: VideoSyncRow[];
};

export type DownstreamCandidate = {
  candidate_id: string;
  decoded_frame_ordinal: number;
  encoded_frame_index: number;
  frame_id: string;
  pose_frame_id: string;
  decoded_pts_sec: number;
  output_image_relative_path: string;
};

export type DownstreamCandidateIndex = {
  valid: boolean;
  errors: string[];
  manifestDigest?: string;
  byDecodedFrameOrdinal: Map<number, DownstreamCandidate>;
};

export type VideoSyncAssociation = {
  match: "exact_retained_observation" | "approximate_nearest_retained_observation";
  deltaMs: number;
};

export type QualityGateInput = {
  captureSource: "iphone" | "android" | "glasses" | "unknown";
  manifestPresent: boolean;
  manifestValid: boolean;
  requiredFiles: {
    walkthrough: boolean;
    manifest: boolean;
  };
  frameCount: number;
  poseMatchRate: number;
  p95PoseDeltaSec: number | null;
};

export type QualityGateResult = {
  status: "passed" | "blocked";
  captureTier: "tier1_iphone" | "tier2_android" | "tier2_glasses";
  processingProfile: "pose_assisted" | "video_only";
  reasons: string[];
  warnings: string[];
};

export type ArtifactAvailability = {
  arkit_poses: boolean;
  arkit_intrinsics: boolean;
  arkit_depth: boolean;
  arkit_confidence: boolean;
  arkit_meshes: boolean;
  motion: boolean;
  video_sync?: boolean;
  arkit_frames?: boolean;
  arkit_frame_quality?: boolean;
  arkit_feature_points?: boolean;
  arkit_planes?: boolean;
  arkit_light_estimates?: boolean;
  camera_pose?: boolean;
  camera_intrinsics?: boolean;
  depth?: boolean;
  depth_confidence?: boolean;
  point_cloud?: boolean;
  planes?: boolean;
  tracking_state?: boolean;
  light_estimate?: boolean;
  geospatial?: boolean;
  companion_phone_pose?: boolean;
  companion_phone_intrinsics?: boolean;
  companion_phone_calibration?: boolean;
};

export type ClaimedArtifactEvaluation = {
  valid: ArtifactAvailability;
  blockers: string[];
  warnings: string[];
};

function toFiniteNumber(value: unknown): number | undefined {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    return undefined;
  }
  return value;
}

function toMatrix(value: unknown): number[][] | undefined {
  if (!Array.isArray(value)) return undefined;
  const matrix: number[][] = [];
  for (const row of value) {
    if (!Array.isArray(row)) return undefined;
    const parsedRow: number[] = [];
    for (const col of row) {
      const numeric = toFiniteNumber(col);
      if (numeric === undefined) return undefined;
      parsedRow.push(numeric);
    }
    matrix.push(parsedRow);
  }
  return matrix;
}

export function zeroPad(n: number, width: number): string {
  const s = String(n);
  return s.length >= width ? s : "0".repeat(width - s.length) + s;
}

export function parsePoseRows(content: string): PoseRow[] {
  const rows = parseStrictJsonLines(content, "arkit/poses.jsonl");

  const legacyTimestampRows = rows
    .map((row) => ({
      timestamp: toFiniteNumber(row.timestamp),
      tDeviceSec: toFiniteNumber(row.t_device_sec),
    }))
    .filter((row) => row.timestamp !== undefined && row.tDeviceSec === undefined)
    .map((row) => row.timestamp as number);
  const legacyBaseTimestamp = legacyTimestampRows.length > 0 ? legacyTimestampRows[0] : undefined;

  return rows.map((row) => {
    const frameIdRaw = typeof row.frame_id === "string" ? row.frame_id : undefined;
    const frameIndexRaw = toFiniteNumber(row.frame_index ?? row.frameIndex);
    const frameId =
      frameIdRaw ??
      (frameIndexRaw !== undefined ? zeroPad(Math.max(0, Math.floor(frameIndexRaw)) + 1, 6) : undefined);

    const tDeviceSecRaw = toFiniteNumber(row.t_device_sec);
    const timestampRaw = toFiniteNumber(row.timestamp);
    let tDeviceSec = tDeviceSecRaw;
    if (tDeviceSec === undefined && timestampRaw !== undefined && legacyBaseTimestamp !== undefined) {
      tDeviceSec = Math.max(0, timestampRaw - legacyBaseTimestamp);
    }

    const worldCamera =
      toMatrix(row.T_world_camera) ??
      toMatrix(row.transform);
    const poseSchemaVersion =
      typeof row.pose_schema_version === "string" ? row.pose_schema_version : undefined;

    let sourceSchema: "v2" | "legacy" | "mixed" = "legacy";
    if (
      frameIdRaw !== undefined ||
      tDeviceSecRaw !== undefined ||
      toMatrix(row.T_world_camera) !== undefined ||
      poseSchemaVersion !== undefined
    ) {
      sourceSchema = "v2";
    }
    if (
      frameIndexRaw !== undefined ||
      timestampRaw !== undefined ||
      toMatrix(row.transform) !== undefined
    ) {
      sourceSchema = sourceSchema === "v2" ? "mixed" : "legacy";
    }

    return {
      pose_schema_version: poseSchemaVersion ?? (sourceSchema === "legacy" ? "legacy" : "2.0"),
      frame_id: frameId,
      t_device_sec: tDeviceSec !== undefined ? Number(tDeviceSec.toFixed(6)) : undefined,
      T_world_camera: worldCamera,
      frameIndex: frameIndexRaw !== undefined ? Math.floor(frameIndexRaw) : undefined,
      timestamp: timestampRaw,
      transform: toMatrix(row.transform),
      source_schema: sourceSchema,
    };
  });
}

export function buildPoseIndex(rows: PoseRow[]): PoseIndex {
  const byFrameId = new Map<string, PoseRow>();
  const byTime: PoseRow[] = [];
  for (const row of rows) {
    if (typeof row.frame_id === "string" && row.frame_id.length > 0) {
      byFrameId.set(row.frame_id, row);
    }
    if (typeof row.t_device_sec === "number" && Number.isFinite(row.t_device_sec)) {
      byTime.push(row);
    }
  }
  byTime.sort((a, b) => (a.t_device_sec ?? 0) - (b.t_device_sec ?? 0));
  return { byFrameId, byTime };
}

export function parseVideoSyncRows(content: string): VideoSyncRow[] {
  return parseStrictJsonLines(content, "sync_map.jsonl").flatMap((row) => {
    const frameId = typeof row.frame_id === "string" ? row.frame_id : undefined;
    const tVideoSec = toFiniteNumber(row.t_video_sec);
    if (!frameId || tVideoSec === undefined) return [];
    return [{
      frame_id: frameId,
      pose_frame_id: typeof row.pose_frame_id === "string" ? row.pose_frame_id : undefined,
      encoded_frame_index: toFiniteNumber(row.encoded_frame_index),
      t_video_sec: tVideoSec,
      t_capture_sec: toFiniteNumber(row.t_capture_sec),
      sync_status: typeof row.sync_status === "string" ? row.sync_status : undefined,
      delta_ms: toFiniteNumber(row.delta_ms),
    }];
  });
}

export function buildVideoSyncIndex(rows: VideoSyncRow[]): VideoSyncIndex {
  return {
    byVideoTime: rows
      .filter((row) => Number.isFinite(row.t_video_sec))
      .sort((a, b) => a.t_video_sec - b.t_video_sec),
  };
}

export function findClosestVideoSyncByTime(
  rows: VideoSyncRow[],
  targetTime: number
): VideoSyncRow | undefined {
  if (!rows.length) return undefined;
  let low = 0;
  let high = rows.length - 1;
  while (low < high) {
    const mid = Math.floor((low + high) / 2);
    if (rows[mid].t_video_sec < targetTime) low = mid + 1;
    else high = mid;
  }
  const candidates = [rows[low], low > 0 ? rows[low - 1] : undefined].filter(
    (row): row is VideoSyncRow => row !== undefined
  );
  return candidates.reduce((best, candidate) =>
    Math.abs(candidate.t_video_sec - targetTime) < Math.abs(best.t_video_sec - targetTime)
      ? candidate
      : best
  );
}

export function classifyVideoSyncAssociation(
  row: VideoSyncRow,
  targetTime: number,
  toleranceSec = 0.0001
): VideoSyncAssociation {
  const deltaMs = Number((Math.abs(row.t_video_sec - targetTime) * 1000).toFixed(3));
  return {
    match:
      row.sync_status === "encoded_decoded_pts_match" && deltaMs <= toleranceSec * 1000
        ? "exact_retained_observation"
        : "approximate_nearest_retained_observation",
    deltaMs,
  };
}

function canonicalJson(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  if (value && typeof value === "object") {
    const object = value as Record<string, unknown>;
    return `{${Object.keys(object)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${canonicalJson(object[key])}`)
      .join(",")}}`;
  }
  return JSON.stringify(value) ?? "null";
}

function safeRelativePath(value: string): boolean {
  return (
    value.length > 0 &&
    !value.startsWith("/") &&
    !value.includes("\\") &&
    value.split("/").every((part) => part.length > 0 && part !== "." && part !== "..")
  );
}

function validMatrix4(value: unknown): boolean {
  return Array.isArray(value) && value.length === 4 && value.every(
    (row) => Array.isArray(row) && row.length === 4 && row.every(
      (entry) => typeof entry === "number" && Number.isFinite(entry)
    )
  );
}

export function buildDownstreamCandidateIndex(
  manifest: Record<string, unknown> | null
): DownstreamCandidateIndex {
  const errors: string[] = [];
  const byDecodedFrameOrdinal = new Map<number, DownstreamCandidate>();
  if (!manifest) {
    return { valid: false, errors: ["downstream_candidate_manifest_missing"], byDecodedFrameOrdinal };
  }
  if (manifest.schema_version !== "downstream_candidate_manifest.v1") {
    errors.push("downstream_candidate_manifest_schema_invalid");
  }
  const digest = typeof manifest.manifest_digest === "string" ? manifest.manifest_digest : undefined;
  const withoutDigest = { ...manifest };
  delete withoutDigest.manifest_digest;
  const computed = `sha256:${createHash("sha256").update(canonicalJson(withoutDigest)).digest("hex")}`;
  if (digest !== computed) errors.push("downstream_candidate_manifest_digest_mismatch");
  if (
    typeof manifest.source_video_uri !== "string" ||
    !/^[0-9a-f]{64}$/.test(String(manifest.source_video_sha256 ?? "")) ||
    manifest.source_video_authority !== "immutable_raw_capture_video" ||
    manifest.decoded_timing_authority !==
      "sync_map_decoded_sample_presentation_timestamps" ||
    manifest.candidate_order !== "encoded_frame_index_ascending"
  ) {
    errors.push("downstream_candidate_source_contract_invalid");
  }

  const selection = manifest.selection_contract as Record<string, unknown> | undefined;
  if (
    selection?.selection_authority !== "blueprint_pipeline_task_site_profile" ||
    selection?.capture_default_selection !== null ||
    selection?.selection_parameters_required !== true ||
    canonicalJson(selection?.allowed_deterministic_selectors) !== canonicalJson([
      "explicit_encoded_frame_ordinals",
      "profile_bound_even_decoded_pts_coverage",
      "profile_bound_quality_filter",
    ]) ||
    selection?.smallest_missing_input_when_unselectable !==
      "task_site_evidence_profile_with_frame_selection_parameters"
  ) {
    errors.push("downstream_candidate_selection_contract_invalid");
  }

  const neutrality = manifest.provider_neutrality as Record<string, unknown> | undefined;
  if (
    neutrality?.mobile_app_direct_provider_upload_allowed !== false ||
    neutrality?.third_party_provider_upload_authorized !== false ||
    neutrality?.provider_selection_authority !== "blueprint_pipeline" ||
    neutrality?.provider_authorization_status !== "not_granted_by_capture_manifest" ||
    neutrality?.provider_selected !== undefined
  ) {
    errors.push("downstream_candidate_provider_neutrality_invalid");
  }
  const allowedUse = manifest.allowed_use_scope as Record<string, unknown> | undefined;
  if (
    allowedUse?.raw_observation_indexing_allowed !== true ||
    typeof allowedUse?.derived_processing_allowed !== "boolean" ||
    typeof allowedUse?.data_licensing_allowed !== "boolean" ||
    allowedUse?.redaction_required_before_derived_use !== true ||
    allowedUse?.latest_revocation_check_required !== true ||
    allowedUse?.provider_upload_requires_separate_downstream_authorization !== true
  ) {
    errors.push("downstream_candidate_use_scope_invalid");
  }
  const claimBoundary = manifest.claim_boundary as Record<string, unknown> | undefined;
  if (
    claimBoundary?.raw_capture_remains_authoritative !== true ||
    claimBoundary?.candidate_manifest_qualifies_reconstruction !== false ||
    claimBoundary?.candidate_manifest_qualifies_metric_scale !== false ||
    claimBoundary?.candidate_manifest_qualifies_collision_or_physics !== false ||
    claimBoundary?.candidate_manifest_proves_task_success !== false
  ) {
    errors.push("downstream_candidate_claim_boundary_invalid");
  }
  const rows = Array.isArray(manifest.candidates) ? manifest.candidates : [];
  if (manifest.candidate_count !== rows.length) {
    errors.push("downstream_candidate_count_mismatch");
  }
  for (const [ordinal, raw] of rows.entries()) {
    const row = raw && typeof raw === "object" && !Array.isArray(raw)
      ? (raw as Record<string, unknown>)
      : {};
    const candidateId = typeof row.candidate_id === "string" ? row.candidate_id : "";
    const decodedOrdinal = toFiniteNumber(row.decoded_frame_ordinal);
    const encodedIndex = toFiniteNumber(row.encoded_frame_index);
    const frameId = typeof row.frame_id === "string" ? row.frame_id : "";
    const poseFrameId = typeof row.pose_frame_id === "string" ? row.pose_frame_id : "";
    const decodedPts = toFiniteNumber(row.decoded_pts_sec);
    const outputPath = typeof row.output_image_relative_path === "string"
      ? row.output_image_relative_path
      : "";
    const intrinsics = row.camera_intrinsics && typeof row.camera_intrinsics === "object"
      && !Array.isArray(row.camera_intrinsics)
      ? (row.camera_intrinsics as Record<string, unknown>)
      : undefined;
    const calibrationDigest = intrinsics
      ? `sha256:${createHash("sha256").update(canonicalJson(intrinsics)).digest("hex")}`
      : undefined;
    if (
      candidateId !== `rgb_${ordinal.toString().padStart(6, "0")}` ||
      decodedOrdinal !== ordinal ||
      encodedIndex !== ordinal ||
      !frameId ||
      !poseFrameId ||
      decodedPts === undefined ||
      outputPath !== `candidate_rgb/${ordinal.toString().padStart(6, "0")}.png` ||
      !safeRelativePath(outputPath) ||
      row.source_video_uri !== manifest.source_video_uri ||
      row.coordinate_frame_session_id !== manifest.coordinate_frame_session_id ||
      row.site_frame_id !== manifest.coordinate_frame_session_id ||
      row.site_frame_definition !== "arkit_world_origin_at_session_start" ||
      row.transform_semantics !== "row_major_camera_to_site" ||
      row.units !== "meters" ||
      row.handedness !== "right_handed" ||
      row.up_axis !== "Y" ||
      row.gravity_aligned !== true ||
      !validMatrix4(row.T_site_camera) ||
      !validMatrix4(row.T_world_camera) ||
      canonicalJson(row.T_site_camera) !== canonicalJson(row.T_world_camera) ||
      intrinsics?.authority !== "arkit_arframe_exact_per_observation" ||
      !Array.isArray(intrinsics?.matrix_column_major) ||
      intrinsics.matrix_column_major.length !== 9 ||
      row.camera_calibration_digest !== calibrationDigest ||
      row.raw_observation_authority !== true ||
      row.downstream_artifact_authority !== false ||
      byDecodedFrameOrdinal.has(ordinal)
    ) {
      errors.push(`downstream_candidate_row_invalid:${ordinal}`);
      continue;
    }
    byDecodedFrameOrdinal.set(ordinal, {
      candidate_id: candidateId,
      decoded_frame_ordinal: ordinal,
      encoded_frame_index: ordinal,
      frame_id: frameId,
      pose_frame_id: poseFrameId,
      decoded_pts_sec: decodedPts,
      output_image_relative_path: outputPath,
    });
  }
  return { valid: errors.length === 0, errors, manifestDigest: digest, byDecodedFrameOrdinal };
}

export function findClosestPoseByTime(poses: PoseRow[], targetTime: number): PoseRow | undefined {
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

export function percentile(values: number[], p: number): number | null {
  if (!values.length) return null;
  if (p <= 0) return Math.min(...values);
  if (p >= 100) return Math.max(...values);
  const sorted = [...values].sort((a, b) => a - b);
  const rank = (p / 100) * (sorted.length - 1);
  const low = Math.floor(rank);
  const high = Math.ceil(rank);
  if (low === high) return sorted[low];
  const weight = rank - low;
  return sorted[low] * (1 - weight) + sorted[high] * weight;
}

export function chooseKeyframeCandidate(
  frameFiles: string[],
  getFileSize: (fileName: string) => number
): { fileName: string; sharpnessScore: number; candidateCount: number } | undefined {
  if (frameFiles.length === 0) return undefined;
  const sorted = [...frameFiles].sort();
  const middleStart = Math.floor(sorted.length / 3);
  const middleEnd = Math.max(middleStart + 1, Math.ceil((2 * sorted.length) / 3));
  const candidates = sorted.slice(middleStart, middleEnd);
  const center = (middleStart + middleEnd - 1) / 2;

  let bestName = candidates[0];
  let bestScore = getFileSize(bestName);
  let bestDistance = Math.abs(sorted.indexOf(bestName) - center);

  for (const name of candidates.slice(1)) {
    const score = getFileSize(name);
    const distance = Math.abs(sorted.indexOf(name) - center);
    if (score > bestScore || (score === bestScore && distance < bestDistance)) {
      bestName = name;
      bestScore = score;
      bestDistance = distance;
    }
  }

  return {
    fileName: bestName,
    sharpnessScore: bestScore,
    candidateCount: candidates.length,
  };
}

export function evaluateQualityGate(input: QualityGateInput): QualityGateResult {
  const reasons: string[] = [];
  const warnings: string[] = [];

  if (!input.requiredFiles.walkthrough) {
    reasons.push("missing_walkthrough");
  }
  if (!input.requiredFiles.manifest || !input.manifestPresent) {
    reasons.push("missing_manifest");
  }
  if (input.manifestPresent && !input.manifestValid) {
    reasons.push("invalid_manifest");
  }
  if (input.frameCount < 3) {
    reasons.push("insufficient_frame_count");
  }

  if (reasons.length > 0) {
    return {
      status: "blocked",
      captureTier:
        input.captureSource === "iphone"
          ? "tier1_iphone"
          : input.captureSource === "android"
          ? "tier2_android"
          : "tier2_glasses",
      processingProfile: input.captureSource === "iphone" ? "pose_assisted" : "video_only",
      reasons,
      warnings,
    };
  }

  if (input.captureSource === "iphone") {
    const p95 = input.p95PoseDeltaSec ?? Number.POSITIVE_INFINITY;
    if (input.poseMatchRate >= 0.65 && p95 <= 0.2) {
      return {
        status: "passed",
        captureTier: "tier1_iphone",
        processingProfile: "pose_assisted",
        reasons,
        warnings,
      };
    }

    warnings.push("insufficient_arkit_alignment_demoted_to_tier2");
    if (input.poseMatchRate === 0) {
      warnings.push("no_pose_matches_detected");
    }
    return {
      status: "passed",
      captureTier: "tier2_glasses",
      processingProfile: "video_only",
      reasons,
      warnings,
    };
  }

  if (input.captureSource === "unknown") {
    warnings.push("unknown_capture_source_defaulted_to_tier2");
  }
  return {
    status: "passed",
    captureTier: input.captureSource === "android" ? "tier2_android" : "tier2_glasses",
    processingProfile: "video_only",
    reasons,
    warnings,
  };
}

export function evaluateClaimedArtifacts(input: {
  claimed: ArtifactAvailability;
  actual: ArtifactAvailability;
}): ClaimedArtifactEvaluation {
  const blockers: string[] = [];
  const warnings: string[] = [];
  const valid: ArtifactAvailability = {
    arkit_poses: input.claimed.arkit_poses === true && input.actual.arkit_poses === true,
    arkit_intrinsics: input.claimed.arkit_intrinsics === true && input.actual.arkit_intrinsics === true,
    arkit_depth: input.claimed.arkit_depth === true && input.actual.arkit_depth === true,
    arkit_confidence: input.claimed.arkit_confidence === true && input.actual.arkit_confidence === true,
    arkit_meshes: input.claimed.arkit_meshes === true && input.actual.arkit_meshes === true,
    motion: input.claimed.motion === true && input.actual.motion === true,
    video_sync: input.claimed.video_sync === true && input.actual.video_sync === true,
    arkit_frames: input.claimed.arkit_frames === true && input.actual.arkit_frames === true,
    arkit_frame_quality:
      input.claimed.arkit_frame_quality === true && input.actual.arkit_frame_quality === true,
    arkit_feature_points:
      input.claimed.arkit_feature_points === true && input.actual.arkit_feature_points === true,
    arkit_planes: input.claimed.arkit_planes === true && input.actual.arkit_planes === true,
    arkit_light_estimates:
      input.claimed.arkit_light_estimates === true && input.actual.arkit_light_estimates === true,
    camera_pose: input.claimed.camera_pose === true && input.actual.camera_pose === true,
    camera_intrinsics:
      input.claimed.camera_intrinsics === true && input.actual.camera_intrinsics === true,
    depth: input.claimed.depth === true && input.actual.depth === true,
    depth_confidence:
      input.claimed.depth_confidence === true && input.actual.depth_confidence === true,
    point_cloud: input.claimed.point_cloud === true && input.actual.point_cloud === true,
    planes: input.claimed.planes === true && input.actual.planes === true,
    tracking_state: input.claimed.tracking_state === true && input.actual.tracking_state === true,
    light_estimate: input.claimed.light_estimate === true && input.actual.light_estimate === true,
    geospatial: input.claimed.geospatial === true && input.actual.geospatial === true,
    companion_phone_pose:
      input.claimed.companion_phone_pose === true && input.actual.companion_phone_pose === true,
    companion_phone_intrinsics:
      input.claimed.companion_phone_intrinsics === true &&
      input.actual.companion_phone_intrinsics === true,
    companion_phone_calibration:
      input.claimed.companion_phone_calibration === true &&
      input.actual.companion_phone_calibration === true,
  };

  if (input.claimed.arkit_poses && !input.actual.arkit_poses) {
    blockers.push("claimed_arkit_poses_missing_or_empty");
  }
  if (input.claimed.arkit_intrinsics && !input.actual.arkit_intrinsics) {
    blockers.push("claimed_arkit_intrinsics_invalid");
  }
  if (input.claimed.arkit_depth && !input.actual.arkit_depth) {
    warnings.push("claimed_arkit_depth_missing_or_empty");
  }
  if (input.claimed.arkit_confidence && !input.actual.arkit_confidence) {
    warnings.push("claimed_arkit_confidence_missing_or_empty");
  }
  if (input.claimed.arkit_meshes && !input.actual.arkit_meshes) {
    warnings.push("claimed_arkit_meshes_missing_or_empty");
  }
  if (input.claimed.motion && !input.actual.motion) {
    warnings.push("claimed_motion_missing_or_empty");
  }
  if (input.claimed.video_sync && !input.actual.video_sync) {
    blockers.push("claimed_video_sync_missing_or_empty");
  }
  if (input.claimed.arkit_frames && !input.actual.arkit_frames) {
    blockers.push("claimed_arkit_frames_missing_or_empty");
  }
  if (input.claimed.arkit_frame_quality && !input.actual.arkit_frame_quality) {
    warnings.push("claimed_arkit_frame_quality_missing_or_empty");
  }
  if (input.claimed.arkit_feature_points && !input.actual.arkit_feature_points) {
    warnings.push("claimed_arkit_feature_points_missing_or_empty");
  }
  if (input.claimed.arkit_planes && !input.actual.arkit_planes) {
    warnings.push("claimed_arkit_planes_missing_or_empty");
  }
  if (input.claimed.arkit_light_estimates && !input.actual.arkit_light_estimates) {
    warnings.push("claimed_arkit_light_estimates_missing_or_empty");
  }
  if (input.claimed.camera_pose && !input.actual.camera_pose) {
    blockers.push("claimed_camera_pose_missing_or_empty");
  }
  if (input.claimed.camera_intrinsics && !input.actual.camera_intrinsics) {
    blockers.push("claimed_camera_intrinsics_invalid");
  }
  if (input.claimed.depth && !input.actual.depth) {
    warnings.push("claimed_depth_missing_or_empty");
  }
  if (input.claimed.depth_confidence && !input.actual.depth_confidence) {
    warnings.push("claimed_depth_confidence_missing_or_empty");
  }
  if (input.claimed.point_cloud && !input.actual.point_cloud) {
    warnings.push("claimed_point_cloud_missing_or_empty");
  }
  if (input.claimed.planes && !input.actual.planes) {
    warnings.push("claimed_planes_missing_or_empty");
  }
  if (input.claimed.tracking_state && !input.actual.tracking_state) {
    warnings.push("claimed_tracking_state_missing_or_empty");
  }
  if (input.claimed.light_estimate && !input.actual.light_estimate) {
    warnings.push("claimed_light_estimate_missing_or_empty");
  }
  if (input.claimed.geospatial && !input.actual.geospatial) {
    blockers.push("claimed_geospatial_missing_or_empty");
  }
  if (input.claimed.companion_phone_pose && !input.actual.companion_phone_pose) {
    warnings.push("claimed_companion_phone_pose_missing_or_empty");
  }
  if (
    input.claimed.companion_phone_intrinsics &&
    !input.actual.companion_phone_intrinsics
  ) {
    warnings.push("claimed_companion_phone_intrinsics_missing_or_invalid");
  }
  if (
    input.claimed.companion_phone_calibration &&
    !input.actual.companion_phone_calibration
  ) {
    warnings.push("claimed_companion_phone_calibration_missing");
  }

  return { valid, blockers, warnings };
}

export function buildCaptureBundleReferences(input: {
  bucketName: string;
  rawPrefix: string;
  availability: ArtifactAvailability;
  declaredReferences?: {
    reconstructionQualificationRequest?: boolean;
    deviceCalibration?: boolean;
    downstreamCandidateManifest?: boolean;
  };
}): Record<string, unknown> {
  const base = `gs://${input.bucketName}/${input.rawPrefix}`;
  const captureBundle: Record<string, unknown> = {
    artifact_validity: input.availability,
  };

  if (input.availability.arkit_poses) {
    captureBundle.arkit_poses_uri = `${base}/arkit/poses.jsonl`;
  }
  if (input.availability.video_sync) {
    captureBundle.sync_map_uri = `${base}/sync_map.jsonl`;
    captureBundle.video_frame_retention_uri = `${base}/video_frame_retention.jsonl`;
  }
  if (input.availability.arkit_frames) {
    captureBundle.arkit_frames_uri = `${base}/arkit/frames.jsonl`;
  }
  if (input.availability.arkit_frame_quality) {
    captureBundle.arkit_frame_quality_uri = `${base}/arkit/frame_quality.jsonl`;
  }
  if (input.availability.arkit_feature_points) {
    captureBundle.arkit_feature_points_uri = `${base}/arkit/feature_points.jsonl`;
  }
  if (input.availability.arkit_planes) {
    captureBundle.arkit_plane_observations_uri = `${base}/arkit/plane_observations.jsonl`;
  }
  if (input.availability.arkit_light_estimates) {
    captureBundle.arkit_light_estimates_uri = `${base}/arkit/light_estimates.jsonl`;
  }
  if (input.availability.arkit_intrinsics) {
    captureBundle.arkit_intrinsics_uri = `${base}/arkit/intrinsics.json`;
  }
  if (input.availability.arkit_depth) {
    captureBundle.arkit_depth_prefix_uri = `${base}/arkit/depth`;
  }
  if (input.availability.arkit_confidence) {
    captureBundle.arkit_confidence_prefix_uri = `${base}/arkit/confidence`;
  }
  if (input.availability.arkit_meshes) {
    captureBundle.arkit_meshes_prefix_uri = `${base}/arkit/meshes`;
    captureBundle.arkit_mesh_manifest_uri = `${base}/arkit/mesh_manifest.json`;
  }
  if (input.availability.motion) {
    captureBundle.motion_uri = `${base}/motion.jsonl`;
  }
  if (input.availability.camera_pose) {
    captureBundle.arcore_poses_uri = `${base}/arcore/poses.jsonl`;
    captureBundle.arcore_frames_uri = `${base}/arcore/frames.jsonl`;
  }
  if (input.availability.camera_intrinsics) {
    captureBundle.arcore_intrinsics_uri = `${base}/arcore/session_intrinsics.json`;
  }
  if (input.availability.depth) {
    captureBundle.arcore_depth_manifest_uri = `${base}/arcore/depth_manifest.json`;
    captureBundle.arcore_depth_prefix_uri = `${base}/arcore/depth`;
  }
  if (input.availability.depth_confidence) {
    captureBundle.arcore_confidence_manifest_uri = `${base}/arcore/confidence_manifest.json`;
    captureBundle.arcore_confidence_prefix_uri = `${base}/arcore/confidence`;
  }
  if (input.availability.point_cloud) {
    captureBundle.arcore_point_cloud_uri = `${base}/arcore/point_cloud.jsonl`;
  }
  if (input.availability.planes) {
    captureBundle.arcore_planes_uri = `${base}/arcore/planes.jsonl`;
  }
  if (input.availability.tracking_state) {
    captureBundle.arcore_tracking_state_uri = `${base}/arcore/tracking_state.jsonl`;
  }
  if (input.availability.light_estimate) {
    captureBundle.arcore_light_estimates_uri = `${base}/arcore/light_estimates.jsonl`;
  }
  if (input.availability.geospatial) {
    captureBundle.arcore_geospatial_uri = `${base}/arcore/geospatial.jsonl`;
  }
  if (input.availability.companion_phone_pose) {
    captureBundle.companion_phone_poses_uri = `${base}/companion_phone/poses.jsonl`;
  }
  if (input.availability.companion_phone_intrinsics) {
    captureBundle.companion_phone_intrinsics_uri =
      `${base}/companion_phone/session_intrinsics.json`;
  }
  if (input.availability.companion_phone_calibration) {
    captureBundle.companion_phone_calibration_uri =
      `${base}/companion_phone/calibration.json`;
  }
  if (input.declaredReferences?.reconstructionQualificationRequest) {
    captureBundle.reconstruction_qualification_request_uri =
      `${base}/reconstruction_qualification_request.json`;
  }
  if (input.declaredReferences?.deviceCalibration) {
    captureBundle.device_calibration_uri = `${base}/device_calibration.json`;
  }
  if (input.declaredReferences?.downstreamCandidateManifest) {
    captureBundle.downstream_candidate_manifest_uri =
      `${base}/downstream_candidate_manifest.json`;
  }

  return captureBundle;
}
