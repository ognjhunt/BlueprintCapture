import assert from "node:assert/strict";
import test from "node:test";
import { createHmac } from "node:crypto";

import {
  readWorldReconstructionConfig,
  requestWorldReconstruction,
  signPipelineSyncRequest,
  worldReconstructionReceipt,
  type WorldReconstructionTriggerConfig,
} from "./world-reconstruction-trigger.js";

const FRAMES = "gs://bucket/scenes/s1/captures/c1/frames";

function config(overrides: Partial<WorldReconstructionTriggerConfig> = {}): WorldReconstructionTriggerConfig {
  return {
    baseUrl: "https://app.example.com",
    syncToken: "secret-token",
    now: () => new Date("2026-09-16T12:00:00.000Z"),
    ...overrides,
  };
}

function jsonResponse(status: number, payload: unknown): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

test("config requires both the WebApp origin and the shared secret", () => {
  assert.deepEqual(readWorldReconstructionConfig({} as NodeJS.ProcessEnv), {
    blocker: "webapp_base_url_missing",
  });
  assert.deepEqual(
    readWorldReconstructionConfig({ BLUEPRINT_WEBAPP_BASE_URL: "https://a.example" } as NodeJS.ProcessEnv),
    { blocker: "pipeline_sync_token_missing" },
  );

  const resolved = readWorldReconstructionConfig({
    BLUEPRINT_WEBAPP_BASE_URL: "https://a.example/",
    BLUEPRINT_PIPELINE_SYNC_TOKEN: "t",
  } as NodeJS.ProcessEnv);
  assert.equal("baseUrl" in resolved && resolved.baseUrl, "https://a.example");
});

test("signature matches what the WebApp recomputes", () => {
  const timestamp = "2026-09-16T12:00:00.000Z";
  const body = JSON.stringify({ frames_prefix_uri: FRAMES });
  const expected = createHmac("sha256", "secret-token")
    .update(`${timestamp}.${body}`)
    .digest("hex");

  assert.equal(signPipelineSyncRequest({ secret: "secret-token", timestamp, body }), expected);
});

test("posts a signed request to the capture's reconstruct route", async () => {
  let seenUrl = "";
  let seenInit: RequestInit | undefined;

  const outcome = await requestWorldReconstruction({
    config: config({
      fetchImpl: (async (url: string | URL | Request, init?: RequestInit) => {
        seenUrl = String(url);
        seenInit = init;
        return jsonResponse(202, { ok: true, reconstruction: { operationId: "op-1" } });
      }) as unknown as typeof fetch,
    }),
    captureId: "cap-1",
    framesPrefixUri: FRAMES,
    sceneId: "scene-1",
  });

  assert.deepEqual(outcome, { status: "requested", operationId: "op-1", httpStatus: 202 });
  assert.equal(
    seenUrl,
    "https://app.example.com/api/internal/pipeline/creator-captures/cap-1/world/reconstruct",
  );

  const headers = seenInit?.headers as Record<string, string>;
  assert.equal(headers["X-Blueprint-Pipeline-Timestamp"], "2026-09-16T12:00:00.000Z");
  assert.match(headers["X-Blueprint-Pipeline-Signature"], /^sha256=[0-9a-f]{64}$/);

  const body = JSON.parse(String(seenInit?.body));
  assert.equal(body.frames_prefix_uri, FRAMES);
  assert.equal(body.scene_id, "scene-1");

  // The signature has to cover exactly the bytes that were sent.
  const expected = signPipelineSyncRequest({
    secret: "secret-token",
    timestamp: "2026-09-16T12:00:00.000Z",
    body: String(seenInit?.body),
  });
  assert.equal(headers["X-Blueprint-Pipeline-Signature"], `sha256=${expected}`);
});

test("does not re-request when a receipt already exists", async () => {
  let called = false;
  const outcome = await requestWorldReconstruction({
    config: config({
      fetchImpl: (async () => {
        called = true;
        return jsonResponse(202, {});
      }) as unknown as typeof fetch,
    }),
    captureId: "cap-1",
    framesPrefixUri: FRAMES,
    alreadyRequested: true,
  });

  // Generating a world costs credits; an at-least-once redelivery must not
  // buy a second one.
  assert.deepEqual(outcome, { status: "already_requested" });
  assert.equal(called, false);
});

test("an unreachable WebApp is reported, never thrown", async () => {
  const outcome = await requestWorldReconstruction({
    config: config({
      fetchImpl: (async () => {
        throw new Error("ECONNREFUSED");
      }) as unknown as typeof fetch,
    }),
    captureId: "cap-1",
    framesPrefixUri: FRAMES,
  });

  assert.equal(outcome.status, "failed");
  assert.equal(outcome.status === "failed" && outcome.blocker, "webapp_unreachable");
});

test("carries the WebApp's own blocker through rather than flattening it", async () => {
  const outcome = await requestWorldReconstruction({
    config: config({
      fetchImpl: (async () =>
        jsonResponse(409, {
          ok: false,
          reconstruction: { blocker: "worldlabs_model_unavailable" },
        })) as unknown as typeof fetch,
    }),
    captureId: "cap-1",
    framesPrefixUri: FRAMES,
  });

  assert.equal(outcome.status, "blocked");
  assert.equal(outcome.status === "blocked" && outcome.blocker, "worldlabs_model_unavailable");
  assert.equal(outcome.status === "blocked" && outcome.httpStatus, 409);
});

test("survives a non-JSON error body", async () => {
  const outcome = await requestWorldReconstruction({
    config: config({
      fetchImpl: (async () => new Response("<html>502</html>", { status: 502 })) as unknown as typeof fetch,
    }),
    captureId: "cap-1",
    framesPrefixUri: FRAMES,
  });

  assert.equal(outcome.status, "blocked");
  assert.equal(outcome.status === "blocked" && outcome.blocker, "world_reconstruction_rejected");
});

test("the receipt records a request, and claims nothing about the world", () => {
  const receipt = worldReconstructionReceipt({
    captureId: "cap-1",
    framesPrefixUri: FRAMES,
    outcome: { status: "requested", operationId: "op-1", httpStatus: 202 },
    requestedAt: "2026-09-16T12:00:00.000Z",
  });

  assert.equal(receipt.status, "requested");
  assert.equal(receipt.operation_id, "op-1");
  assert.equal(receipt.blocker, null);
  assert.equal(receipt.authority, "reconstruction_requested_not_world_proof");
});

test("the receipt keeps the blocker when one was hit", () => {
  const receipt = worldReconstructionReceipt({
    captureId: "cap-1",
    framesPrefixUri: FRAMES,
    outcome: { status: "blocked", blocker: "capture_frames_empty", httpStatus: 409, detail: "" },
    requestedAt: "2026-09-16T12:00:00.000Z",
  });

  assert.equal(receipt.status, "blocked");
  assert.equal(receipt.blocker, "capture_frames_empty");
  assert.equal(receipt.operation_id, null);
});
