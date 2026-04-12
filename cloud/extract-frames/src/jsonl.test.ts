import test from "node:test";
import assert from "node:assert/strict";

import { parseStrictJsonLines } from "./jsonl.js";

test("parseStrictJsonLines rejects malformed JSONL", () => {
  assert.throws(
    () => parseStrictJsonLines(['{"frame_id":"000001"}', '{"frame_id":'].join("\n"), "frames.jsonl"),
    /invalid_jsonl:frames\.jsonl:2/
  );
});
