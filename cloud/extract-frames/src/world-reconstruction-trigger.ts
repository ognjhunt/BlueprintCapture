/**
 * Asking the WebApp to reconstruct a capture, as soon as its frames exist.
 *
 * This is the link that makes the chain hands-off. A capturer uploads one
 * walkthrough; this function extracts frames; the WebApp sends those frames to
 * a World Labs world model and hands the resulting scene to the Pipeline,
 * which configures a robot and runs policies against it. Nobody presses a
 * button anywhere in that sequence.
 *
 * Three properties matter here, and all three come from the same fact: the
 * storage trigger that runs this is at-least-once.
 *
 * 1. It must be idempotent. Generating a world costs real credits, so a
 *    redelivery must not start a second one. The caller owns that guard (see
 *    `alreadyRequested`), because the receipt lives in the same bucket as the
 *    rest of the capture's artifacts.
 * 2. It must not fail the extraction. Frames and the Pipeline handoff are the
 *    canonical output; reconstruction is downstream of them. A WebApp that is
 *    down should leave a capture that can be reconstructed later, not a
 *    capture that looks like it failed.
 * 3. It must say what happened. Every outcome is a value, so the caller can
 *    write it next to the capture instead of leaving a silence.
 */

import { createHmac } from "node:crypto";

export type WorldReconstructionRequestOutcome =
  | { status: "requested"; operationId: string | null; httpStatus: number }
  | { status: "already_requested" }
  | { status: "not_configured"; blocker: string }
  | { status: "blocked"; blocker: string; httpStatus: number; detail: string }
  | { status: "failed"; blocker: string; detail: string };

export interface WorldReconstructionTriggerConfig {
  /** WebApp origin, e.g. https://app.tryblueprint.io */
  baseUrl: string;
  /** Shared secret; the same PIPELINE_SYNC_TOKEN the WebApp verifies against. */
  syncToken: string;
  /** Overridable for tests. */
  fetchImpl?: typeof fetch;
  now?: () => Date;
  timeoutMs?: number;
}

export function readWorldReconstructionConfig(
  env: NodeJS.ProcessEnv = process.env,
): WorldReconstructionTriggerConfig | { blocker: string } {
  const baseUrl = String(env.BLUEPRINT_WEBAPP_BASE_URL || "").trim().replace(/\/+$/, "");
  const syncToken = String(env.BLUEPRINT_PIPELINE_SYNC_TOKEN || "").trim();

  if (!baseUrl) {
    return { blocker: "webapp_base_url_missing" };
  }
  if (!syncToken) {
    return { blocker: "pipeline_sync_token_missing" };
  }
  return { baseUrl, syncToken };
}

/**
 * Sign the request the way `verifyPipelineSyncRequest` expects: HMAC-SHA256
 * over `<timestamp>.<body>`, with the timestamp sent alongside so the WebApp
 * can reject replays outside its skew window.
 */
export function signPipelineSyncRequest(args: {
  secret: string;
  timestamp: string;
  body: string;
}): string {
  return createHmac("sha256", args.secret)
    .update(`${args.timestamp}.${args.body}`)
    .digest("hex");
}

export interface RequestWorldReconstructionArgs {
  config: WorldReconstructionTriggerConfig;
  captureId: string;
  /** gs:// prefix holding the extracted frames and their index.jsonl. */
  framesPrefixUri: string;
  sceneId?: string | null;
  siteSubmissionId?: string | null;
  /**
   * Whether a reconstruction has already been asked for. The receipt lives in
   * storage next to the capture, so the caller reads it; this function stays
   * free of bucket access and therefore testable without one.
   */
  alreadyRequested?: boolean;
}

export async function requestWorldReconstruction(
  args: RequestWorldReconstructionArgs,
): Promise<WorldReconstructionRequestOutcome> {
  if (args.alreadyRequested) {
    return { status: "already_requested" };
  }

  const { config } = args;
  const fetchImpl = config.fetchImpl || fetch;
  const now = config.now || (() => new Date());

  const body = JSON.stringify({
    frames_prefix_uri: args.framesPrefixUri,
    ...(args.sceneId ? { scene_id: args.sceneId } : {}),
    ...(args.siteSubmissionId ? { site_submission_id: args.siteSubmissionId } : {}),
  });
  const timestamp = now().toISOString();
  const signature = signPipelineSyncRequest({
    secret: config.syncToken,
    timestamp,
    body,
  });

  const url =
    `${config.baseUrl}/api/internal/pipeline/creator-captures/` +
    `${encodeURIComponent(args.captureId)}/world/reconstruct`;

  let response: Response;
  try {
    response = await fetchImpl(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Blueprint-Pipeline-Timestamp": timestamp,
        "X-Blueprint-Pipeline-Signature": `sha256=${signature}`,
      },
      body,
      signal: AbortSignal.timeout(config.timeoutMs ?? 30_000),
    });
  } catch (error) {
    // The WebApp being unreachable leaves a capture that can be reconstructed
    // later. It must not look like a failed capture.
    return {
      status: "failed",
      blocker: "webapp_unreachable",
      detail: error instanceof Error ? error.message : String(error),
    };
  }

  const text = await response.text().catch(() => "");
  let payload: Record<string, unknown> = {};
  try {
    payload = text ? (JSON.parse(text) as Record<string, unknown>) : {};
  } catch {
    payload = {};
  }

  if (!response.ok) {
    // 409 is the WebApp reporting a named blocker of its own -- no frames, a
    // model we do not have access to yet. That is a real state to record, not
    // a transport failure to retry blindly.
    const reconstruction =
      payload.reconstruction && typeof payload.reconstruction === "object"
        ? (payload.reconstruction as Record<string, unknown>)
        : {};
    return {
      status: "blocked",
      blocker: String(reconstruction.blocker || payload.error || "world_reconstruction_rejected"),
      httpStatus: response.status,
      detail: text.slice(0, 500),
    };
  }

  const reconstruction =
    payload.reconstruction && typeof payload.reconstruction === "object"
      ? (payload.reconstruction as Record<string, unknown>)
      : {};
  const operationId = String(reconstruction.operationId || "").trim();

  return {
    status: "requested",
    operationId: operationId || null,
    httpStatus: response.status,
  };
}

/** The receipt written beside the capture so a redelivery does not re-request. */
export function worldReconstructionReceipt(args: {
  captureId: string;
  framesPrefixUri: string;
  outcome: WorldReconstructionRequestOutcome;
  requestedAt: string;
}): Record<string, unknown> {
  return {
    schema_version: "v1",
    capture_id: args.captureId,
    frames_prefix_uri: args.framesPrefixUri,
    status: args.outcome.status,
    operation_id: args.outcome.status === "requested" ? args.outcome.operationId : null,
    blocker:
      args.outcome.status === "blocked" ||
      args.outcome.status === "failed" ||
      args.outcome.status === "not_configured"
        ? args.outcome.blocker
        : null,
    requested_at: args.requestedAt,
    // This receipt records that reconstruction was asked for. It is not a
    // claim that a world exists, that it is any good, or that the capture
    // qualified for anything.
    authority: "reconstruction_requested_not_world_proof",
  };
}
