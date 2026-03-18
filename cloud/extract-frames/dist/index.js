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
import { buildCaptureBundleReferences, buildPoseIndex, chooseKeyframeCandidate, evaluateClaimedArtifacts, evaluateQualityGate, findClosestPoseByTime, parsePoseRows, percentile, } from "./bridge.js";
const storage = new Storage();
const pubsub = new PubSub();
const PIPELINE_HANDOFF_TOPIC = process.env.BLUEPRINT_CAPTURE_PIPELINE_TOPIC ?? "blueprint-capture-pipeline-handoff";
function zeroPad(n, width) {
    const s = String(n);
    return s.length >= width ? s : "0".repeat(width - s.length) + s;
}
async function runCommand(cmd, args, opts = {}) {
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
async function loadArkitPoses(bucket, rawPrefix, tmpDir) {
    const posesObjectName = `${rawPrefix}/arkit/poses.jsonl`;
    const posesFile = bucket.file(posesObjectName);
    let exists = false;
    try {
        [exists] = await posesFile.exists();
    }
    catch (error) {
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
    }
    catch (error) {
        logger.error("Failed to download ARKit pose log", { posesObjectName, error });
        return { byFrameId: new Map(), byTime: [] };
    }
    let content;
    try {
        content = readFileSync(localPosesPath, { encoding: "utf8" });
    }
    catch (error) {
        logger.error("Failed to read downloaded ARKit pose log", { posesObjectName, error });
        return { byFrameId: new Map(), byTime: [] };
    }
    const rows = parsePoseRows(content);
    const index = buildPoseIndex(rows);
    logger.info("Loaded ARKit pose entries", { posesObjectName, count: rows.length });
    return index;
}
export function parseCapturePath(objectName, generation) {
    const parts = objectName.split("/");
    if (parts.length >= 6 &&
        parts[0] === "scenes" &&
        parts[2] === "captures" &&
        parts[4] === "raw") {
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
function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}
async function waitForObjectExists(bucket, objectName, timeoutMs, intervalMs) {
    const started = Date.now();
    while (Date.now() - started <= timeoutMs) {
        try {
            const [exists] = await bucket.file(objectName).exists();
            if (exists)
                return true;
        }
        catch (error) {
            logger.warn("Failed checking object existence", { objectName, error });
        }
        await sleep(intervalMs);
    }
    return false;
}
async function loadJsonObject(bucket, objectName, tmpDir) {
    const localPath = join(tmpDir, `json-${Date.now()}-${basename(objectName)}`);
    try {
        await bucket.file(objectName).download({ destination: localPath });
        const raw = readFileSync(localPath, "utf8");
        const parsed = JSON.parse(raw);
        if (typeof parsed !== "object" || parsed === null)
            return null;
        return parsed;
    }
    catch (error) {
        logger.warn("Failed to load JSON object", { objectName, error });
        return null;
    }
}
export function mergeManifestWithSidecars(manifest, sidecars) {
    const base = asRecord(manifest) || {};
    return {
        ...base,
        site_identity: asRecord(base.site_identity) || sidecars.siteIdentity || null,
        capture_topology: asRecord(base.capture_topology) || sidecars.captureTopology || null,
        capture_mode: asRecord(base.capture_mode) || sidecars.captureMode || null,
    };
}
async function prefixHasObjects(bucket, prefix) {
    try {
        const [files] = await bucket.getFiles({ prefix, maxResults: 1 });
        return files.some((file) => file.name !== prefix && !file.name.endsWith("/"));
    }
    catch (error) {
        logger.warn("Failed to inspect prefix objects", { prefix, error });
        return false;
    }
}
async function fileHasContent(bucket, objectName) {
    try {
        const [metadata] = await bucket.file(objectName).getMetadata();
        const size = Number(metadata.size ?? 0);
        return Number.isFinite(size) && size > 0;
    }
    catch (error) {
        logger.warn("Failed to inspect file content", { objectName, error });
        return false;
    }
}
function isValidIntrinsicsPayload(value) {
    const fx = asFiniteNumber(value?.fx);
    const fy = asFiniteNumber(value?.fy);
    const cx = asFiniteNumber(value?.cx);
    const cy = asFiniteNumber(value?.cy);
    const width = asFiniteNumber(value?.width);
    const height = asFiniteNumber(value?.height);
    return (fx !== undefined &&
        fx > 0 &&
        fy !== undefined &&
        fy > 0 &&
        cx !== undefined &&
        cy !== undefined &&
        width !== undefined &&
        width > 0 &&
        height !== undefined &&
        height > 0);
}
function gsUri(bucketName, objectName) {
    return `gs://${bucketName}/${objectName}`;
}
function asFiniteNumber(value) {
    if (typeof value !== "number" || !Number.isFinite(value))
        return undefined;
    return value;
}
function asString(value) {
    if (typeof value !== "string")
        return undefined;
    const trimmed = value.trim();
    return trimmed.length > 0 ? trimmed : undefined;
}
function asRecord(value) {
    if (typeof value !== "object" || value === null || Array.isArray(value)) {
        return undefined;
    }
    return value;
}
function asStringArray(value) {
    if (!Array.isArray(value))
        return undefined;
    const parsed = value
        .filter((item) => typeof item === "string")
        .map((item) => item.trim())
        .filter((item) => item.length > 0);
    return parsed.length > 0 ? parsed : [];
}
function hasStringArray(value) {
    return Array.isArray(value) && value.every((item) => typeof item === "string");
}
function captureObjectKind(objectName) {
    const fileName = basename(objectName);
    if (fileName === "walkthrough.mov")
        return "walkthrough";
    if (fileName === "capture_upload_complete.json")
        return "completion_marker";
    return "other";
}
export function deriveRequestedRouting(manifest) {
    const requestedOutputs = asStringArray(manifest?.requested_outputs) ?? [];
    const requestedLanes = new Set();
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
export function buildWorldlabsPreviewFields(bucketName, pathInfo, previewSimulationRequested) {
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
export function buildTaskSiteContext(manifest) {
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
function validateIdentityMapping(input) {
    const { manifest, completionMarker, pathInfo } = input;
    const manifestSceneId = asString(manifest?.scene_id) ?? null;
    const manifestCaptureId = asString(manifest?.capture_id) ?? null;
    const completionSceneId = asString(completionMarker?.scene_id) ?? null;
    const completionCaptureId = asString(completionMarker?.capture_id) ?? null;
    const completionRawPrefix = asString(completionMarker?.raw_prefix) ?? null;
    const siteSubmissionId = asString(manifest?.site_submission_id) ?? null;
    const buyerRequestId = asString(manifest?.buyer_request_id) ?? null;
    const captureJobId = asString(manifest?.capture_job_id) ?? null;
    const blockReasons = [];
    const warnings = [];
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
async function publishPipelineHandoff(payload) {
    const topic = pubsub.topic(PIPELINE_HANDOFF_TOPIC);
    const messageBuffer = Buffer.from(JSON.stringify(payload));
    const messageId = await topic.publishMessage({
        data: messageBuffer,
        attributes: {
            scene_id: String(payload.scene_id ?? ""),
            capture_id: String(payload.capture_id ?? ""),
            qa_status: String(payload.qa_status ?? ""),
            preview_simulation_requested: payload.preview_simulation_requested === true ? "true" : "false",
        },
    });
    return messageId;
}
function normalizedSceneMemoryCapture(manifest) {
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
        // world_model_candidate is NOT read from the raw manifest here. It is computed
        // deterministically from actual artifact presence and capture_mode after the bridge
        // has verified GCS artifacts. See canonicalWorldModelCandidate() below.
        world_model_candidate_reasoning: Array.isArray(raw?.world_model_candidate_reasoning)
            ? raw?.world_model_candidate_reasoning
            : [],
        motion_provenance: asString(raw?.motion_provenance) ?? null,
        motion_timestamps_capture_relative: raw?.motion_timestamps_capture_relative === true,
    };
}
function normalizedSiteIdentity(manifest) {
    const raw = asRecord(manifest?.site_identity);
    if (!raw)
        return null;
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
function normalizedCaptureTopology(manifest) {
    const raw = asRecord(manifest?.capture_topology);
    if (!raw)
        return null;
    return {
        capture_session_id: asString(raw.capture_session_id) ?? null,
        route_id: asString(raw.route_id) ?? null,
        pass_id: asString(raw.pass_id) ?? null,
        pass_index: typeof raw.pass_index === "number" ? raw.pass_index : null,
        intended_pass_role: asString(raw.intended_pass_role) ?? "primary",
        entry_anchor_id: asString(raw.entry_anchor_id) ?? null,
        return_anchor_id: asString(raw.return_anchor_id) ?? null,
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
export function canonicalWorldModelCandidate({ manifest, actualAvailability, processingProfile, captureRights, captureSource, }) {
    const captureMode = asRecord(manifest?.capture_mode);
    const resolvedMode = asString(captureMode?.resolved_mode) ?? "qualification_only";
    const requestedMode = asString(captureMode?.requested_mode) ?? "qualification_only";
    const arkitReady = actualAvailability.arkit_poses &&
        actualAvailability.arkit_intrinsics &&
        actualAvailability.arkit_depth &&
        processingProfile === "pose_assisted";
    const nonArkitDeferred = captureSource !== "iphone" &&
        requestedMode === "site_world_candidate" &&
        captureRights.derived_scene_generation_allowed === true;
    const reasoning = [
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
    const candidate = resolvedMode === "site_world_candidate" &&
        arkitReady &&
        captureRights.derived_scene_generation_allowed === true;
    return { candidate, reasoning };
}
function normalizedCaptureRights(manifest) {
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
function validateSceneMemoryCapture(manifest) {
    const warnings = [];
    const sceneMemory = asRecord(manifest.scene_memory_capture);
    if (!sceneMemory) {
        warnings.push("missing_scene_memory_capture");
        return warnings;
    }
    const sensors = asRecord(sceneMemory.sensor_availability);
    const hasRequiredArrays = hasStringArray(sceneMemory.operator_notes) && hasStringArray(sceneMemory.inaccessible_areas);
    const hasRequiredSensors = sensors !== undefined &&
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
function validateCaptureRights(manifest) {
    const warnings = [];
    const captureRights = asRecord(manifest.capture_rights);
    if (!captureRights) {
        warnings.push("missing_capture_rights");
        return warnings;
    }
    const consentStatus = asString(captureRights.consent_status);
    const validConsentStatus = consentStatus === "documented" || consentStatus === "policy_only" || consentStatus === "unknown";
    const hasValidScope = hasStringArray(captureRights.consent_scope);
    const hasValidNotes = hasStringArray(captureRights.consent_notes);
    if (!validConsentStatus || !hasValidScope || !hasValidNotes) {
        warnings.push("malformed_capture_rights");
    }
    return warnings;
}
export function validateManifest(manifest) {
    if (!manifest) {
        return { valid: false, missingRequired: ["manifest"], warnings: [] };
    }
    const missingRequired = [];
    const warnings = [];
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
export const extractFrames = onObjectFinalized({
    region: "us-central1",
    memory: "2GiB",
    timeoutSeconds: 540,
    cpu: 2,
}, async (event) => {
    const bucketName = event.bucket;
    const objectName = event.data?.name || "";
    const contentType = event.data?.contentType || "";
    const objectGeneration = event.data?.generation !== undefined && event.data?.generation !== null
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
    const intrinsicsObjectName = `${pathInfo.rawPrefix}/arkit/intrinsics.json`;
    const walkthroughObjectName = `${pathInfo.rawPrefix}/walkthrough.mov`;
    const walkthroughExists = await waitForObjectExists(bucket, walkthroughObjectName, 45000, 3000);
    const manifestExists = await waitForObjectExists(bucket, manifestObjectName, 45000, 3000);
    const rawManifest = manifestExists ? await loadJsonObject(bucket, manifestObjectName, tmp) : null;
    const sidecarSiteIdentity = await loadJsonObject(bucket, siteIdentityObjectName, tmp);
    const sidecarCaptureTopology = await loadJsonObject(bucket, captureTopologyObjectName, tmp);
    const sidecarCaptureMode = await loadJsonObject(bucket, captureModeObjectName, tmp);
    const manifest = mergeManifestWithSidecars(rawManifest, {
        siteIdentity: sidecarSiteIdentity,
        captureTopology: sidecarCaptureTopology,
        captureMode: sidecarCaptureMode,
    });
    const completionMarker = objectKind === "completion_marker"
        ? await loadJsonObject(bucket, completionMarkerObjectName, tmp)
        : null;
    const manifestValidation = validateManifest(manifest);
    const poseIndex = await loadArkitPoses(bucket, pathInfo.rawPrefix, tmp);
    const intrinsics = await loadJsonObject(bucket, intrinsicsObjectName, tmp);
    const actualAvailability = {
        arkit_poses: poseIndex.byFrameId.size > 0 || poseIndex.byTime.length > 0,
        arkit_intrinsics: isValidIntrinsicsPayload(intrinsics),
        arkit_depth: await prefixHasObjects(bucket, `${pathInfo.rawPrefix}/arkit/depth/`),
        arkit_confidence: await prefixHasObjects(bucket, `${pathInfo.rawPrefix}/arkit/confidence/`),
        arkit_meshes: await prefixHasObjects(bucket, `${pathInfo.rawPrefix}/arkit/meshes/`),
        motion: await fileHasContent(bucket, `${pathInfo.rawPrefix}/motion.jsonl`),
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
    const ptsTimes = [];
    for (const line of stderr.split(/\r?\n/)) {
        let m;
        timeRegex.lastIndex = 0;
        while ((m = timeRegex.exec(line)) !== null) {
            const t = parseFloat(m[1]);
            if (!Number.isNaN(t))
                ptsTimes.push(t);
        }
    }
    const sortedFiles = readdirSync(framesDir)
        .filter((f) => f.toLowerCase().endsWith(".jpg"))
        .sort();
    const indexEntries = [];
    const posesByFrameId = poseIndex.byFrameId;
    const posesByTime = poseIndex.byTime;
    let matchedPoseCount = 0;
    const poseDeltaSecValues = [];
    for (let i = 0; i < sortedFiles.length; i++) {
        const frameId = zeroPad(i + 1, 6);
        const t = i < ptsTimes.length ? ptsTimes[i] : i / 5.0;
        const tVideoSec = Number(t.toFixed(6));
        const entry = {
            frame_id: frameId,
            t_video_sec: tVideoSec,
        };
        let poseMatchType;
        let pose = posesByFrameId.get(frameId);
        if (pose) {
            poseMatchType = "frame_id";
        }
        else if (posesByTime.length > 0) {
            pose = findClosestPoseByTime(posesByTime, tVideoSec);
            if (pose) {
                poseMatchType = "time";
            }
        }
        if (pose) {
            matchedPoseCount += 1;
            const arkitPose = {};
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
    writeFileSync(indexPath, indexEntries.map((row) => JSON.stringify(row)).join("\n"), { encoding: "utf8" });
    const uploads = [];
    for (const fname of readdirSync(framesDir)) {
        const localPath = join(framesDir, fname);
        const dest = `${pathInfo.framesPrefix}/${fname}`;
        const ct = fname.endsWith(".jpg")
            ? "image/jpeg"
            : fname.endsWith(".jsonl")
                ? "application/json"
                : undefined;
        uploads.push(bucket.upload(localPath, {
            destination: dest,
            metadata: ct ? { contentType: ct } : undefined,
        }));
    }
    await Promise.all(uploads);
    const keyframeCandidate = chooseKeyframeCandidate(sortedFiles, (fileName) => statSync(join(framesDir, fileName)).size);
    let keyframeUri = null;
    if (keyframeCandidate) {
        await bucket.upload(join(framesDir, keyframeCandidate.fileName), {
            destination: pathInfo.keyframeObjectName,
            metadata: { contentType: "image/jpeg" },
        });
        keyframeUri = gsUri(bucketName, pathInfo.keyframeObjectName);
    }
    const captureSourceRaw = asString(manifest?.capture_source) ??
        (pathInfo.captureSourcePath === "iphone" || pathInfo.captureSourcePath === "glasses"
            ? pathInfo.captureSourcePath
            : "unknown");
    const captureSource = captureSourceRaw === "iphone"
        ? "iphone"
        : captureSourceRaw === "android_phone"
            ? "android_phone"
            : captureSourceRaw === "glasses"
                ? "glasses"
                : "unknown";
    const poseMatchRate = sortedFiles.length > 0 ? Number((matchedPoseCount / sortedFiles.length).toFixed(6)) : 0;
    const p95PoseDeltaRaw = percentile(poseDeltaSecValues, 95);
    const p95PoseDeltaSec = p95PoseDeltaRaw === null ? null : Number(p95PoseDeltaRaw.toFixed(6));
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
    const captureDescriptorUri = gsUri(bucketName, `${pathInfo.capturesPrefix}/capture_descriptor.json`);
    const pipelineHandoffUri = gsUri(bucketName, `${pathInfo.capturesPrefix}/pipeline_handoff.json`);
    const sceneMemoryCapture = normalizedSceneMemoryCapture(manifest);
    const captureRights = normalizedCaptureRights(manifest);
    const siteIdentity = normalizedSiteIdentity(manifest);
    const captureTopology = normalizedCaptureTopology(manifest);
    // worldModelCandidate is computed AFTER actualAvailability is known (see below).
    const routing = deriveRequestedRouting(manifest);
    const taskSiteContext = buildTaskSiteContext(manifest);
    const worldlabsPreview = buildWorldlabsPreviewFields(bucketName, pathInfo, routing.previewSimulationRequested);
    const claimedSensorRecord = typeof sceneMemoryCapture.sensor_availability === "object" && sceneMemoryCapture.sensor_availability
        ? sceneMemoryCapture.sensor_availability
        : {};
    const claimedAvailability = {
        arkit_poses: claimedSensorRecord.arkit_poses === true,
        arkit_intrinsics: claimedSensorRecord.arkit_intrinsics === true,
        arkit_depth: claimedSensorRecord.arkit_depth === true,
        arkit_confidence: claimedSensorRecord.arkit_confidence === true,
        arkit_meshes: claimedSensorRecord.arkit_meshes === true,
        motion: claimedSensorRecord.motion === true,
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
    const { candidate: worldModelCandidate, reasoning: worldModelCandidateReasoning } = canonicalWorldModelCandidate({
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
    const deferGeometry = captureSource !== "iphone" &&
        requestedMode === "site_world_candidate" &&
        captureRights.derived_scene_generation_allowed === true;
    const resolvedMode = worldModelCandidate || deferGeometry ? "site_world_candidate" : "qualification_only";
    const captureMode = {
        requested_mode: requestedMode,
        resolved_mode: resolvedMode,
        downgrade_reason: requestedMode === "site_world_candidate" && resolvedMode === "qualification_only"
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
    const captureDescriptor = {
        schema_version: "v1",
        scene_id: pathInfo.sceneId,
        capture_id: pathInfo.captureId,
        capture_source: captureSource,
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
        capture_mode: captureMode,
        geometry_source: null,
        geometry_ready: false,
        coordinate_frame_session_id: asString(captureTopology?.capture_session_id) ??
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
        ...worldlabsPreview,
        generated_at: new Date().toISOString(),
    };
    if (!keyframeUri) {
        finalWarnings.push("missing_keyframe");
    }
    if (pathInfo.mode === "targets") {
        finalWarnings.push("legacy_targets_path");
    }
    const qaReport = {
        schema_version: "v1",
        scene_id: pathInfo.sceneId,
        capture_id: pathInfo.captureId,
        capture_source: captureSource,
        capture_tier_initial: asString(manifest?.capture_tier_hint) ??
            (captureSource === "iphone"
                ? "tier1_iphone"
                : captureSource === "android_phone"
                    ? "tier2_android_phone"
                    : "tier2_glasses"),
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
    const pipelineHandoffPayload = {
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
    await bucket
        .file(`${pathInfo.capturesPrefix}/pipeline_handoff.json`)
        .save(JSON.stringify(pipelineHandoffPayload, null, 2), {
        contentType: "application/json",
    });
    const handoffMessageId = await publishPipelineHandoff(pipelineHandoffPayload);
    logger.info("Uploaded frames, descriptor, QA report, and pipeline handoff", {
        framesPrefix: pathInfo.framesPrefix,
        frameCount: sortedFiles.length,
        captureId: pathInfo.captureId,
        sceneId: pathInfo.sceneId,
        qaStatus: finalStatus,
        handoffTopic: PIPELINE_HANDOFF_TOPIC,
        handoffMessageId,
    });
});
