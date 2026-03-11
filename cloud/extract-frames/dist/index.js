import { onObjectFinalized } from "firebase-functions/v2/storage";
import * as logger from "firebase-functions/logger";
import { Storage } from "@google-cloud/storage";
import { tmpdir } from "os";
import { join, basename } from "path";
import { mkdirSync, writeFileSync, readdirSync, statSync, readFileSync } from "fs";
import { spawn } from "child_process";
import ffmpegInstaller from "@ffmpeg-installer/ffmpeg";
import ffprobeInstaller from "@ffprobe-installer/ffprobe";
import { buildPoseIndex, chooseKeyframeCandidate, evaluateQualityGate, findClosestPoseByTime, parsePoseRows, percentile, } from "./bridge.js";
const storage = new Storage();
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
function hasStringArray(value) {
    return Array.isArray(value) && value.every((item) => typeof item === "string");
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
        world_model_candidate: raw?.world_model_candidate === true,
    };
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
    if (!objectName.endsWith("/raw/walkthrough.mov")) {
        logger.info("Skipping object (not a walkthrough.mov upload)", { objectName, contentType });
        return;
    }
    const pathInfo = parseCapturePath(objectName, objectGeneration);
    if (!pathInfo) {
        logger.info("Skipping object (unsupported walkthrough.mov path)", { objectName });
        return;
    }
    logger.info("Starting frame extraction", {
        bucketName,
        objectName,
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
    const walkthroughExists = await waitForObjectExists(bucket, objectName, 3000, 1000);
    const manifestExists = await waitForObjectExists(bucket, manifestObjectName, 45000, 3000);
    const manifest = manifestExists ? await loadJsonObject(bucket, manifestObjectName, tmp) : null;
    const manifestValidation = validateManifest(manifest);
    const poseIndex = await loadArkitPoses(bucket, pathInfo.rawPrefix, tmp);
    const file = bucket.file(objectName);
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
    const sceneMemoryCapture = normalizedSceneMemoryCapture(manifest);
    const captureRights = normalizedCaptureRights(manifest);
    const worldModelCandidate = sceneMemoryCapture.world_model_candidate === true;
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
        capture_bundle: {
            arkit_poses_uri: gsUri(bucketName, `${pathInfo.rawPrefix}/arkit/poses.jsonl`),
            arkit_intrinsics_uri: gsUri(bucketName, `${pathInfo.rawPrefix}/arkit/intrinsics.json`),
            arkit_depth_prefix_uri: gsUri(bucketName, `${pathInfo.rawPrefix}/arkit/depth`),
            arkit_confidence_prefix_uri: gsUri(bucketName, `${pathInfo.rawPrefix}/arkit/confidence`),
        },
        scene_memory_capture: sceneMemoryCapture,
        capture_rights: captureRights,
        requested_lanes: ["qualification", "scene_memory"],
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
            (captureSource === "iphone" ? "tier1_iphone" : "tier2_glasses"),
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
        },
        reasons: finalReasons,
        warnings: finalWarnings,
        generated_at: new Date().toISOString(),
    };
    captureDescriptor.qa_status = finalStatus;
    captureDescriptor.qa_report_uri = qaReportUri;
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
    logger.info("Uploaded frames, descriptor, and QA report", {
        framesPrefix: pathInfo.framesPrefix,
        frameCount: sortedFiles.length,
        captureId: pathInfo.captureId,
        sceneId: pathInfo.sceneId,
        qaStatus: finalStatus,
    });
});
