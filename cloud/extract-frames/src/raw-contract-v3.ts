export type RawCaptureBundleV3Input = {
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
};

export type RawCaptureBundleV3ValidationResult = {
  valid: boolean;
  blockers: string[];
  warnings: string[];
};

function asString(value: unknown): string | undefined {
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : undefined;
}

function asFiniteNumber(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

function asRecord(value: unknown): Record<string, unknown> | undefined {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : undefined;
}

function isCanonicalV3Manifest(manifest: Record<string, unknown> | null): boolean {
  return (
    asString(manifest?.schema_version) === "v3" &&
    (asString(manifest?.capture_schema_version)?.startsWith("3.") ?? false)
  );
}

function isMatrix4x4(value: unknown): boolean {
  return (
    Array.isArray(value) &&
    value.length === 4 &&
    value.every(
      (row) =>
        Array.isArray(row) &&
        row.length === 4 &&
        row.every((cell) => typeof cell === "number" && Number.isFinite(cell))
    )
  );
}

function validateFrameSeries(
  label: string,
  rows: Record<string, unknown>[],
  blockers: string[]
): void {
  const seen = new Set<string>();
  let lastTime = Number.NEGATIVE_INFINITY;
  for (const row of rows) {
    const frameId = asString(row.frame_id);
    const tCaptureSec = asFiniteNumber(row.t_capture_sec);
    if (!frameId) {
      blockers.push(`missing_frame_id:${label}`);
      continue;
    }
    if (seen.has(frameId)) {
      blockers.push(`frame_id_duplicate:${label}:${frameId}`);
    }
    seen.add(frameId);
    if (tCaptureSec === undefined) {
      blockers.push(`missing_time:${label}:${frameId}`);
      continue;
    }
    if (tCaptureSec < lastTime) {
      blockers.push(`timestamp_non_monotonic:${label}:${frameId}`);
    }
    lastTime = tCaptureSec;
  }
}

export function validateRawCaptureBundleV3(
  input: RawCaptureBundleV3Input
): RawCaptureBundleV3ValidationResult {
  const blockers: string[] = [];
  const warnings: string[] = [];

  const requiredFiles = [
    "manifest.json",
    "provenance.json",
    "rights_consent.json",
    "capture_context.json",
    "recording_session.json",
    "capture_topology.json",
    "capture_upload_complete.json",
    "hashes.json",
    "sync_map.jsonl",
    "arkit/poses.jsonl",
    "arkit/frames.jsonl",
    "arkit/frame_quality.jsonl",
    "arkit/session_intrinsics.json",
    "arkit/depth_manifest.json",
    "arkit/confidence_manifest.json",
  ];

  for (const file of requiredFiles) {
    if (!input.filesPresent.has(file)) {
      blockers.push(`missing_required_file:${file}`);
    }
  }

  if (!isCanonicalV3Manifest(input.manifest)) {
    blockers.push("manifest_not_v3");
  }

  const manifest = input.manifest ?? {};
  const requiredManifestStrings = [
    "scene_id",
    "capture_id",
    "capture_source",
    "capture_tier_hint",
    "coordinate_frame_session_id",
    "video_uri",
    "app_version",
    "app_build",
    "ios_version",
    "ios_build",
    "hardware_model_identifier",
    "device_model_marketing",
    "capture_profile_id",
  ];
  const requiredManifestNumbers = ["capture_start_epoch_ms", "fps_source", "width", "height"];
  const requiredManifestBooleans = ["has_lidar", "depth_supported"];

  for (const key of requiredManifestStrings) {
    if (!asString(manifest[key])) blockers.push(`manifest_missing_string:${key}`);
  }
  for (const key of requiredManifestNumbers) {
    if (asFiniteNumber(manifest[key]) === undefined) blockers.push(`manifest_missing_number:${key}`);
  }
  for (const key of requiredManifestBooleans) {
    if (typeof manifest[key] !== "boolean") blockers.push(`manifest_missing_boolean:${key}`);
  }

  const sceneId = asString(manifest.scene_id);
  const captureId = asString(manifest.capture_id);
  const cfs = asString(manifest.coordinate_frame_session_id);

  for (const [label, object] of [
    ["provenance", input.provenance],
    ["rights_consent", input.rightsConsent],
    ["capture_context", input.captureContext],
    ["capture_upload_complete", input.completionMarker],
  ] as const) {
    if (!object) {
      blockers.push(`missing_required_object:${label}`);
      continue;
    }
    if (sceneId && asString(object.scene_id) && asString(object.scene_id) !== sceneId) {
      blockers.push(`identity_mismatch:${label}:scene_id`);
    }
    if (captureId && asString(object.capture_id) && asString(object.capture_id) !== captureId) {
      blockers.push(`identity_mismatch:${label}:capture_id`);
    }
  }

  for (const [label, value] of [
    ["recording_session", asString(input.recordingSession?.coordinate_frame_session_id)],
    ["capture_topology", asString(input.captureTopology?.coordinate_frame_session_id)],
    ["session_intrinsics", asString(input.sessionIntrinsics?.coordinate_frame_session_id)],
  ] as const) {
    if (cfs && value && value !== cfs) {
      blockers.push(`coordinate_frame_session_mismatch:${label}`);
    }
  }

  validateFrameSeries("poses", input.poses, blockers);
  validateFrameSeries("frames", input.frames, blockers);
  validateFrameSeries("frame_quality", input.frameQuality, blockers);
  validateFrameSeries("sync_map", input.syncMap, blockers);

  if (input.poses.length > 0 && input.syncMap.length === 0) {
    blockers.push("sync_map_missing_rows");
  }

  for (const pose of input.poses) {
    const frameId = asString(pose.frame_id) ?? "unknown";
    if (!isMatrix4x4(pose.T_world_camera)) {
      blockers.push(`invalid_transform_matrix:${frameId}`);
    }
    const poseCfs = asString(pose.coordinate_frame_session_id);
    if (cfs && poseCfs && poseCfs !== cfs) {
      blockers.push(`coordinate_frame_session_mismatch:pose:${frameId}`);
    }
  }

  for (const [label, manifestObject, pathKeys] of [
    ["depth", input.depthManifest, ["depth_path", "paired_confidence_path"]],
    ["confidence", input.confidenceManifest, ["confidence_path", "paired_depth_path"]],
  ] as const) {
    const frames = Array.isArray(manifestObject?.frames) ? manifestObject?.frames : [];
    for (const frame of frames) {
      const row = asRecord(frame);
      if (!row) continue;
      const frameId = asString(row.frame_id) ?? "unknown";
      for (const key of pathKeys) {
        const path = asString(row[key]);
        if (path && !input.filesPresent.has(path)) {
          blockers.push(`referenced_artifact_missing:${label}:${frameId}:${path}`);
        }
      }
    }
  }

  const hashArtifacts = asRecord(input.hashes?.artifacts);
  if (!hashArtifacts) {
    blockers.push("missing_hash_manifest");
  } else {
    for (const relativePath of Object.keys(hashArtifacts)) {
      if (!input.filesPresent.has(relativePath)) {
        blockers.push(`hash_target_missing:${relativePath}`);
      }
    }
  }

  if ((input.rightsConsent?.redaction_required as boolean | undefined) !== true) {
    warnings.push("rights_redaction_not_explicitly_required");
  }

  return {
    valid: blockers.length === 0,
    blockers,
    warnings,
  };
}
