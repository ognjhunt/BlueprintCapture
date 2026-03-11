import test from "node:test";
import assert from "node:assert/strict";
process.env.FIREBASE_CONFIG = JSON.stringify({ storageBucket: "test-bucket" });
process.env.GCLOUD_PROJECT = "test-project";
const { parseCapturePath, validateManifest } = await import("./index.js");
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
