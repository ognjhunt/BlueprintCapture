function toFiniteNumber(value) {
    if (typeof value !== "number" || !Number.isFinite(value)) {
        return undefined;
    }
    return value;
}
function toMatrix(value) {
    if (!Array.isArray(value))
        return undefined;
    const matrix = [];
    for (const row of value) {
        if (!Array.isArray(row))
            return undefined;
        const parsedRow = [];
        for (const col of row) {
            const numeric = toFiniteNumber(col);
            if (numeric === undefined)
                return undefined;
            parsedRow.push(numeric);
        }
        matrix.push(parsedRow);
    }
    return matrix;
}
export function zeroPad(n, width) {
    const s = String(n);
    return s.length >= width ? s : "0".repeat(width - s.length) + s;
}
export function parsePoseRows(content) {
    const rows = [];
    const lines = content.split(/\r?\n/);
    for (const lineRaw of lines) {
        const line = lineRaw.trim();
        if (!line)
            continue;
        try {
            const parsed = JSON.parse(line);
            rows.push(parsed);
        }
        catch {
            continue;
        }
    }
    const legacyTimestampRows = rows
        .map((row) => ({
        timestamp: toFiniteNumber(row.timestamp),
        tDeviceSec: toFiniteNumber(row.t_device_sec),
    }))
        .filter((row) => row.timestamp !== undefined && row.tDeviceSec === undefined)
        .map((row) => row.timestamp);
    const legacyBaseTimestamp = legacyTimestampRows.length > 0 ? legacyTimestampRows[0] : undefined;
    return rows.map((row) => {
        const frameIdRaw = typeof row.frame_id === "string" ? row.frame_id : undefined;
        const frameIndexRaw = toFiniteNumber(row.frameIndex);
        const frameId = frameIdRaw ??
            (frameIndexRaw !== undefined ? zeroPad(Math.max(0, Math.floor(frameIndexRaw)) + 1, 6) : undefined);
        const tDeviceSecRaw = toFiniteNumber(row.t_device_sec);
        const timestampRaw = toFiniteNumber(row.timestamp);
        let tDeviceSec = tDeviceSecRaw;
        if (tDeviceSec === undefined && timestampRaw !== undefined && legacyBaseTimestamp !== undefined) {
            tDeviceSec = Math.max(0, timestampRaw - legacyBaseTimestamp);
        }
        const worldCamera = toMatrix(row.T_world_camera) ??
            toMatrix(row.transform);
        const poseSchemaVersion = typeof row.pose_schema_version === "string" ? row.pose_schema_version : undefined;
        let sourceSchema = "legacy";
        if (frameIdRaw !== undefined ||
            tDeviceSecRaw !== undefined ||
            toMatrix(row.T_world_camera) !== undefined ||
            poseSchemaVersion !== undefined) {
            sourceSchema = "v2";
        }
        if (frameIndexRaw !== undefined ||
            timestampRaw !== undefined ||
            toMatrix(row.transform) !== undefined) {
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
export function buildPoseIndex(rows) {
    const byFrameId = new Map();
    const byTime = [];
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
export function findClosestPoseByTime(poses, targetTime) {
    if (!poses.length)
        return undefined;
    let low = 0;
    let high = poses.length - 1;
    while (low < high) {
        const mid = Math.floor((low + high) / 2);
        const midTime = poses[mid].t_device_sec ?? Number.NEGATIVE_INFINITY;
        if (midTime < targetTime) {
            low = mid + 1;
        }
        else {
            high = mid;
        }
    }
    let best = poses[low];
    const bestTime = best.t_device_sec;
    const bestDiff = bestTime !== undefined ? Math.abs(bestTime - targetTime) : Number.POSITIVE_INFINITY;
    const prev = low > 0 ? poses[low - 1] : undefined;
    if (prev && prev.t_device_sec !== undefined) {
        const prevDiff = Math.abs(prev.t_device_sec - targetTime);
        if (prevDiff <= bestDiff) {
            best = prev;
        }
    }
    return best;
}
export function percentile(values, p) {
    if (!values.length)
        return null;
    if (p <= 0)
        return Math.min(...values);
    if (p >= 100)
        return Math.max(...values);
    const sorted = [...values].sort((a, b) => a - b);
    const rank = (p / 100) * (sorted.length - 1);
    const low = Math.floor(rank);
    const high = Math.ceil(rank);
    if (low === high)
        return sorted[low];
    const weight = rank - low;
    return sorted[low] * (1 - weight) + sorted[high] * weight;
}
export function chooseKeyframeCandidate(frameFiles, getFileSize) {
    if (frameFiles.length === 0)
        return undefined;
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
export function evaluateQualityGate(input) {
    const reasons = [];
    const warnings = [];
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
            captureTier: input.captureSource === "iphone" ? "tier1_iphone" : "tier2_glasses",
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
        captureTier: "tier2_glasses",
        processingProfile: "video_only",
        reasons,
        warnings,
    };
}
