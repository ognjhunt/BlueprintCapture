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
  arcoreSessionIntrinsics?: Record<string, unknown> | null;
  arcoreDepthManifest?: Record<string, unknown> | null;
  arcoreConfidenceManifest?: Record<string, unknown> | null;
  poses: Record<string, unknown>[];
  frames: Record<string, unknown>[];
  frameQuality: Record<string, unknown>[];
  arcorePoses?: Record<string, unknown>[];
  arcoreFrames?: Record<string, unknown>[];
  arcoreTracking?: Record<string, unknown>[];
  companionPhoneIntrinsics?: Record<string, unknown> | null;
  companionPhonePoses?: Record<string, unknown>[];
  syncMap: Record<string, unknown>[];
  motion: Record<string, unknown>[];
  semanticAnchorObservations: Record<string, unknown>[];
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

function validateRequiredKeys(
  label: string,
  rows: Record<string, unknown>[],
  requiredKeys: string[],
  blockers: string[]
): void {
  for (let i = 0; i < rows.length; i++) {
    const row = rows[i];
    for (const key of requiredKeys) {
      if (!(key in row) || row[key] === undefined || row[key] === null) {
        blockers.push(`${label}_missing_field:${key}:line_${i + 1}`);
      }
    }
  }
}

function hasCapability(capabilities: Record<string, unknown>, key: string): boolean {
  return capabilities[key] === true;
}

function hasExplicitMissingDepthReason(capabilities: Record<string, unknown>): boolean {
  const allowedReasons = new Set([
    "not_supported",
    "not_enabled",
    "temporarily_unavailable",
    "dropped_at_write",
    "invalid_for_frame",
  ]);
  const reason = asString(capabilities.missing_depth_reason);
  return reason !== undefined && allowedReasons.has(reason);
}

function requireFiles(filesPresent: Set<string>, files: string[], blockers: string[]): void {
  for (const file of files) {
    if (!filesPresent.has(file)) {
      blockers.push(`missing_required_file:${file}`);
    }
  }
}

function addBlocker(blockers: string[], blocker: string): void {
  if (!blockers.includes(blocker)) {
    blockers.push(blocker);
  }
}

function hasWalkthroughFile(filesPresent: Set<string>, videoURI: string | undefined): boolean {
  if (videoURI) {
    const normalized = videoURI.startsWith("raw/") ? videoURI.slice("raw/".length) : videoURI;
    const fileName = normalized.split("/").filter(Boolean).pop();
    if (filesPresent.has(videoURI) || filesPresent.has(normalized) || (fileName && filesPresent.has(fileName))) {
      return true;
    }
  }
  return filesPresent.has("walkthrough.mov") || filesPresent.has("walkthrough.mp4");
}

function validateMotionSamples(
  rows: Record<string, unknown>[],
  blockers: string[]
): void {
  const requiredKeys = [
    "timestamp", "t_capture_sec", "t_monotonic_ns", "wall_time",
    "motion_provenance", "attitude", "rotation_rate", "gravity", "user_acceleration"
  ];
  validateRequiredKeys("motion", rows, requiredKeys, blockers);

  for (let i = 0; i < rows.length; i++) {
    const row = rows[i];
    const att = row.attitude;
    if (att !== undefined && att !== null) {
      const attitude = asRecord(att);
      if (!attitude) {
        blockers.push(`motion_attitude_not_object:line_${i + 1}`);
      } else {
        for (const subKey of ["roll", "pitch", "yaw", "quaternion"]) {
          if (!(subKey in attitude) || attitude[subKey] === undefined || attitude[subKey] === null) {
            blockers.push(`motion_attitude_missing_field:${subKey}:line_${i + 1}`);
          }
        }
        const quat = asRecord(attitude.quaternion);
        if (quat) {
          for (const subKey of ["x", "y", "z", "w"]) {
            if (!(subKey in quat) || quat[subKey] === undefined || quat[subKey] === null) {
              blockers.push(`motion_quaternion_missing_field:${subKey}:line_${i + 1}`);
            }
          }
        } else if (attitude.quaternion !== undefined && attitude.quaternion !== null) {
          blockers.push(`motion_quaternion_not_object:line_${i + 1}`);
        }
      }
    }

    const vecFields: Array<[keyof Record<string, unknown>, string]> = [
      ["rotation_rate", "motion_rotation_rate"],
      ["gravity", "motion_gravity"],
      ["user_acceleration", "motion_user_acceleration"]
    ];
    for (let j = 0; j < vecFields.length; j++) {
      const [fieldKey, labelPrefix] = vecFields[j];
      const vec = row[fieldKey];
      if (vec !== undefined && vec !== null) {
        const vecObj = asRecord(vec);
        if (!vecObj) {
          blockers.push(`${labelPrefix}_not_object:line_${i + 1}`);
        } else {
          for (const subKey of ["x", "y", "z"]) {
            if (!(subKey in vecObj) || vecObj[subKey] === undefined || vecObj[subKey] === null) {
              blockers.push(`${labelPrefix}_missing_field:${subKey}:line_${i + 1}`);
            }
          }
        }
      }
    }
  }
}

function validateSemanticAnchorObservations(
  rows: Record<string, unknown>[],
  blockers: string[]
): void {
  const requiredKeys = [
    "anchor_instance_id", "anchor_type", "frame_id",
    "t_capture_sec", "coordinate_frame_session_id", "observation_method"
  ];
  validateRequiredKeys("semantic_anchor", rows, requiredKeys, blockers);
}

export function validateRawCaptureBundleV3(
  input: RawCaptureBundleV3Input
): RawCaptureBundleV3ValidationResult {
  const blockers: string[] = [];
  const warnings: string[] = [];

  const requiredBaseFiles = [
    "manifest.json",
    "provenance.json",
    "rights_consent.json",
    "capture_context.json",
    "intake_packet.json",
    "task_hypothesis.json",
    "recording_session.json",
    "capture_topology.json",
    "route_anchors.json",
    "checkpoint_events.json",
    "relocalization_events.json",
    "overlap_graph.json",
    "video_track.json",
    "motion.jsonl",
    "semantic_anchor_observations.jsonl",
    "capture_upload_complete.json",
    "hashes.json",
    "sync_map.jsonl",
  ];

  const manifest = input.manifest ?? {};
  const captureSource = asString(manifest.capture_source) ?? "unknown";
  const profileId = asString(manifest.capture_profile_id) ?? "";
  const capabilities = asRecord(manifest.capture_capabilities) ?? {};
  const androidXrProfile = profileId.startsWith("android_xr");

  requireFiles(input.filesPresent, requiredBaseFiles, blockers);

  if (!hasWalkthroughFile(input.filesPresent, asString(manifest.video_uri))) {
    blockers.push("missing_required_file:walkthrough");
  }

  if (!isCanonicalV3Manifest(input.manifest)) {
    blockers.push("manifest_not_v3");
  }

  const arkitRequired =
    captureSource === "iphone" ||
    profileId.startsWith("iphone_arkit") ||
    input.filesPresent.has("arkit/poses.jsonl");
  const arcoreRequired =
    captureSource === "android" &&
    (profileId.startsWith("android_arcore") ||
      hasCapability(capabilities, "camera_pose") ||
      input.filesPresent.has("arcore/poses.jsonl"));
  const glassesRequired = captureSource === "glasses" || profileId.startsWith("glasses_");
  const companionPhoneRequired =
    hasCapability(capabilities, "companion_phone_pose") ||
    hasCapability(capabilities, "companion_phone_intrinsics") ||
    hasCapability(capabilities, "companion_phone_calibration") ||
    input.filesPresent.has("companion_phone/poses.jsonl");

  if (arkitRequired) {
    requireFiles(
      input.filesPresent,
      [
        "arkit/poses.jsonl",
        "arkit/frames.jsonl",
        "arkit/frame_quality.jsonl",
        "arkit/per_frame_camera_state.jsonl",
        "arkit/session_intrinsics.json",
      ],
      blockers
    );
    if (hasCapability(capabilities, "depth") || manifest.depth_supported === true) {
      requireFiles(input.filesPresent, ["arkit/depth_manifest.json"], blockers);
    }
    if (hasCapability(capabilities, "depth_confidence") || manifest.depth_supported === true) {
      requireFiles(input.filesPresent, ["arkit/confidence_manifest.json"], blockers);
    }
  }

  if (arcoreRequired) {
    requireFiles(
      input.filesPresent,
      ["arcore/poses.jsonl", "arcore/frames.jsonl", "arcore/session_intrinsics.json", "arcore/tracking_state.jsonl"],
      blockers
    );
    if (hasCapability(capabilities, "point_cloud")) {
      requireFiles(input.filesPresent, ["arcore/point_cloud.jsonl"], blockers);
    }
    if (hasCapability(capabilities, "planes")) {
      requireFiles(input.filesPresent, ["arcore/planes.jsonl"], blockers);
    }
    if (hasCapability(capabilities, "light_estimate")) {
      requireFiles(input.filesPresent, ["arcore/light_estimates.jsonl"], blockers);
    }
    if (hasCapability(capabilities, "depth")) {
      requireFiles(input.filesPresent, ["arcore/depth_manifest.json"], blockers);
    }
    if (hasCapability(capabilities, "depth_confidence")) {
      requireFiles(input.filesPresent, ["arcore/confidence_manifest.json"], blockers);
    }
  }

  if (glassesRequired) {
    requireFiles(
      input.filesPresent,
      [
        "glasses/stream_metadata.json",
        "glasses/frame_timestamps.jsonl",
        "glasses/device_state.jsonl",
        "glasses/health_events.jsonl",
      ],
      blockers
    );
  }

  if (companionPhoneRequired) {
    if (hasCapability(capabilities, "companion_phone_pose") || input.filesPresent.has("companion_phone/poses.jsonl")) {
      requireFiles(input.filesPresent, ["companion_phone/poses.jsonl"], blockers);
    }
    if (
      hasCapability(capabilities, "companion_phone_intrinsics") ||
      input.filesPresent.has("companion_phone/session_intrinsics.json")
    ) {
      requireFiles(input.filesPresent, ["companion_phone/session_intrinsics.json"], blockers);
    }
    if (
      hasCapability(capabilities, "companion_phone_calibration") ||
      input.filesPresent.has("companion_phone/calibration.json")
    ) {
      requireFiles(input.filesPresent, ["companion_phone/calibration.json"], blockers);
    }
  }

  if (androidXrProfile) {
    const poseClaimed =
      hasCapability(capabilities, "camera_pose") ||
      hasCapability(capabilities, "camera_intrinsics") ||
      hasCapability(capabilities, "tracking_state");
    const depthClaimed =
      hasCapability(capabilities, "depth") ||
      hasCapability(capabilities, "depth_confidence") ||
      hasCapability(capabilities, "point_cloud") ||
      hasCapability(capabilities, "planes");
    const geospatialClaimed = hasCapability(capabilities, "geospatial");

    if (poseClaimed) addBlocker(blockers, "android_xr_glasses_pose_claim_not_supported");
    if (depthClaimed || manifest.depth_supported === true) {
      addBlocker(blockers, "android_xr_glasses_depth_claim_not_supported");
    }
    if (geospatialClaimed) {
      addBlocker(blockers, "android_xr_glasses_geospatial_claim_not_supported");
    }
    if (asRecord(manifest.capture_rights)?.capture_contributor_payout_eligible === true ||
        input.rightsConsent?.capture_contributor_payout_eligible === true) {
      addBlocker(blockers, "android_xr_glasses_payout_claim_not_supported");
    }
    if (profileId !== "android_xr_glasses") {
      addBlocker(blockers, "android_xr_glasses_profile_must_be_video_only");
    }

    for (const sidecar of [
      "arcore/poses.jsonl",
      "arcore/frames.jsonl",
      "arcore/session_intrinsics.json",
      "arcore/tracking_state.jsonl",
      "arcore/depth_manifest.json",
      "arcore/confidence_manifest.json",
      "arcore/point_cloud.jsonl",
      "arcore/planes.jsonl",
      "arcore/light_estimates.jsonl",
      "arcore/geospatial.jsonl",
    ]) {
      if (input.filesPresent.has(sidecar)) {
        addBlocker(blockers, `android_xr_glasses_arcore_sidecar_not_supported:${sidecar}`);
      }
    }
  }

  const requiredManifestStrings = [
    "scene_id",
    "capture_id",
    "capture_source",
    "capture_tier_hint",
    "coordinate_frame_session_id",
    "video_uri",
    "app_version",
    "app_build",
    "hardware_model_identifier",
    "device_model_marketing",
    "capture_profile_id",
  ];
  if (captureSource === "iphone") {
    requiredManifestStrings.push("ios_version", "ios_build");
  }
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
  if (!asRecord(manifest.capture_capabilities)) {
    blockers.push("manifest_missing_object:capture_capabilities");
  }
  if (!hasCapability(capabilities, "depth") && !hasExplicitMissingDepthReason(capabilities)) {
    blockers.push("missing_depth_reason_required");
  }

  const sceneId = asString(manifest.scene_id);
  const captureId = asString(manifest.capture_id);
  const cfs = asString(manifest.coordinate_frame_session_id);
  const arcorePoses = input.arcorePoses ?? [];
  const arcoreFrames = input.arcoreFrames ?? [];
  const arcoreTracking = input.arcoreTracking ?? [];
  const companionPhonePoses = input.companionPhonePoses ?? [];

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
    ["arcore_session_intrinsics", asString(input.arcoreSessionIntrinsics?.coordinate_frame_session_id)],
    ["companion_phone_intrinsics", asString(input.companionPhoneIntrinsics?.coordinate_frame_session_id)],
  ] as const) {
    if (cfs && value && value !== cfs) {
      blockers.push(`coordinate_frame_session_mismatch:${label}`);
    }
  }

  validateFrameSeries("poses", input.poses, blockers);
  validateFrameSeries("frames", input.frames, blockers);
  validateFrameSeries("frame_quality", input.frameQuality, blockers);
  validateFrameSeries("arcore_poses", arcorePoses, blockers);
  validateFrameSeries("arcore_frames", arcoreFrames, blockers);
  validateFrameSeries("arcore_tracking_state", arcoreTracking, blockers);
  validateFrameSeries("companion_phone_poses", companionPhonePoses, blockers);
  validateFrameSeries("sync_map", input.syncMap, blockers);

  validateMotionSamples(input.motion, blockers);
  validateSemanticAnchorObservations(input.semanticAnchorObservations, blockers);

  if ((input.poses.length > 0 || arcorePoses.length > 0 || companionPhonePoses.length > 0) && input.syncMap.length === 0) {
    blockers.push("sync_map_missing_rows");
  }

  for (const pose of [...input.poses, ...arcorePoses, ...companionPhonePoses]) {
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
    ["arcore_depth", input.arcoreDepthManifest, ["depth_path", "paired_confidence_path"]],
    ["arcore_confidence", input.arcoreConfidenceManifest, ["confidence_path", "paired_depth_path"]],
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
    for (const relativePath of [...input.filesPresent].sort()) {
      if (relativePath !== "hashes.json" && !(relativePath in hashArtifacts)) {
        blockers.push(`hash_coverage_missing:${relativePath}`);
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
