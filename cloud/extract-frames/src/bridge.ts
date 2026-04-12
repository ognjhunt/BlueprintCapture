import { parseStrictJsonLines } from "./jsonl.js";

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
  camera_pose?: boolean;
  camera_intrinsics?: boolean;
  depth?: boolean;
  depth_confidence?: boolean;
  point_cloud?: boolean;
  planes?: boolean;
  tracking_state?: boolean;
  light_estimate?: boolean;
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
  const valid = input.actual;

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
}): Record<string, unknown> {
  const base = `gs://${input.bucketName}/${input.rawPrefix}`;
  const captureBundle: Record<string, unknown> = {
    artifact_validity: input.availability,
  };

  if (input.availability.arkit_poses) {
    captureBundle.arkit_poses_uri = `${base}/arkit/poses.jsonl`;
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

  return captureBundle;
}
