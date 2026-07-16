/**
 * referral-core
 *
 * Pure, dependency-free logic for the referral/payout money path so the
 * most sensitive calculations and request validation are unit-testable
 * without Firestore or the Functions runtime.
 */

import { timingSafeEqual } from "node:crypto";

export const COMMISSION_RATE = 0.1; // 10 % ongoing commission to referrer
export const FIRST_CAPTURE_BONUS_RATE = 0.1; // 10 % one-time bonus to referred user

export type ReferralStatus = "invited" | "signedUp" | "firstCapture" | "active";

export const REFERRAL_STATUSES: readonly ReferralStatus[] = [
  "invited",
  "signedUp",
  "firstCapture",
  "active",
];

/** Statuses that mean "this referred user has not yet had an approved capture". */
export function isPreFirstCaptureStatus(status: ReferralStatus): boolean {
  return status === "invited" || status === "signedUp";
}

export function nextReferralStatus(current: ReferralStatus): ReferralStatus {
  if (isPreFirstCaptureStatus(current)) return "firstCapture";
  return "active";
}

export function normalizeReferralStatus(raw: unknown): ReferralStatus {
  if (typeof raw !== "string") return "signedUp";
  // Tolerate historical snake_case writes ("signed_up", "first_capture").
  const collapsed = raw
    .trim()
    .replace(/_([a-z])/g, (_, ch: string) => ch.toUpperCase());
  return (REFERRAL_STATUSES as readonly string[]).includes(collapsed)
    ? (collapsed as ReferralStatus)
    : "signedUp";
}

export interface ReferralOutcome {
  referrerCommissionCents: number;
  referredUserBonusCents: number;
  newReferralStatus: ReferralStatus;
  isFirstCapture: boolean;
}

/**
 * Computes what a qualifying (approved/paid) capture pays the referrer and
 * — on the referred user's first qualifying capture — the referred user.
 * Returns null when the payout is not a positive integer number of cents,
 * so callers cannot accidentally credit from a malformed document.
 */
export function computeReferralOutcome(input: {
  payoutCents: unknown;
  currentReferralStatus: ReferralStatus;
}): ReferralOutcome | null {
  const { payoutCents, currentReferralStatus } = input;
  if (
    typeof payoutCents !== "number" ||
    !Number.isFinite(payoutCents) ||
    payoutCents <= 0
  ) {
    return null;
  }

  const wholeCents = Math.floor(payoutCents);
  if (wholeCents <= 0) return null;

  const isFirstCapture = isPreFirstCaptureStatus(currentReferralStatus);
  return {
    referrerCommissionCents: Math.floor(wholeCents * COMMISSION_RATE),
    referredUserBonusCents: isFirstCapture
      ? Math.floor(wholeCents * FIRST_CAPTURE_BONUS_RATE)
      : 0,
    newReferralStatus: nextReferralStatus(currentReferralStatus),
    isFirstCapture,
  };
}

// ─── Referral codes ──────────────────────────────────────────────────────────

const REFERRAL_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const REFERRAL_CODE_LENGTH = 6;
const REFERRAL_CODE_PATTERN = new RegExp(
  `^[${REFERRAL_CODE_ALPHABET}]{${REFERRAL_CODE_LENGTH}}$`,
);

/**
 * Mirrors the client normalizers (iOS ReferralService.normalizedReferralCode,
 * Android AuthRepository.extractReferralCode): 6 chars from the unambiguous
 * alphabet, upper-cased. Returns null for anything else.
 */
export function normalizeReferralCode(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  const code = raw.trim().toUpperCase();
  return REFERRAL_CODE_PATTERN.test(code) ? code : null;
}

// ─── updateCaptureStatus request parsing/authorization ───────────────────────

export const CAPTURE_STATUS_VALUES = [
  "submitted",
  "under_review",
  "approved",
  "paid",
  "needs_fix",
  "rejected",
] as const;

export type CaptureStatusValue = (typeof CAPTURE_STATUS_VALUES)[number];

export interface CaptureStatusUpdate {
  captureId: string;
  creatorId: string;
  status: CaptureStatusValue;
  payoutCents: number;
}

export type ParseResult<T> =
  | { ok: true; value: T }
  | { ok: false; error: string };

export function parseCaptureStatusUpdate(
  body: unknown,
): ParseResult<CaptureStatusUpdate> {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return { ok: false, error: "body must be a JSON object" };
  }
  const record = body as Record<string, unknown>;

  const captureId =
    typeof record.captureId === "string" ? record.captureId.trim() : "";
  if (!captureId) return { ok: false, error: "captureId is required" };

  const creatorId =
    typeof record.creatorId === "string" ? record.creatorId.trim() : "";
  if (!creatorId) return { ok: false, error: "creatorId is required" };

  const status = record.status;
  if (
    typeof status !== "string" ||
    !(CAPTURE_STATUS_VALUES as readonly string[]).includes(status)
  ) {
    return {
      ok: false,
      error: `status must be one of: ${CAPTURE_STATUS_VALUES.join(", ")}`,
    };
  }

  const payoutCents =
    typeof record.payoutCents === "number" && Number.isFinite(record.payoutCents)
      ? Math.max(0, Math.floor(record.payoutCents))
      : 0;

  return {
    ok: true,
    value: { captureId, creatorId, status: status as CaptureStatusValue, payoutCents },
  };
}

export function extractBearerToken(header: unknown): string | null {
  if (typeof header !== "string") return null;
  const match = /^Bearer\s+(.+)$/i.exec(header.trim());
  const token = match?.[1]?.trim();
  return token ? token : null;
}

export function timingSafeEqualStrings(a: string, b: string): boolean {
  const bufA = Buffer.from(a, "utf8");
  const bufB = Buffer.from(b, "utf8");
  if (bufA.length !== bufB.length) return false;
  return timingSafeEqual(bufA, bufB);
}

export interface AdminTokenClaims {
  admin?: unknown;
  role?: unknown;
  roles?: unknown;
}

/** Mirrors the firestore.rules isAdmin() helper for Functions-side checks. */
export function claimsGrantAdmin(claims: AdminTokenClaims): boolean {
  if (claims.admin === true) return true;
  if (typeof claims.role === "string" && ["admin", "ops"].includes(claims.role)) {
    return true;
  }
  if (Array.isArray(claims.roles)) {
    return claims.roles.some(
      (role) => role === "admin" || role === "ops",
    );
  }
  return false;
}

export type CaptureStatusAuthDecision =
  | { allowed: true; via: "shared_secret" | "admin_token" }
  | { allowed: false; reason: string };

/**
 * Authorizes a capture-status mutation. Fail-closed:
 *  - a configured shared secret must match exactly (timing-safe), or
 *  - a verifier-validated ID token must carry admin/ops claims.
 * With no secret configured and no verifier success, the request is denied.
 */
export async function authorizeCaptureStatusRequest(input: {
  authorizationHeader: unknown;
  sharedSecret: string | null | undefined;
  verifyIdToken: (token: string) => Promise<AdminTokenClaims>;
}): Promise<CaptureStatusAuthDecision> {
  const token = extractBearerToken(input.authorizationHeader);
  if (!token) {
    return { allowed: false, reason: "missing_bearer_token" };
  }

  const secret = input.sharedSecret?.trim();
  if (secret && timingSafeEqualStrings(token, secret)) {
    return { allowed: true, via: "shared_secret" };
  }

  try {
    const claims = await input.verifyIdToken(token);
    if (claimsGrantAdmin(claims)) {
      return { allowed: true, via: "admin_token" };
    }
    return { allowed: false, reason: "token_lacks_admin_claims" };
  } catch {
    return { allowed: false, reason: "token_verification_failed" };
  }
}
