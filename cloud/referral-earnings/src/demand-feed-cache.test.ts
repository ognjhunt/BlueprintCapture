import test from "node:test";
import assert from "node:assert/strict";

import {
  DEFAULT_DEMAND_FEED_CACHE_TTL_MS,
  DEFAULT_DEMAND_SNAPSHOT_REFRESH_FRESHNESS_MS,
  SingleFlightTtlCache,
  isRefreshFresh,
  nonNegativeIntFromEnv,
} from "./demand-feed-cache.js";

// ─── SingleFlightTtlCache ────────────────────────────────────────────────────

test("SingleFlightTtlCache serves cached payload inside the TTL window", async () => {
  let nowMs = 0;
  let loads = 0;
  const cache = new SingleFlightTtlCache(
    async () => {
      loads += 1;
      return { loads };
    },
    60_000,
    () => nowMs,
  );

  assert.deepEqual(await cache.get(), { loads: 1 });
  nowMs = 59_999;
  assert.deepEqual(await cache.get(), { loads: 1 });
  assert.equal(loads, 1);
});

test("SingleFlightTtlCache reloads after the TTL expires", async () => {
  let nowMs = 0;
  let loads = 0;
  const cache = new SingleFlightTtlCache(
    async () => {
      loads += 1;
      return loads;
    },
    60_000,
    () => nowMs,
  );

  assert.equal(await cache.get(), 1);
  nowMs = 60_000;
  assert.equal(await cache.get(), 2);
  assert.equal(loads, 2);
});

test("SingleFlightTtlCache shares one in-flight load across concurrent callers", async () => {
  let loads = 0;
  let release: (value: string) => void = () => {};
  const cache = new SingleFlightTtlCache(
    () => {
      loads += 1;
      return new Promise<string>((resolve) => {
        release = resolve;
      });
    },
    60_000,
    () => 0,
  );

  const first = cache.get();
  const second = cache.get();
  release("payload");
  assert.equal(await first, "payload");
  assert.equal(await second, "payload");
  assert.equal(loads, 1);
});

test("SingleFlightTtlCache does not cache a failed load and retries next call", async () => {
  let loads = 0;
  const cache = new SingleFlightTtlCache(
    async () => {
      loads += 1;
      if (loads === 1) throw new Error("firestore_unavailable");
      return "recovered";
    },
    60_000,
    () => 0,
  );

  await assert.rejects(cache.get(), /firestore_unavailable/);
  assert.equal(await cache.get(), "recovered");
  assert.equal(loads, 2);
});

test("SingleFlightTtlCache with ttl 0 disables caching", async () => {
  let loads = 0;
  const cache = new SingleFlightTtlCache(
    async () => {
      loads += 1;
      return loads;
    },
    0,
    () => 0,
  );

  assert.equal(await cache.get(), 1);
  assert.equal(await cache.get(), 2);
  assert.equal(loads, 2);
});

// ─── isRefreshFresh ──────────────────────────────────────────────────────────

test("isRefreshFresh skips refreshes inside the freshness window", () => {
  const windowMs = DEFAULT_DEMAND_SNAPSHOT_REFRESH_FRESHNESS_MS;
  assert.equal(isRefreshFresh(0, windowMs - 1, windowMs), true);
  assert.equal(isRefreshFresh(0, windowMs, windowMs), false);
  assert.equal(isRefreshFresh(0, windowMs + 1, windowMs), false);
});

test("isRefreshFresh never skips without a completed refresh or with window 0", () => {
  assert.equal(isRefreshFresh(null, 1_000, 3_600_000), false);
  assert.equal(isRefreshFresh(999, 1_000, 0), false);
});

// ─── nonNegativeIntFromEnv ───────────────────────────────────────────────────

test("nonNegativeIntFromEnv parses valid values and falls back otherwise", () => {
  const name = "BLUEPRINT_DEMAND_FEED_CACHE_TTL_MS_TEST";
  const cases: Array<[string | undefined, number]> = [
    [undefined, DEFAULT_DEMAND_FEED_CACHE_TTL_MS],
    ["", DEFAULT_DEMAND_FEED_CACHE_TTL_MS],
    ["not-a-number", DEFAULT_DEMAND_FEED_CACHE_TTL_MS],
    ["-5", DEFAULT_DEMAND_FEED_CACHE_TTL_MS],
    ["2.5", DEFAULT_DEMAND_FEED_CACHE_TTL_MS],
    ["0", 0],
    ["30000", 30000],
  ];
  for (const [raw, expected] of cases) {
    if (raw === undefined) delete process.env[name];
    else process.env[name] = raw;
    assert.equal(nonNegativeIntFromEnv(name, DEFAULT_DEMAND_FEED_CACHE_TTL_MS), expected);
  }
  delete process.env[name];
});
