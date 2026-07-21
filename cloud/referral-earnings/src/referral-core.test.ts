import test from "node:test";
import assert from "node:assert/strict";

import {
  DEFAULT_MAX_PAYOUT_CENTS,
  createRateLimiter,
  authorizeCaptureStatusRequest,
  claimsGrantAdmin,
  computeReferralOutcome,
  extractBearerToken,
  isPreFirstCaptureStatus,
  nextReferralStatus,
  normalizeReferralCode,
  normalizeReferralStatus,
  parseCaptureStatusUpdate,
  shouldAttemptReferralCredit,
  timingSafeEqualStrings,
} from "./referral-core.js";

// ─── shouldAttemptReferralCredit ─────────────────────────────────────────────

test("shouldAttemptReferralCredit attempts on any paying write until credited", () => {
  // First transition into approved.
  assert.equal(
    shouldAttemptReferralCredit({ newStatus: "approved", referralBonusProcessed: false }),
    true,
  );
  // Approve-then-pay flow: still uncredited when the real amount lands on the
  // later `paid` write (the historical edge-gating bug skipped this case).
  assert.equal(
    shouldAttemptReferralCredit({ newStatus: "paid", referralBonusProcessed: false }),
    true,
  );
});

test("shouldAttemptReferralCredit skips once credited or while not paying", () => {
  assert.equal(
    shouldAttemptReferralCredit({ newStatus: "paid", referralBonusProcessed: true }),
    false,
  );
  for (const status of ["submitted", "under_review", "needs_fix", "rejected", undefined]) {
    assert.equal(
      shouldAttemptReferralCredit({ newStatus: status, referralBonusProcessed: false }),
      false,
    );
  }
});

// ─── computeReferralOutcome ──────────────────────────────────────────────────

test("computeReferralOutcome pays 10% commission and first-capture bonus from signedUp", () => {
  const outcome = computeReferralOutcome({
    payoutCents: 2500,
    currentReferralStatus: "signedUp",
  });
  assert.ok(outcome);
  assert.equal(outcome.referrerCommissionCents, 250);
  assert.equal(outcome.referredUserBonusCents, 250);
  assert.equal(outcome.newReferralStatus, "firstCapture");
  assert.equal(outcome.isFirstCapture, true);
});

test("computeReferralOutcome treats invited as a pre-first-capture status", () => {
  const outcome = computeReferralOutcome({
    payoutCents: 1000,
    currentReferralStatus: "invited",
  });
  assert.ok(outcome);
  assert.equal(outcome.referredUserBonusCents, 100);
  assert.equal(outcome.isFirstCapture, true);
  assert.equal(outcome.newReferralStatus, "firstCapture");
});

test("computeReferralOutcome pays no bonus after the first capture", () => {
  for (const status of ["firstCapture", "active"] as const) {
    const outcome = computeReferralOutcome({
      payoutCents: 1000,
      currentReferralStatus: status,
    });
    assert.ok(outcome);
    assert.equal(outcome.referredUserBonusCents, 0);
    assert.equal(outcome.isFirstCapture, false);
    assert.equal(outcome.newReferralStatus, "active");
  }
});

test("computeReferralOutcome floors fractional cents", () => {
  const outcome = computeReferralOutcome({
    payoutCents: 999,
    currentReferralStatus: "active",
  });
  assert.ok(outcome);
  assert.equal(outcome.referrerCommissionCents, 99);
});

test("computeReferralOutcome rejects zero, negative, NaN, and non-numeric payouts", () => {
  for (const payoutCents of [0, -100, Number.NaN, Number.POSITIVE_INFINITY, "500", null, undefined]) {
    assert.equal(
      computeReferralOutcome({
        payoutCents,
        currentReferralStatus: "signedUp",
      }),
      null,
      `expected null for payoutCents=${String(payoutCents)}`,
    );
  }
});

// ─── status helpers ──────────────────────────────────────────────────────────

test("nextReferralStatus advances invited/signedUp to firstCapture, then active", () => {
  assert.equal(nextReferralStatus("invited"), "firstCapture");
  assert.equal(nextReferralStatus("signedUp"), "firstCapture");
  assert.equal(nextReferralStatus("firstCapture"), "active");
  assert.equal(nextReferralStatus("active"), "active");
});

test("isPreFirstCaptureStatus covers exactly invited and signedUp", () => {
  assert.equal(isPreFirstCaptureStatus("invited"), true);
  assert.equal(isPreFirstCaptureStatus("signedUp"), true);
  assert.equal(isPreFirstCaptureStatus("firstCapture"), false);
  assert.equal(isPreFirstCaptureStatus("active"), false);
});

test("normalizeReferralStatus tolerates snake_case and unknown values", () => {
  assert.equal(normalizeReferralStatus("signed_up"), "signedUp");
  assert.equal(normalizeReferralStatus("first_capture"), "firstCapture");
  assert.equal(normalizeReferralStatus("active"), "active");
  assert.equal(normalizeReferralStatus("garbage"), "signedUp");
  assert.equal(normalizeReferralStatus(undefined), "signedUp");
});

// ─── referral codes ──────────────────────────────────────────────────────────

test("normalizeReferralCode accepts valid 6-char codes case-insensitively", () => {
  assert.equal(normalizeReferralCode("abc234"), "ABC234");
  assert.equal(normalizeReferralCode("  XYZ789  "), "XYZ789");
});

test("normalizeReferralCode rejects ambiguous chars, wrong lengths, and non-strings", () => {
  assert.equal(normalizeReferralCode("ABC10O"), null); // 1, 0, O excluded
  assert.equal(normalizeReferralCode("ABCDE"), null);
  assert.equal(normalizeReferralCode("ABCDEFG"), null);
  assert.equal(normalizeReferralCode(""), null);
  assert.equal(normalizeReferralCode(123456), null);
  assert.equal(normalizeReferralCode(null), null);
});

// ─── payout ceiling + rate limiter ───────────────────────────────────────────

test("parseCaptureStatusUpdate rejects payouts above the ceiling", () => {
  const over = parseCaptureStatusUpdate({
    captureId: "cap-1",
    creatorId: "user-1",
    status: "paid",
    payoutCents: DEFAULT_MAX_PAYOUT_CENTS + 1,
  });
  assert.equal(over.ok, false);

  const custom = parseCaptureStatusUpdate(
    { captureId: "cap-1", creatorId: "user-1", status: "paid", payoutCents: 900 },
    1000,
  );
  assert.equal(custom.ok, true);

  const customOver = parseCaptureStatusUpdate(
    { captureId: "cap-1", creatorId: "user-1", status: "paid", payoutCents: 1100 },
    1000,
  );
  assert.equal(customOver.ok, false);
});

test("parseCaptureStatusUpdate allows payouts at exactly the ceiling", () => {
  const atCeiling = parseCaptureStatusUpdate({
    captureId: "cap-1",
    creatorId: "user-1",
    status: "paid",
    payoutCents: DEFAULT_MAX_PAYOUT_CENTS,
  });
  assert.equal(atCeiling.ok, true);
});

test("createRateLimiter enforces the fixed window per key", () => {
  const check = createRateLimiter({ limit: 3, windowMs: 1000 });
  const t0 = 1_000_000;
  assert.equal(check("a", t0), true);
  assert.equal(check("a", t0 + 1), true);
  assert.equal(check("a", t0 + 2), true);
  assert.equal(check("a", t0 + 3), false); // over limit inside window
  assert.equal(check("b", t0 + 3), true); // other keys unaffected
  assert.equal(check("a", t0 + 1000), true); // window rolled over
});

// ─── parseCaptureStatusUpdate ────────────────────────────────────────────────

test("parseCaptureStatusUpdate accepts a valid payload and floors payout cents", () => {
  const result = parseCaptureStatusUpdate({
    captureId: "cap-1",
    creatorId: "user-1",
    status: "approved",
    payoutCents: 1234.9,
  });
  assert.ok(result.ok);
  assert.deepEqual(result.value, {
    captureId: "cap-1",
    creatorId: "user-1",
    status: "approved",
    payoutCents: 1234,
  });
});

test("parseCaptureStatusUpdate rejects missing fields and invalid statuses", () => {
  assert.equal(parseCaptureStatusUpdate(null).ok, false);
  assert.equal(parseCaptureStatusUpdate([]).ok, false);
  assert.equal(
    parseCaptureStatusUpdate({ creatorId: "u", status: "approved" }).ok,
    false,
  );
  assert.equal(
    parseCaptureStatusUpdate({ captureId: "c", status: "approved" }).ok,
    false,
  );
  assert.equal(
    parseCaptureStatusUpdate({ captureId: "c", creatorId: "u", status: "fabricated" }).ok,
    false,
  );
});

test("parseCaptureStatusUpdate clamps negative payouts to zero", () => {
  const result = parseCaptureStatusUpdate({
    captureId: "c",
    creatorId: "u",
    status: "rejected",
    payoutCents: -500,
  });
  assert.ok(result.ok);
  assert.equal(result.value.payoutCents, 0);
});

// ─── auth ────────────────────────────────────────────────────────────────────

test("extractBearerToken parses Bearer headers and rejects everything else", () => {
  assert.equal(extractBearerToken("Bearer abc123"), "abc123");
  assert.equal(extractBearerToken("bearer abc123"), "abc123");
  assert.equal(extractBearerToken("Basic abc123"), null);
  assert.equal(extractBearerToken("Bearer "), null);
  assert.equal(extractBearerToken(undefined), null);
});

test("timingSafeEqualStrings compares without throwing on length mismatch", () => {
  assert.equal(timingSafeEqualStrings("secret", "secret"), true);
  assert.equal(timingSafeEqualStrings("secret", "secreT"), false);
  assert.equal(timingSafeEqualStrings("secret", "longer-secret"), false);
});

test("claimsGrantAdmin mirrors the firestore isAdmin() helper", () => {
  assert.equal(claimsGrantAdmin({ admin: true }), true);
  assert.equal(claimsGrantAdmin({ role: "admin" }), true);
  assert.equal(claimsGrantAdmin({ role: "ops" }), true);
  assert.equal(claimsGrantAdmin({ roles: ["ops"] }), true);
  assert.equal(claimsGrantAdmin({ roles: ["viewer"] }), false);
  assert.equal(claimsGrantAdmin({ admin: "true" }), false);
  assert.equal(claimsGrantAdmin({}), false);
});

test("authorizeCaptureStatusRequest allows a matching shared secret", async () => {
  const decision = await authorizeCaptureStatusRequest({
    authorizationHeader: "Bearer s3cret",
    sharedSecret: "s3cret",
    verifyIdToken: async () => {
      throw new Error("should not be called");
    },
  });
  assert.deepEqual(decision, { allowed: true, via: "shared_secret" });
});

test("authorizeCaptureStatusRequest allows a verified admin token", async () => {
  const decision = await authorizeCaptureStatusRequest({
    authorizationHeader: "Bearer some-id-token",
    sharedSecret: null,
    verifyIdToken: async () => ({ admin: true }),
  });
  assert.deepEqual(decision, { allowed: true, via: "admin_token" });
});

test("authorizeCaptureStatusRequest denies non-admin tokens", async () => {
  const decision = await authorizeCaptureStatusRequest({
    authorizationHeader: "Bearer some-id-token",
    sharedSecret: "unrelated-secret",
    verifyIdToken: async () => ({}),
  });
  assert.equal(decision.allowed, false);
});

test("authorizeCaptureStatusRequest denies when verification fails and no secret matches", async () => {
  const decision = await authorizeCaptureStatusRequest({
    authorizationHeader: "Bearer forged",
    sharedSecret: undefined,
    verifyIdToken: async () => {
      throw new Error("bad token");
    },
  });
  assert.equal(decision.allowed, false);
});

test("authorizeCaptureStatusRequest denies missing Authorization entirely", async () => {
  const decision = await authorizeCaptureStatusRequest({
    authorizationHeader: undefined,
    sharedSecret: "configured",
    verifyIdToken: async () => ({ admin: true }),
  });
  assert.equal(decision.allowed, false);
});
