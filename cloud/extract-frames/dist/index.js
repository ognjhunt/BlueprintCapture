import { onObjectFinalized } from "firebase-functions/v2/storage";
import * as logger from "firebase-functions/logger";
import { Storage } from "@google-cloud/storage";
import { tmpdir } from "os";
import { join, dirname, basename } from "path";
import { mkdirSync, writeFileSync, readdirSync, statSync, readFileSync, createWriteStream } from "fs";
import { spawn } from "child_process";
import ffmpegInstaller from "@ffmpeg-installer/ffmpeg";
import ffprobeInstaller from "@ffprobe-installer/ffprobe";
import AdmZip from "adm-zip";
import archiver from "archiver";
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
    const scenePrefix = dirname(dirname(objectName));
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
function addDirToZip(zip, rootDir, currentDir) {
    const entries = readdirSync(currentDir);
    for (const name of entries) {
        const full = join(currentDir, name);
        const relPath = full.substring(rootDir.length + 1);
        const stats = statSync(full);
        if (stats.isDirectory()) {
            addDirToZip(zip, rootDir, full);
        }
        else {
            zip.addLocalFile(full, dirname(relPath), name);
        }
    }
}
function findFileRecursive(rootDir, targetFileName) {
    const entries = readdirSync(rootDir);
    for (const name of entries) {
        const full = join(rootDir, name);
        const stats = statSync(full);
        if (stats.isDirectory()) {
            const found = findFileRecursive(full, targetFileName);
            if (found) {
                return found;
            }
        }
        else if (name === targetFileName) {
            return full;
        }
    }
    return null;
}
function removeObjectGrpFromUsd(usdContent) {
    const lines = usdContent.split('\n');
    const output = [];
    let insideObjectGrp = false;
    let braceDepth = 0;
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        const trimmed = line.trim();
        if (insideObjectGrp) {
            const openBraces = (line.match(/{/g) || []).length;
            const closeBraces = (line.match(/}/g) || []).length;
            braceDepth += openBraces - closeBraces;
            if (braceDepth <= 0) {
                insideObjectGrp = false;
                braceDepth = 0;
            }
            continue;
        }
        if (trimmed.startsWith('def ') && trimmed.includes('"Object_grp"')) {
            insideObjectGrp = true;
            const openBraces = (line.match(/{/g) || []).length;
            const closeBraces = (line.match(/}/g) || []).length;
            braceDepth = openBraces - closeBraces;
            continue;
        }
        if (trimmed.startsWith('over ') && trimmed.includes('"Object_grp"')) {
            insideObjectGrp = true;
            const openBraces = (line.match(/{/g) || []).length;
            const closeBraces = (line.match(/}/g) || []).length;
            braceDepth = openBraces - closeBraces;
            continue;
        }
        output.push(line);
    }
    return output.join('\n');
}
function getAllFilesInDir(dir, fileList = []) {
    const files = readdirSync(dir);
    for (const file of files) {
        const filePath = join(dir, file);
        const stats = statSync(filePath);
        if (stats.isDirectory()) {
            getAllFilesInDir(filePath, fileList);
        }
        else {
            fileList.push(filePath);
        }
    }
    return fileList;
}
async function createUncompressedUsdz(sourceDir, outputPath) {
    return new Promise((resolve, reject) => {
        const output = createWriteStream(outputPath);
        const archive = archiver('zip', {
            store: true,
            zlib: { level: 0 }
        });
        output.on('close', () => {
            logger.info(`Created USDZ with ${archive.pointer()} bytes`);
            resolve();
        });
        archive.on('error', (err) => {
            reject(err);
        });
        archive.pipe(output);
        const allFiles = getAllFilesInDir(sourceDir);
        const usdFiles = allFiles.filter(f => f.endsWith('.usdc') || f.endsWith('.usda'));
        const otherFiles = allFiles.filter(f => !f.endsWith('.usdc') && !f.endsWith('.usda'));
        if (usdFiles.length > 0) {
            const firstFile = usdFiles[0];
            const relativePath = firstFile.substring(sourceDir.length + 1);
            archive.file(firstFile, { name: relativePath });
        }
        const sortedOtherFiles = [...usdFiles.slice(1), ...otherFiles].sort();
        for (const file of sortedOtherFiles) {
            const relativePath = file.substring(sourceDir.length + 1);
            archive.file(file, { name: relativePath });
        }
        archive.finalize();
    });
}
async function processUsdzToRemoveObjects(usdzPath, outputPath) {
    const extractDir = join(dirname(usdzPath), `usdz-extract-${Date.now()}`);
    mkdirSync(extractDir, { recursive: true });
    const zip = new AdmZip(usdzPath);
    zip.extractAllTo(extractDir, true);
    const allFiles = getAllFilesInDir(extractDir);
    for (const filePath of allFiles) {
        const fileName = basename(filePath);
        if (fileName.endsWith('.usda') || fileName.endsWith('.usd')) {
            try {
                const content = readFileSync(filePath, 'utf8');
                const modified = removeObjectGrpFromUsd(content);
                writeFileSync(filePath, modified, 'utf8');
                logger.info(`Modified USD file: ${fileName}`);
            }
            catch (err) {
                logger.warn(`Could not read/modify ${fileName} as text, skipping`, { error: err });
            }
        }
    }
    await createUncompressedUsdz(extractDir, outputPath);
    logger.info(`Created modified USDZ: ${outputPath}`);
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
    await bucket.file(objectName).download({ destination: localZip });
    const zip = new AdmZip(localZip);
    zip.extractAllTo(extractDir, true);
    const usdzPath = findFileRecursive(extractDir, "RoomPlanParametric.usdz");
    if (!usdzPath) {
        logger.error("RoomPlanParametric.usdz not found after unzip", {
            extractDir,
        });
        return;
    }
    const roomplanDir = dirname(usdzPath);
    logger.info("Found RoomPlanParametric.usdz", {
        usdzPath,
        roomplanDir,
    });
    const architectureOnlyPath = join(roomplanDir, "RoomPlanArchitectureOnly.usdz");
    await processUsdzToRemoveObjects(usdzPath, architectureOnlyPath);
    const processedZipPath = join(tmp, `roomplan-processed-${Date.now()}.zip`);
    const newZip = new AdmZip();
    addDirToZip(newZip, extractDir, extractDir);
    newZip.writeZip(processedZipPath);
    const scenePrefix = dirname(dirname(objectName));
    const processedObjectName = `${scenePrefix}/processed/roomplan.zip`;
    await bucket.upload(processedZipPath, {
        destination: processedObjectName,
        metadata: { contentType: "application/zip" },
    });
    logger.info("Uploaded processed RoomPlan zip with architecture-only USDZ", {
        processedObjectName,
    });
});
