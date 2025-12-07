import { onObjectFinalized } from "firebase-functions/v2/storage";
import * as logger from "firebase-functions/logger";
import { Storage } from "@google-cloud/storage";
import { tmpdir } from "os";
import { join, dirname } from "path";
import { mkdirSync, writeFileSync, readdirSync, statSync } from "fs";
import { spawn } from "child_process";
import ffmpegInstaller from "@ffmpeg-installer/ffmpeg";
import ffprobeInstaller from "@ffprobe-installer/ffprobe";
import AdmZip from "adm-zip";
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
        child.stdout.on("data", d => (stdout += d.toString()));
        child.stderr.on("data", d => (stderr += d.toString()));
        child.on("error", reject);
        child.on("close", code => resolve({ stdout, stderr, code }));
    });
}
export const extractFrames = onObjectFinalized({
    region: "us-central1",
    memory: "2GiB",
    timeoutSeconds: 540,
    cpu: 2,
}, async (event) => {
    const bucketName = event.bucket;
    const objectName = event.data?.name || "";
    const contentType = event.data?.contentType || "";
    // Only handle: targets/<scene_id>/raw/walkthrough.mov
    if (!objectName.endsWith("/raw/walkthrough.mov") || !objectName.startsWith("targets/")) {
        logger.info("Skipping object (not a walkthrough.mov under targets/*/raw/)", {
            objectName,
            contentType,
        });
        return;
    }
    logger.info("Starting frame extraction", { bucketName, objectName });
    const tmp = tmpdir();
    const localVideo = join(tmp, `video-${Date.now()}.mov`);
    const framesDir = join(tmp, `frames-${Date.now()}`);
    mkdirSync(framesDir, { recursive: true });
    const bucket = storage.bucket(bucketName);
    const file = bucket.file(objectName);
    // Download video
    await file.download({ destination: localVideo });
    logger.info("Downloaded video to temp", { localVideo });
    // Extract frames using ffmpeg fps=10 and scale longest side to 512 with Lanczos
    const outputPattern = join(framesDir, "%06d.jpg");
    const ffmpegArgs = [
        "-hide_banner",
        "-loglevel",
        "info",
        "-y",
        "-i",
        localVideo,
        "-vf",
        "fps=10,scale=512:-2:flags=lanczos,showinfo",
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
    // Parse pts_time values from showinfo lines
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
    // Build index.jsonl mapping frame_id -> t_video_sec
    const sortedFiles = readdirSync(framesDir)
        .filter(f => f.toLowerCase().endsWith(".jpg"))
        .sort();
    const indexLines = [];
    for (let i = 0; i < sortedFiles.length; i++) {
        const frameId = zeroPad(i + 1, 6);
        const t = i < ptsTimes.length ? ptsTimes[i] : i / 10.0;
        indexLines.push(JSON.stringify({ frame_id: frameId, t_video_sec: Number(t.toFixed(6)) }));
    }
    const indexPath = join(framesDir, "index.jsonl");
    writeFileSync(indexPath, indexLines.join("\n"), { encoding: "utf8" });
    // Upload all frames and index.jsonl to frames/ prefix next to raw/
    // Input: targets/<scene>/raw/walkthrough.mov -> Output: targets/<scene>/frames/<files>
    const scenePrefix = dirname(dirname(objectName)); // targets/<scene>
    const framesPrefix = `${scenePrefix}/frames`;
    const uploads = [];
    for (const fname of readdirSync(framesDir)) {
        const localPath = join(framesDir, fname);
        const dest = `${framesPrefix}/${fname}`;
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
    logger.info("Uploaded frames and index", { framesPrefix, count: sortedFiles.length });
});
// Helper for zipping a directory tree
function addDirToZip(zip, rootDir, currentDir) {
    const entries = readdirSync(currentDir);
    for (const name of entries) {
        const full = join(currentDir, name);
        const relPath = full.substring(rootDir.length + 1); // path relative to rootDir
        const stats = statSync(full);
        if (stats.isDirectory()) {
            addDirToZip(zip, rootDir, full);
        }
        else {
            zip.addLocalFile(full, dirname(relPath), name);
        }
    }
}
// Write shell_architecture_only.usda next to RoomPlanParametric.usdz
function writeShellUsda(roomplanDir) {
    const shellPath = join(roomplanDir, "shell_architecture_only.usda");
    const content = `#usda 1.0
(
    subLayers = ["RoomPlanParametric.usdz"]
)

over "Room_1"
{
    over "Object_grp"
    (
        active = false
    )
}
`;
    writeFileSync(shellPath, content, { encoding: "utf8" });
    return shellPath;
}
export const cleanRoomplan = onObjectFinalized({
    region: "us-central1",
    memory: "2GiB",
    timeoutSeconds: 540,
    cpu: 2,
}, async (event) => {
    const bucketName = event.bucket;
    const objectName = event.data?.name || "";
    const contentType = event.data?.contentType || "";
    // Expect: targets/<scene_id>/raw/roomplan.zip
    if (!objectName.startsWith("targets/") ||
        !objectName.endsWith("/raw/roomplan.zip")) {
        logger.info("Skipping object (not a roomplan.zip under targets/*/raw/)", { objectName, contentType });
        return;
    }
    logger.info("Starting RoomPlan cleanup", { bucketName, objectName });
    const bucket = storage.bucket(bucketName);
    const tmp = tmpdir();
    const localZip = join(tmp, `roomplan-${Date.now()}.zip`);
    const extractDir = join(tmp, `roomplan-extract-${Date.now()}`);
    mkdirSync(extractDir, { recursive: true });
    // 1) Download zip from GCS
    await bucket.file(objectName).download({ destination: localZip });
    // 2) Unzip into extractDir
    const zip = new AdmZip(localZip);
    zip.extractAllTo(extractDir, true);
    // 3) Locate RoomPlanParametric.usdz
    const roomplanDir = join(extractDir, "roomplan");
    const usdzPath = join(roomplanDir, "RoomPlanParametric.usdz");
    try {
        statSync(usdzPath);
    }
    catch {
        logger.error("RoomPlanParametric.usdz not found", { expectedPath: usdzPath });
        return;
    }
    // 4) Write shell_architecture_only.usda next to it
    const shellPath = writeShellUsda(roomplanDir);
    logger.info("Wrote shell_architecture_only.usda", { shellPath });
    // 5) Re-zip everything (including new shell usd)
    const processedZipPath = join(tmp, `roomplan-processed-${Date.now()}.zip`);
    const newZip = new AdmZip();
    addDirToZip(newZip, extractDir, extractDir);
    newZip.writeZip(processedZipPath);
    // 6) Upload processed zip to processed/ prefix
    // raw:       targets/<scene_id>/raw/roomplan.zip
    // processed: targets/<scene_id>/processed/roomplan.zip
    const scenePrefix = dirname(dirname(objectName)); // targets/<scene_id>
    const processedObjectName = `${scenePrefix}/processed/roomplan.zip`;
    await bucket.upload(processedZipPath, {
        destination: processedObjectName,
        metadata: { contentType: "application/zip" },
    });
    logger.info("Uploaded processed RoomPlan zip", {
        processedObjectName,
    });
});
