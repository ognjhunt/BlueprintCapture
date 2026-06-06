import test from "node:test";
import assert from "node:assert/strict";

process.env.FIREBASE_CONFIG = JSON.stringify({ storageBucket: "test-bucket" });
process.env.GCLOUD_PROJECT = "test-project";

const {
  buildRawCaptureLineageFields,
  buildPipelineStatusEvent,
  buildRobotEvalHandoffFields,
  buildTaskSiteContext,
  buildWorldlabsPreviewFields,
  canonicalWorldModelCandidate,
  captureObjectKind,
  deriveRequestedRouting,
  mergeManifestWithSidecars,
  parseCapturePath,
  resolveWalkthroughObjectName,
  validateIdentityMapping,
  validateManifest,
} = await import("./index.js");

test("parseCapturePath supports canonical scenes capture layout", () => {
  const parsed = parseCapturePath(
    "scenes/scene-123/captures/capture-456/raw/walkthrough.mov",
    "0"
  );

  assert.ok(parsed);
  assert.equal(parsed?.mode, "scenes");
  assert.equal(parsed?.sceneId, "scene-123");
  assert.equal(parsed?.captureId, "capture-456");
  assert.equal(parsed?.captureSourcePath, null);
  assert.equal(parsed?.rawPrefix, "scenes/scene-123/captures/capture-456/raw");
  assert.equal(parsed?.capturesPrefix, "scenes/scene-123/captures/capture-456");
});

test("validateIdentityMapping preserves missing upstream ids as hosted-review blockers", () => {
  const pathInfo = parseCapturePath(
    "scenes/scene-123/captures/capture-456/raw/capture_upload_complete.json",
    "0"
  );
  assert.ok(pathInfo);

  const validation = validateIdentityMapping({
    manifest: {
      scene_id: "scene-123",
      capture_id: "capture-456",
    },
    completionMarker: {
      sceneId: "scene-123",
      captureId: "capture-456",
      rawPrefix: "scenes/scene-123/captures/capture-456/raw",
    },
    pathInfo,
  });

  assert.equal(validation.blockReasons.length, 0);
  assert.ok(validation.warnings.includes("missing_site_submission_id"));
  assert.ok(validation.warnings.includes("missing_buyer_request_id"));
  assert.ok(validation.warnings.includes("missing_capture_job_id"));
  assert.deepEqual(validation.identity.hosted_review_blockers, [
    "missing_site_submission_id",
    "missing_buyer_request_id",
    "missing_capture_job_id",
  ]);
});

test("deriveRequestedRouting exposes robot eval dataset publication routing", () => {
  const routing = deriveRequestedRouting({
    requested_outputs: ["robot_eval_dataset", "task_evaluation_run"],
  });

  assert.equal(routing.robotEvalDatasetRequested, true);
  assert.equal(routing.robotEvalPublicationGateRequired, true);
  assert.ok(routing.requestedLanes.includes("robot_eval_dataset"));
  assert.ok(routing.requestedLanes.includes("task_evaluation_run"));
  assert.ok(routing.requestedLanes.includes("evaluation_prep"));
});

test("buildRobotEvalHandoffFields carries publication package and missing-proof metadata", () => {
  const pathInfo = parseCapturePath(
    "scenes/scene-123/captures/capture-456/raw/capture_upload_complete.json",
    "0"
  );
  assert.ok(pathInfo);

  const identityValidation = validateIdentityMapping({
    manifest: {
      scene_id: "scene-123",
      capture_id: "capture-456",
      site_submission_id: "site-submission-1",
      buyer_request_id: "buyer-request-1",
    },
    completionMarker: {
      sceneId: "scene-123",
      captureId: "capture-456",
      rawPrefix: "scenes/scene-123/captures/capture-456/raw",
    },
    pathInfo,
  });
  const routing = deriveRequestedRouting({
    requested_outputs: ["robot_eval_dataset"],
  });
  const taskSiteContext = buildTaskSiteContext({
    task_text_hint: "Move totes from receiving to shelf staging",
    target_kpi: "Complete in under 45 seconds with zero collisions",
    zone: "receiving",
    task_anchor_candidates: [
      {
        task_id: "move_tote_receiving_to_staging",
        start_zone: [0, 0, 0],
        goal_zone: [2, 1, 0],
        confidence: "capturer_hint",
      },
    ],
    scene_asset_hints: [
      {
        asset_type: "ply",
        path_hint: "pipeline/advanced_geometry/3dgs_compressed.ply",
      },
    ],
    robot_profiles: [
      {
        robot_profile_id: "mobile_manipulator_rgbd_fixture",
        source: "capturer_hint",
      },
    ],
    route_anchors: {
      route_anchors: [
        {
          anchor_id: "receiving_start",
          label: "Receiving start",
        },
      ],
    },
  });

  const fields = buildRobotEvalHandoffFields({
    routing,
    taskSiteContext,
    identity: identityValidation.identity,
  });

  assert.equal(fields.robot_eval_dataset_requested, true);
  assert.equal(fields.robot_eval_publication_gate_required, true);
  assert.deepEqual(fields.robot_eval_required_artifacts, [
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
  ]);
  assert.deepEqual(fields.robot_eval_missing_proof_labels, [
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
  ]);
  assert.deepEqual(fields.robot_eval_task_thresholds, {
    threshold_source: "capture_manifest_target_kpi",
    target_kpi: "Complete in under 45 seconds with zero collisions",
    zone: "receiving",
    claim_boundary: "capture_target_kpi_is_threshold_context_not_robot_readiness_proof",
  });
  assert.deepEqual(fields.robot_eval_episode_spec_inputs, {
    task_anchor_candidate_count: 1,
    scene_asset_hint_count: 1,
    robot_profile_candidate_count: 1,
    route_anchor_candidate_count: 1,
    review_required: true,
    claim_boundary:
      "episode_spec_inputs_can_seed_pipeline_review_but_cannot_set_proof_booleans",
  });
  assert.deepEqual(fields.robot_eval_cpu_preflight_inputs, {
    task_anchor_candidates: [
      {
        task_id: "move_tote_receiving_to_staging",
        start_zone: [0, 0, 0],
        goal_zone: [2, 1, 0],
        confidence: "capturer_hint",
      },
    ],
    scene_asset_hints: [
      {
        asset_type: "ply",
        path_hint: "pipeline/advanced_geometry/3dgs_compressed.ply",
      },
    ],
    robot_profile_candidates: [
      {
        robot_profile_id: "mobile_manipulator_rgbd_fixture",
        source: "capturer_hint",
      },
    ],
    route_anchor_candidates: [
      {
        anchor_id: "receiving_start",
        label: "Receiving start",
      },
    ],
    source_policy:
      "capture_handoff_candidates_only_raw_capture_and_pipeline_validators_remain_authoritative",
    claim_boundary:
      "cpu_preflight_inputs_are_advisory_and_do_not_prove_scene_scale_collision_or_robot_readiness",
  });
  assert.deepEqual(fields.robot_eval_publication_blockers, ["missing_capture_job_id"]);
});

test("buildPipelineStatusEvent emits canonical raw upload completion trigger payload", () => {
  const pathInfo = parseCapturePath(
    "scenes/scene-123/captures/capture-456/raw/capture_upload_complete.json",
    "7"
  );
  assert.ok(pathInfo);

  const event = buildPipelineStatusEvent({
    bucketName: "test-bucket",
    pathInfo,
    objectName: "scenes/scene-123/captures/capture-456/raw/capture_upload_complete.json",
    objectKind: "completion_marker",
    qaStatus: "passed",
    pipelineHandoffUri:
      "gs://test-bucket/scenes/scene-123/captures/capture-456/pipeline_handoff.json",
  });

  assert.deepEqual(event, {
    event_type: "capture.raw_upload_complete.v1",
    scene_id: "scene-123",
    capture_id: "capture-456",
    raw_prefix: "scenes/scene-123/captures/capture-456/raw",
    raw_prefix_uri: "gs://test-bucket/scenes/scene-123/captures/capture-456/raw",
    upload_completion_marker_uri:
      "gs://test-bucket/scenes/scene-123/captures/capture-456/raw/capture_upload_complete.json",
    trigger_object: "scenes/scene-123/captures/capture-456/raw/capture_upload_complete.json",
    trigger_kind: "completion_marker",
    qa_status: "passed",
    pipeline_handoff_uri:
      "gs://test-bucket/scenes/scene-123/captures/capture-456/pipeline_handoff.json",
  });
});

test("captureObjectKind treats mp4 walkthrough uploads as bridge triggers", () => {
  assert.equal(
    captureObjectKind("scenes/scene-123/captures/capture-456/raw/walkthrough.mp4"),
    "walkthrough"
  );
});

test("parseCapturePath still supports legacy scenes source layout", () => {
  const parsed = parseCapturePath(
    "scenes/scene-123/iphone/capture-456/raw/walkthrough.mov",
    "0"
  );

  assert.ok(parsed);
  assert.equal(parsed?.mode, "scenes");
  assert.equal(parsed?.captureSourcePath, "iphone");
  assert.equal(parsed?.capturesPrefix, "scenes/scene-123/captures/capture-456");
});

test("validateManifest warns when scene memory and rights metadata are missing", () => {
  const validation = validateManifest({
    scene_id: "scene-123",
    video_uri: "gs://bucket/scenes/scene-123/captures/capture-456/raw/walkthrough.mov",
    device_model: "iPhone 15 Pro",
    os_version: "18.0",
    fps_source: 30,
    width: 1920,
    height: 1440,
    capture_start_epoch_ms: 1_700_000_000_000,
    has_lidar: true,
    capture_schema_version: "2.0.0",
    capture_source: "iphone",
    capture_tier_hint: "tier1_iphone",
  });

  assert.equal(validation.valid, true);
  assert.ok(validation.warnings.includes("missing_scene_memory_capture"));
  assert.ok(validation.warnings.includes("missing_capture_rights"));
});

test("validateManifest accepts normalized scene memory and rights metadata", () => {
  const validation = validateManifest({
    scene_id: "scene-123",
    video_uri: "gs://bucket/scenes/scene-123/captures/capture-456/raw/walkthrough.mov",
    device_model: "iPhone 15 Pro",
    os_version: "18.0",
    fps_source: 30,
    width: 1920,
    height: 1440,
    capture_start_epoch_ms: 1_700_000_000_000,
    has_lidar: true,
    capture_schema_version: "2.0.0",
    capture_source: "iphone",
    capture_tier_hint: "tier1_iphone",
    scene_memory_capture: {
      continuity_score: null,
      lighting_consistency: "unknown",
      dynamic_object_density: "unknown",
      sensor_availability: {
        arkit_poses: true,
        arkit_intrinsics: true,
        arkit_depth: true,
        arkit_confidence: true,
        arkit_meshes: true,
        motion: true,
      },
      operator_notes: [],
      inaccessible_areas: [],
      world_model_candidate: false,
    },
    capture_rights: {
      derived_scene_generation_allowed: false,
      data_licensing_allowed: false,
      capture_contributor_payout_eligible: false,
      consent_status: "unknown",
      permission_document_uri: null,
      consent_scope: [],
      consent_notes: [],
    },
  });

  assert.equal(validation.valid, true);
  assert.ok(!validation.warnings.includes("missing_scene_memory_capture"));
  assert.ok(!validation.warnings.includes("missing_capture_rights"));
  assert.ok(!validation.warnings.includes("malformed_scene_memory_capture"));
  assert.ok(!validation.warnings.includes("malformed_capture_rights"));
});

test("validateManifest enforces additional v3 manifest fields", () => {
  const validation = validateManifest({
    schema_version: "v3",
    capture_schema_version: "3.0.0",
    scene_id: "scene-123",
    capture_id: "capture-456",
    coordinate_frame_session_id: "cfs-1",
    video_uri: "gs://bucket/scenes/scene-123/captures/capture-456/raw/walkthrough.mov",
    device_model: "iPhone16,2",
    device_model_marketing: "iPhone 15 Pro",
    os_version: "18.3.1",
    app_version: "1.0.0",
    app_build: "100",
    ios_version: "18.3.1",
    ios_build: "22D68",
    hardware_model_identifier: "iPhone16,2",
    fps_source: 30,
    width: 1920,
    height: 1440,
    capture_start_epoch_ms: 1_700_000_000_000,
    has_lidar: true,
    depth_supported: true,
    capture_source: "iphone",
    capture_tier_hint: "tier1_iphone",
    capture_profile_id: "iphone_arkit_lidar",
    capture_capabilities: { camera_pose: true, depth: true },
  });

  assert.equal(validation.valid, true);
  assert.deepEqual(validation.missingRequired, []);
});

test("validateManifest enforces v3.1 capture_profile_id and capture_capabilities", () => {
  // Missing v3.1 fields should fail
  const validationMissing = validateManifest({
    schema_version: "v3",
    capture_schema_version: "3.1.0",
    scene_id: "scene-123",
    capture_id: "capture-456",
    coordinate_frame_session_id: "cfs-1",
    video_uri: "raw/walkthrough.mov",
    device_model: "iPhone16,2",
    device_model_marketing: "iPhone 15 Pro",
    os_version: "18.3.1",
    app_version: "1.0.0",
    app_build: "100",
    ios_version: "18.3.1",
    ios_build: "22D68",
    hardware_model_identifier: "iPhone16,2",
    fps_source: 30,
    width: 1920,
    height: 1440,
    capture_start_epoch_ms: 1_700_000_000_000,
    has_lidar: true,
    depth_supported: true,
    capture_source: "iphone",
    capture_tier_hint: "tier1_iphone",
  });
  assert.equal(validationMissing.valid, false);
  assert.ok(validationMissing.missingRequired.includes("capture_profile_id"));
  assert.ok(validationMissing.missingRequired.includes("capture_capabilities"));

  // Present v3.1 fields should pass
  const validationPresent = validateManifest({
    schema_version: "v3",
    capture_schema_version: "3.1.0",
    scene_id: "scene-123",
    capture_id: "capture-456",
    coordinate_frame_session_id: "cfs-1",
    video_uri: "raw/walkthrough.mov",
    device_model: "iPhone16,2",
    device_model_marketing: "iPhone 15 Pro",
    os_version: "18.3.1",
    app_version: "1.0.0",
    app_build: "100",
    ios_version: "18.3.1",
    ios_build: "22D68",
    hardware_model_identifier: "iPhone16,2",
    fps_source: 30,
    width: 1920,
    height: 1440,
    capture_start_epoch_ms: 1_700_000_000_000,
    has_lidar: true,
    depth_supported: true,
    capture_source: "iphone",
    capture_tier_hint: "tier1_iphone",
    capture_profile_id: "iphone_arkit_lidar",
    capture_capabilities: { camera_pose: true, depth: true },
    scene_memory_capture: {
      operator_notes: [],
      inaccessible_areas: [],
      sensor_availability: {
        arkit_poses: true,
        arkit_intrinsics: true,
        arkit_depth: true,
        arkit_confidence: true,
        arkit_meshes: false,
        motion: true,
      },
      semantic_anchors_observed: [],
    },
    capture_rights: {
      consent_status: "documented",
      consent_scope: [],
      consent_notes: [],
    },
  });
  assert.equal(validationPresent.valid, true);
  assert.deepEqual(validationPresent.missingRequired, []);
});

test("validateManifest accepts Android V3.1 without iOS-only build fields", () => {
  const validation = validateManifest({
    schema_version: "v3",
    capture_schema_version: "3.1.0",
    scene_id: "scene-123",
    capture_id: "capture-456",
    coordinate_frame_session_id: "cfs-1",
    video_uri: "raw/walkthrough.mp4",
    device_model: "Pixel 9 Pro",
    device_model_marketing: "Pixel 9 Pro",
    os_version: "Android 16",
    app_version: "1.0.0",
    app_build: "100",
    hardware_model_identifier: "Pixel 9 Pro",
    fps_source: 30,
    width: 1920,
    height: 1080,
    capture_start_epoch_ms: 1_700_000_000_000,
    has_lidar: false,
    depth_supported: true,
    capture_source: "android",
    capture_tier_hint: "tier2_android",
    capture_profile_id: "android_arcore_depth",
    capture_capabilities: { camera_pose: true, camera_intrinsics: true, depth: true },
    scene_memory_capture: {
      operator_notes: [],
      inaccessible_areas: [],
      sensor_availability: {
        arkit_poses: false,
        arkit_intrinsics: false,
        arkit_depth: false,
        arkit_confidence: false,
        arkit_meshes: false,
        motion: false,
      },
    },
    capture_rights: {
      consent_status: "unknown",
      consent_scope: [],
      consent_notes: [],
    },
  });

  assert.equal(validation.valid, true);
  assert.deepEqual(validation.missingRequired, []);
});

test("deriveRequestedRouting preserves outputs and expands preview simulation lane", () => {
  const routing = deriveRequestedRouting({
    requested_outputs: ["qualification", "preview_simulation"],
  });

  assert.deepEqual(routing.requestedOutputs, ["qualification", "preview_simulation"]);
  assert.equal(routing.previewSimulationRequested, true);
  assert.deepEqual(routing.requestedLanes, ["qualification", "scene_memory", "preview_simulation"]);
});

test("buildTaskSiteContext lifts task and site metadata from manifest", () => {
  const context = buildTaskSiteContext({
    task_text_hint: "Dock-to-staging tote handoff",
    task_steps: ["Dock entry", "Outbound handoff"],
    target_kpi: "handoff throughput",
    zone: "dock_a",
    shift: "day",
    owner: "warehouse_supervisor",
    capture_profile: {
      facility_template: "warehouse_dock_handoff",
      required_coverage_areas: ["Ingress route"],
      benchmark_stations: ["Dock threshold"],
      adjacent_systems: ["WMS"],
      privacy_security_limits: ["No faces"],
      known_blockers: ["Forklift congestion"],
      non_routine_modes: ["jam clearing"],
      people_traffic_notes: ["Shared aisle"],
      capture_restrictions: ["Avoid office corridor"],
    },
    environment_variability: {
      lighting_windows: ["08:00-11:00"],
      shift_traffic_windows: ["Morning rush"],
      movable_obstacles: ["Pallets"],
      floor_condition_notes: ["Smooth concrete"],
      reflective_surface_notes: ["Dock strip curtain"],
      access_rules: ["Escort required"],
    },
  });

  assert.equal(context.workflow_name, "Dock-to-staging tote handoff");
  assert.deepEqual(context.task_steps, ["Dock entry", "Outbound handoff"]);
  assert.equal(context.target_kpi, "handoff throughput");
  assert.equal(context.zone, "dock_a");
  assert.equal(context.shift, "day");
  assert.equal(context.owner, "warehouse_supervisor");
  assert.equal(context.facility_template, "warehouse_dock_handoff");
  assert.deepEqual(context.benchmark_stations, ["Dock threshold"]);
  assert.deepEqual(context.access_rules, ["Escort required"]);
});

test("buildWorldlabsPreviewFields reserves worldlabs uris when preview is requested", () => {
  const pathInfo = parseCapturePath(
    "scenes/scene-123/captures/capture-456/raw/capture_upload_complete.json",
    "0"
  );

  assert.ok(pathInfo);
  const fields = buildWorldlabsPreviewFields("test-bucket", pathInfo!, true);

  assert.equal(fields.preview_simulation_requested, true);
  assert.equal(
    fields.worldlabs_request_manifest_uri,
    "gs://test-bucket/scenes/scene-123/captures/capture-456/worldlabs/request_manifest.json"
  );
  assert.equal(
    fields.worldlabs_input_manifest_uri,
    "gs://test-bucket/scenes/scene-123/captures/capture-456/worldlabs/input_manifest.json"
  );
  assert.equal(
    fields.worldlabs_input_video_uri,
    "gs://test-bucket/scenes/scene-123/captures/capture-456/raw/walkthrough.mov"
  );
});

test("buildWorldlabsPreviewFields can use resolved mp4 walkthrough uri", () => {
  const pathInfo = parseCapturePath(
    "scenes/scene-123/captures/capture-456/raw/capture_upload_complete.json",
    "0"
  );

  assert.ok(pathInfo);
  const videoObjectName = resolveWalkthroughObjectName(
    { video_uri: "raw/walkthrough.mp4" },
    pathInfo!
  );
  const fields = buildWorldlabsPreviewFields("test-bucket", pathInfo!, true, videoObjectName);

  assert.equal(
    fields.worldlabs_input_video_uri,
    "gs://test-bucket/scenes/scene-123/captures/capture-456/raw/walkthrough.mp4"
  );
});

test("buildRawCaptureLineageFields preserves Meta raw video descriptor lineage", () => {
  const pathInfo = parseCapturePath(
    "scenes/scene-123/captures/capture-456/raw/capture_upload_complete.json",
    "0"
  );

  assert.ok(pathInfo);
  const fields = buildRawCaptureLineageFields(
    "test-bucket",
    pathInfo!,
    {
      capture_source: "meta_glasses",
      capture_profile_id: "glasses_pov",
      width: 1920,
      height: 1080,
      fps_source: 30,
      device_model: "Ray-Ban Meta",
      frame_timestamps_object: "scenes/scene-123/captures/capture-456/raw/glasses/frame_timestamps.jsonl",
      stream_metadata_object: "scenes/scene-123/captures/capture-456/raw/glasses/stream_metadata.json",
      privacy_lineage: { status: "raw_unprocessed" },
      provenance_lineage: { original_media_sha256: "abc" },
    },
    "glasses",
    "scenes/scene-123/captures/capture-456/raw/walkthrough.mov"
  );

  assert.equal(fields.source_device, "meta_glasses");
  assert.equal(fields.capture_modality, "glasses_pov");
  assert.equal(fields.raw_video_uri, "gs://test-bucket/scenes/scene-123/captures/capture-456/raw/walkthrough.mov");
  assert.equal((fields.media_metadata as any).frame_timestamps_uri, "gs://test-bucket/scenes/scene-123/captures/capture-456/raw/glasses/frame_timestamps.jsonl");
  assert.equal((fields.media_metadata as any).stream_metadata_uri, "gs://test-bucket/scenes/scene-123/captures/capture-456/raw/glasses/stream_metadata.json");
  assert.equal((fields.privacy_lineage as any).status, "raw_unprocessed");
  assert.equal((fields.provenance_lineage as any).original_media_sha256, "abc");
});

test("mergeManifestWithSidecars lifts Android sidecar metadata into manifest shape", () => {
  const merged = mergeManifestWithSidecars(
    {
      scene_id: "scene-1",
      capture_source: "android",
    },
    {
      siteIdentity: { site_id: "site-123", site_id_source: "site_submission" },
      captureTopology: {
        capture_session_id: "visit-1",
        site_visit_id: "visit-1",
        coordinate_frame_session_id: "arkit-session-1",
        pass_id: "pass-1",
      },
      captureMode: { requested_mode: "site_world_candidate", resolved_mode: "site_world_candidate" },
      routeAnchors: {
        schema_version: "v1",
        route_anchors: [{ anchor_id: "anchor_entry", anchor_type: "entry" }],
      },
      checkpointEvents: {
        schema_version: "v1",
        checkpoint_events: [{ anchor_id: "anchor_entry", pass_id: "pass-1", t_capture_sec: 1.0, completed: true }],
      },
      relocalizationEvents: {
        schema_version: "v1",
        relocalization_events: [{ event_id: "relocalize-1", pass_id: "pass-1", status: "accepted" }],
      },
    },
  );

  assert.equal((merged as any)?.site_identity?.site_id, "site-123");
  assert.equal((merged as any)?.capture_topology?.capture_session_id, "visit-1");
  assert.equal((merged as any)?.capture_topology?.site_visit_id, "visit-1");
  assert.equal((merged as any)?.capture_topology?.coordinate_frame_session_id, "arkit-session-1");
  assert.equal((merged as any)?.capture_mode?.requested_mode, "site_world_candidate");
  assert.equal((merged as any)?.route_anchors?.route_anchors?.[0]?.anchor_id, "anchor_entry");
  assert.equal((merged as any)?.checkpoint_events?.checkpoint_events?.[0]?.anchor_id, "anchor_entry");
  assert.equal((merged as any)?.relocalization_events?.relocalization_events?.[0]?.event_id, "relocalize-1");
});

test("canonicalWorldModelCandidate requires stable site identity for iPhone captures", () => {
  const result = canonicalWorldModelCandidate({
    manifest: {
      site_identity: null,
      capture_mode: { requested_mode: "site_world_candidate", resolved_mode: "site_world_candidate" },
    },
    actualAvailability: {
      arkit_poses: true,
      arkit_intrinsics: true,
      arkit_depth: true,
    },
    processingProfile: "pose_assisted",
    captureRights: { derived_scene_generation_allowed: true },
    captureSource: "iphone",
  });

  assert.equal(result.candidate, false);
  assert.ok(result.reasoning.includes("site_id_present:false"));
});

test("canonicalWorldModelCandidate defers non-ARKit world model promotion until geometry stage", () => {
  const result = canonicalWorldModelCandidate({
    manifest: {
      capture_mode: { requested_mode: "site_world_candidate", resolved_mode: "qualification_only" },
    },
    actualAvailability: {
      arkit_poses: false,
      arkit_intrinsics: false,
      arkit_depth: false,
    },
    processingProfile: "video_only",
    captureRights: { derived_scene_generation_allowed: true },
    captureSource: "android",
  });

  assert.equal(result.candidate, false);
  assert.ok(result.reasoning.includes("awaiting_geometry_stage:true"));
});
