import test from "node:test";
import assert from "node:assert/strict";

import { isDeterministicJsonlError, parseStrictJsonLines } from "./jsonl.js";

test("parseStrictJsonLines rejects malformed JSONL", () => {
  assert.throws(
    () => parseStrictJsonLines(['{"frame_id":"000001"}', '{"frame_id":'].join("\n"), "frames.jsonl"),
    /invalid_jsonl:frames\.jsonl:2/
  );
});

test("isDeterministicJsonlError separates parse failures from transient IO errors", () => {
  let parseError: unknown;
  try {
    parseStrictJsonLines('{"frame_id":', "arkit/poses.jsonl");
  } catch (error) {
    parseError = error;
  }
  // Malformed content fails identically on every retry, so the ARKit loaders
  // degrade to "log unavailable" instead of crash-looping the trigger.
  assert.equal(isDeterministicJsonlError(parseError), true);
  // Transient storage errors must still rethrow so the trigger retries them.
  assert.equal(isDeterministicJsonlError(new Error("socket hang up")), false);
  assert.equal(isDeterministicJsonlError(undefined), false);
});
