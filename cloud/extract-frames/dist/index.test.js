import test from "node:test";
import assert from "node:assert/strict";
process.env.FIREBASE_CONFIG = JSON.stringify({ storageBucket: "test-bucket" });
process.env.GCLOUD_PROJECT = "test-project";
const { buildTaskSiteContext, buildWorldlabsPreviewFields, canonicalWorldModelCandidate, deriveRequestedRouting, mergeManifestWithSidecars, parseCapturePath, validateManifest, } = await import("./index.js");
test("parseCapturePath supports canonical scenes capture layout", () => {
    const parsed = parseCapturePath("scenes/scene-123/captures/capture-456/raw/walkthrough.mov", "0");
    assert.ok(parsed);
    assert.equal(parsed?.mode, "scenes");
    assert.equal(parsed?.sceneId, "scene-123");
    assert.equal(parsed?.captureId, "capture-456");
    assert.equal(parsed?.captureSourcePath, null);
    assert.equal(parsed?.rawPrefix, "scenes/scene-123/captures/capture-456/raw");
    assert.equal(parsed?.capturesPrefix, "scenes/scene-123/captures/capture-456");
});
test("parseCapturePath still supports legacy scenes source layout", () => {
    const parsed = parseCapturePath("scenes/scene-123/iphone/capture-456/raw/walkthrough.mov", "0");
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
    const pathInfo = parseCapturePath("scenes/scene-123/captures/capture-456/raw/capture_upload_complete.json", "0");
    assert.ok(pathInfo);
    const fields = buildWorldlabsPreviewFields("test-bucket", pathInfo, true);
    assert.equal(fields.preview_simulation_requested, true);
    assert.equal(fields.worldlabs_request_manifest_uri, "gs://test-bucket/scenes/scene-123/captures/capture-456/worldlabs/request_manifest.json");
    assert.equal(fields.worldlabs_input_manifest_uri, "gs://test-bucket/scenes/scene-123/captures/capture-456/worldlabs/input_manifest.json");
    assert.equal(fields.worldlabs_input_video_uri, "gs://test-bucket/scenes/scene-123/captures/capture-456/raw/walkthrough.mov");
});
test("mergeManifestWithSidecars lifts Android sidecar metadata into manifest shape", () => {
    const merged = mergeManifestWithSidecars({
        scene_id: "scene-1",
        capture_source: "android",
    }, {
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
    });
    assert.equal(merged?.site_identity?.site_id, "site-123");
    assert.equal(merged?.capture_topology?.capture_session_id, "visit-1");
    assert.equal(merged?.capture_topology?.site_visit_id, "visit-1");
    assert.equal(merged?.capture_topology?.coordinate_frame_session_id, "arkit-session-1");
    assert.equal(merged?.capture_mode?.requested_mode, "site_world_candidate");
    assert.equal(merged?.route_anchors?.route_anchors?.[0]?.anchor_id, "anchor_entry");
    assert.equal(merged?.checkpoint_events?.checkpoint_events?.[0]?.anchor_id, "anchor_entry");
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
