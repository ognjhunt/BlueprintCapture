import { basename } from "path";

export type CaptureObjectKind = "walkthrough" | "completion_marker" | "other";

export type CapturePathInfo = {
  mode: "scenes" | "targets";
  sceneId: string;
  captureSourcePath: string | null;
  captureId: string;
  scenePrefix: string;
  capturePrefix: string;
  rawPrefix: string;
  framesPrefix: string;
  capturesPrefix: string;
  keyframeObjectName: string;
};

function asString(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

export function parseCapturePath(objectName: string, generation: string): CapturePathInfo | null {
  const parts = objectName.split("/");
  if (
    parts.length >= 6 &&
    parts[0] === "scenes" &&
    parts[2] === "captures" &&
    parts[4] === "raw"
  ) {
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

export function captureObjectKind(objectName: string): CaptureObjectKind {
  const fileName = basename(objectName);
  if (fileName === "walkthrough.mov" || fileName === "walkthrough.mp4") return "walkthrough";
  if (fileName === "capture_upload_complete.json") return "completion_marker";
  return "other";
}

export function resolveWalkthroughObjectName(
  manifest: Record<string, unknown> | null,
  pathInfo: CapturePathInfo,
  finalizedObjectName?: string
): string {
  const finalizedFileName = finalizedObjectName ? basename(finalizedObjectName) : null;
  if (
    finalizedObjectName?.startsWith(`${pathInfo.rawPrefix}/`) &&
    (finalizedFileName === "walkthrough.mov" || finalizedFileName === "walkthrough.mp4")
  ) {
    return finalizedObjectName;
  }

  const videoURI = asString(manifest?.video_uri);
  if (videoURI) {
    if (videoURI.startsWith(`${pathInfo.rawPrefix}/`)) {
      return videoURI;
    }
    const rawPrefixIndex = videoURI.indexOf(`${pathInfo.rawPrefix}/`);
    if (rawPrefixIndex >= 0) {
      return videoURI.slice(rawPrefixIndex);
    }
    const videoFileName = basename(videoURI);
    if (videoURI.startsWith("raw/") || videoURI === videoFileName) {
      return `${pathInfo.rawPrefix}/${videoFileName}`;
    }
  }

  return `${pathInfo.rawPrefix}/walkthrough.mov`;
}
