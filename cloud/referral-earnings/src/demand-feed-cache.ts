/**
 * demand-feed-cache
 *
 * Scaling guards for the demand-opportunity surface (unit-tested here, wired
 * up in index.ts):
 *
 *   1. `SingleFlightTtlCache` — a module-level TTL cache for the shared feed
 *      inputs (demand signals + active capture jobs + strategic weights) so a
 *      burst of /v1/opportunities/feed requests performs one Firestore load
 *      per TTL window instead of three queries per request. Concurrent
 *      requests share a single in-flight load ("single-flight"). The feed is
 *      advisory UX, so bounded staleness is acceptable; per-request
 *      ranking/filtering still runs per caller.
 *
 *   2. `isRefreshFresh` — the freshness-window decision used to debounce
 *      `capture_jobs` demand-snapshot rewrites so public demand submissions
 *      cannot trigger a 200-doc batch rewrite per request.
 */

export const DEFAULT_DEMAND_FEED_CACHE_TTL_MS = 60_000;
export const DEFAULT_DEMAND_SNAPSHOT_REFRESH_FRESHNESS_MS = 60 * 60 * 1000;

/** Reads a non-negative integer from the environment, falling back on unset/invalid. */
export function nonNegativeIntFromEnv(name: string, fallback: number): number {
  const raw = process.env[name];
  if (!raw) return fallback;
  const parsed = Number(raw);
  if (!Number.isSafeInteger(parsed) || parsed < 0) return fallback;
  return parsed;
}

/**
 * TTL cache with single-flight loading. `ttlMs <= 0` disables caching entirely
 * (every `get()` calls the loader). A failed load is not cached: the in-flight
 * promise is shared by concurrent callers (they all see the failure), then
 * cleared so the next call retries.
 */
export class SingleFlightTtlCache<T> {
  private cached: { loadedAtMs: number; payload: T } | null = null;
  private inFlight: Promise<T> | null = null;

  constructor(
    private readonly loader: () => Promise<T>,
    private readonly ttlMs: number,
    private readonly now: () => number = Date.now,
  ) {}

  async get(): Promise<T> {
    if (this.ttlMs <= 0) return this.loader();
    const cached = this.cached;
    if (cached && this.now() - cached.loadedAtMs < this.ttlMs) {
      return cached.payload;
    }
    if (this.inFlight) return this.inFlight;
    const load = this.loader()
      .then((payload) => {
        this.cached = { loadedAtMs: this.now(), payload };
        return payload;
      })
      .finally(() => {
        this.inFlight = null;
      });
    this.inFlight = load;
    return load;
  }
}

/**
 * True when a completed refresh at `lastCompletedAtMs` is still inside the
 * freshness window at `nowMs` (so a new refresh should be skipped).
 * `freshnessWindowMs <= 0` disables debouncing (never fresh).
 */
export function isRefreshFresh(
  lastCompletedAtMs: number | null,
  nowMs: number,
  freshnessWindowMs: number,
): boolean {
  if (freshnessWindowMs <= 0) return false;
  if (lastCompletedAtMs === null) return false;
  return nowMs - lastCompletedAtMs < freshnessWindowMs;
}
