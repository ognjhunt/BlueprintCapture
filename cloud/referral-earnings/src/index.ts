/**
 * referral-earnings
 *
 * Fires whenever a `capture_submissions/{captureId}` document is written and
 * its `status` transitions to "approved" or "paid" for the first time.
 *
 * What it does:
 *   1. Checks whether the capturer was referred by another user (`referredBy` on user doc).
 *   2. Calculates a 10 % commission for the referrer on every qualifying payout.
 *   3. On the referred user's FIRST approved capture, also credits them with a
 *      10 % first-capture bonus (the "You'll both get 10% extra" promise).
 *   4. Advances the referral status:  signedUp → firstCapture → active.
 *   5. Stamps `referralBonusProcessedAt` on the capture document so re-runs are idempotent.
 *
 * Capture submission schema (written by backend when approving/paying):
 * {
 *   creator_id:   string,   // Firebase UID of the capturer
 *   status:       string,   // "approved" | "paid" | …
 *   payout_cents: number,   // base payout for this capture (before bonuses)
 *   …
 * }
 */

import crypto from "node:crypto";

import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { onRequest } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";
import { initializeApp, getApps } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import {
  authorizeCaptureStatusRequest,
  computeReferralOutcome,
  normalizeReferralCode,
  normalizeReferralStatus,
  parseCaptureStatusUpdate,
  shouldAttemptReferralCredit,
} from "./referral-core.js";
import {
  buildDemandSignalsForWebResearchFindings,
  buildStrategicWeightsFromSignals,
  fetchDailyResearchFindings,
} from "./autonomous-demand-research.js";
import {
  DEFAULT_DEMAND_FEED_CACHE_TTL_MS,
  DEFAULT_DEMAND_SNAPSHOT_REFRESH_FRESHNESS_MS,
  SingleFlightTtlCache,
  isRefreshFresh,
  nonNegativeIntFromEnv,
} from "./demand-feed-cache.js";
import {
  annotateCaptureJobs,
  buildDemandSignalsForRobotTeamRequest,
  buildDemandSignalsForSiteOperatorSubmission,
  type DemandOpportunityFeedRequest,
  rankNearbyOpportunitiesForFeed,
  sanitizeRobotTeamDemandPayload,
  sanitizeSiteOperatorDemandPayload,
  type CaptureJobApiRecord,
  type DemandSignalDocument,
  type StrategicWeightConfig,
} from "./demand-opportunities.js";
import {
  NearbyProxyError,
  proxyNearbyDiscovery,
  proxyPlaceDetails,
  proxyPlacesAutocomplete,
  type NearbyProxyAutocompleteRequest,
  type NearbyProxyDetailsRequest,
  type NearbyProxyDiscoveryRequest,
} from "./nearby-proxy.js";

if (getApps().length === 0) initializeApp();

const db = getFirestore();

// Scale-out bounds: no function here needs unbounded instances. HTTP surfaces
// and Firestore triggers cap at 20; scheduled jobs are singletons.
const HTTP_MAX_INSTANCES = 20;
const FIRESTORE_TRIGGER_MAX_INSTANCES = 20;
const SCHEDULED_MAX_INSTANCES = 1;

// Commission/bonus math lives in referral-core.ts so it stays unit-tested.

function operationalStateForCaptureStatus(status: string) {
  switch (status) {
    case "approved":
    case "paid":
      return {
        upload_state: "uploaded",
        qa_state: "reviewed",
        qa_outcome: "pass",
        repeat_ready: true,
      };
    case "needs_fix":
      return {
        upload_state: "uploaded",
        qa_state: "reviewed",
        qa_outcome: "borderline",
        repeat_ready: false,
      };
    case "rejected":
      return {
        upload_state: "uploaded",
        qa_state: "reviewed",
        qa_outcome: "fail",
        repeat_ready: false,
      };
    case "under_review":
      return {
        upload_state: "uploaded",
        qa_state: "under_review",
        repeat_ready: false,
      };
    default:
      return {
        upload_state: "uploaded",
        qa_state: "queued",
        repeat_ready: false,
      };
  }
}

function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
}

function asString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function asIsoString(value: unknown): string | null {
  if (!value) return null;
  if (typeof value === "string") {
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
  }
  if (value instanceof Timestamp) {
    return value.toDate().toISOString();
  }
  if (typeof value === "object" && value && "toDate" in value && typeof (value as { toDate: () => Date }).toDate === "function") {
    const parsed = (value as { toDate: () => Date }).toDate();
    return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
  }
  return null;
}

function slugifyCity(value: string): string {
  return value
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

function buildOperatingGraphEventId(input: {
  eventKey: string;
  stage: "capture_in_progress" | "capture_uploaded";
  recordedAtIso: string;
}) {
  return crypto
    .createHash("sha256")
    .update(`${input.eventKey}|${input.stage}|${input.recordedAtIso}`)
    .digest("hex")
    .slice(0, 32);
}

function captureRunEntityId(captureId: string) {
  return `capture_run:${captureId}`;
}

function deriveCaptureLifecycleStage(after: Record<string, unknown>) {
  const lifecycle = asRecord(after.lifecycle);
  const operationalState = asRecord(after.operational_state);
  const captureUploadedAtIso =
    asIsoString(lifecycle.capture_uploaded_at) || asIsoString(after.capture_uploaded_at);
  if (captureUploadedAtIso) {
    return {
      stage: "capture_uploaded" as const,
      recordedAtIso: captureUploadedAtIso,
      summary: "Capture uploaded and durably registered.",
    };
  }

  const captureStartedAtIso = asIsoString(lifecycle.capture_started_at);
  const uploadStartedAtIso = asIsoString(lifecycle.upload_started_at);
  const uploadState = asString(operationalState.upload_state);
  if (captureStartedAtIso || uploadStartedAtIso || ["uploading", "registering"].includes(uploadState)) {
    return {
      stage: "capture_in_progress" as const,
      recordedAtIso: uploadStartedAtIso || captureStartedAtIso || Timestamp.now().toDate().toISOString(),
      summary: "Capture is in progress and upload has started.",
    };
  }

  return null;
}

function buildCaptureCanonicalForeignKeys(after: Record<string, unknown>) {
  const cityContext = asRecord(after.city_context);
  const canonicalForeignKeys = Object.fromEntries(
    Object.entries({
      city_program_id: asString(cityContext.city_slug)
        ? `city_program:${asString(cityContext.city_slug)}:unscoped`
        : undefined,
      capture_id: asString(after.capture_id),
      capture_run_id: captureRunEntityId(asString(after.capture_id)),
      site_submission_id: asString(after.site_submission_id) || undefined,
      scene_id: asString(after.scene_id) || undefined,
      buyer_request_id: asString(after.buyer_request_id) || undefined,
      capture_job_id: asString(after.capture_job_id) || undefined,
    }).filter(([, value]) => value !== undefined),
  );
  return {
    capture_id: asString(after.capture_id),
    capture_run_id: captureRunEntityId(asString(after.capture_id)),
    site_submission_id: asString(after.site_submission_id),
    scene_id: asString(after.scene_id),
    buyer_request_id: asString(after.buyer_request_id),
    capture_job_id: asString(after.capture_job_id),
    canonical_foreign_keys: canonicalForeignKeys,
  };
}

async function syncCaptureLifecycleOperatingGraph(params: {
  captureId: string;
  before: Record<string, unknown> | undefined;
  after: Record<string, unknown>;
}) {
  const lifecycle = deriveCaptureLifecycleStage(params.after);
  if (!lifecycle) {
    return;
  }

  const beforeLifecycle = params.before ? deriveCaptureLifecycleStage(params.before) : null;
  if (
    beforeLifecycle?.stage === lifecycle.stage &&
    beforeLifecycle.recordedAtIso === lifecycle.recordedAtIso
  ) {
    return;
  }

  const cityContext = asRecord(params.after.city_context);
  const city = asString(cityContext.city);
  const citySlug = asString(cityContext.city_slug) || slugifyCity(city);
  if (!city || !citySlug) {
    logger.info("Skipping capture lifecycle operating-graph sync because city context is missing", {
      captureId: params.captureId,
      stage: lifecycle.stage,
    });
    return;
  }

  const entityId = captureRunEntityId(params.captureId);
  const metadata = buildCaptureCanonicalForeignKeys(params.after);
  const eventKey = `capture_lifecycle:${params.captureId}:${lifecycle.stage}`;
  const eventId = buildOperatingGraphEventId({
    eventKey,
    stage: lifecycle.stage,
    recordedAtIso: lifecycle.recordedAtIso,
  });

  const eventPayload = {
    id: eventId,
    event_key: eventKey,
    entity_type: "capture_run",
    entity_id: entityId,
    city,
    city_slug: citySlug,
    stage: lifecycle.stage,
    summary: lifecycle.summary,
    source_repo: "BlueprintCapture",
    source_kind: "capture_lifecycle",
    origin: {
      repo: "BlueprintCapture",
      sourceCollection: "capture_submissions",
      sourceDocId: params.captureId,
    },
    blocking_conditions: [],
    external_confirmations: [],
    next_actions: [],
    metadata,
    recorded_at_iso: lifecycle.recordedAtIso,
    recorded_at: lifecycle.recordedAtIso,
    updated_at: FieldValue.serverTimestamp(),
  };

  await db.collection("operatingGraphEvents").doc(eventId).set(eventPayload, { merge: true });

  const stateRef = db.collection("operatingGraphState").doc(entityId);
  const existingState = await stateRef.get();
  const current = existingState.exists ? asRecord(existingState.data()) : {};
  const currentLatestAtIso = asIsoString(current.latest_event_at_iso);
  const shouldPromoteCurrentStage =
    !currentLatestAtIso ||
    Date.parse(lifecycle.recordedAtIso) >= Date.parse(currentLatestAtIso);
  const stagesSeen = Array.from(
    new Set(
      [
        ...(Array.isArray(current.stages_seen) ? current.stages_seen.filter((value): value is string => typeof value === "string") : []),
        lifecycle.stage,
      ],
    ),
  );

  await stateRef.set(
    {
      state_key: entityId,
      entity_type: "capture_run",
      entity_id: entityId,
      city,
      city_slug: citySlug,
      stages_seen: stagesSeen,
      ...(shouldPromoteCurrentStage
        ? {
            current_stage: lifecycle.stage,
            latest_summary: lifecycle.summary,
            latest_source_repo: "BlueprintCapture",
            latest_event_id: eventId,
            latest_event_at_iso: lifecycle.recordedAtIso,
          }
        : {}),
      blocking_conditions: [],
      external_confirmations: [],
      next_actions: [],
      canonical_foreign_keys: metadata.canonical_foreign_keys,
      updated_at: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

export const onCaptureApproved = onDocumentWritten(
  {
    document: "capture_submissions/{captureId}",
    region: "us-central1",
    maxInstances: FIRESTORE_TRIGGER_MAX_INSTANCES,
  },
  async (event) => {
    const captureId = event.params.captureId;
    const after = event.data?.after?.data();

    if (!after) return; // document deleted — nothing to do

    const newStatus = after["status"] as string | undefined;

    // Cheap pre-check outside the transaction; the authoritative idempotency
    // guard is re-read inside the transaction below because Firestore triggers
    // are at-least-once and can be delivered concurrently.
    if (
      !shouldAttemptReferralCredit({
        newStatus,
        referralBonusProcessed: after["referralBonusProcessedAt"] !== undefined,
      })
    ) {
      return;
    }

    const captureRef = db.collection("capture_submissions").doc(captureId);

    const result = await db.runTransaction(async (tx) => {
      const captureSnap = await tx.get(captureRef);
      if (!captureSnap.exists) return { applied: false, reason: "capture_missing" };
      const capture = captureSnap.data() ?? {};

      if (capture["referralBonusProcessedAt"] !== undefined) {
        return { applied: false, reason: "already_processed" };
      }
      const status = capture["status"];
      if (status !== "approved" && status !== "paid") {
        return { applied: false, reason: "status_not_paying" };
      }

      const creatorId = capture["creator_id"] as string | undefined;
      if (!creatorId) {
        return { applied: false, reason: "missing_creator" };
      }

      // ── 1. Load the capturer's user document to find their referrer ────────
      const userRef = db.collection("users").doc(creatorId);
      const userSnap = await tx.get(userRef);
      if (!userSnap.exists) {
        logger.warn("Creator user document not found", { creatorId, captureId });
        return { applied: false, reason: "creator_user_missing" };
      }

      const referredBy = userSnap.data()?.["referredBy"] as string | undefined;
      if (!referredBy) {
        tx.update(captureRef, {
          referralBonusProcessedAt: FieldValue.serverTimestamp(),
          referralBonusSkippedReason: "no_referrer",
        });
        return { applied: false, reason: "no_referrer" };
      }

      // Server-side self-referral guard: never rely on the client for this.
      if (referredBy === creatorId) {
        tx.update(captureRef, {
          referralBonusProcessedAt: FieldValue.serverTimestamp(),
          referralBonusSkippedReason: "self_referral",
        });
        return { applied: false, reason: "self_referral" };
      }

      // ── 2. Load the referral record ─────────────────────────────────────────
      const referralRef = db
        .collection("users")
        .doc(referredBy)
        .collection("referrals")
        .doc(creatorId);
      const referralSnap = await tx.get(referralRef);
      if (!referralSnap.exists) {
        // Do NOT trust any field on the creator's own user document as proof
        // that `onUserProfileWritten` already validated this attribution —
        // firestore.rules only blocks client writes to `stats`, so a capturer
        // can self-write `referredBy` + any other field (including a forged
        // "already validated" marker) on their own doc. The only trustworthy
        // signal is the server-owned `referralCodes/{code}` lookup, which
        // clients cannot write at all (rules: `allow write: if false`). Heal
        // the missing record ONLY when that lookup independently confirms
        // `referredByCode` really does resolve to `referredBy`.
        const referredByCode = normalizeReferralCode(userSnap.data()?.["referredByCode"]);
        const codeLookupSnap = referredByCode
          ? await tx.get(db.collection("referralCodes").doc(referredByCode))
          : null;
        const codeOwnerId = codeLookupSnap?.exists ? codeLookupSnap.data()?.["ownerId"] : undefined;

        if (!referredByCode || codeOwnerId !== referredBy) {
          logger.warn("Referral record missing and attribution unverifiable via referralCodes", {
            referrerId: referredBy,
            referredUserId: creatorId,
            captureId,
            hasCode: Boolean(referredByCode),
          });
          tx.update(captureRef, {
            referralBonusProcessedAt: FieldValue.serverTimestamp(),
            referralBonusSkippedReason: "referral_record_missing",
          });
          return { applied: false, reason: "referral_record_missing" };
        }

        // Verified against server-owned data: safe to heal.
        logger.warn("Referral record missing for a code-verified attribution; healing", {
          referrerId: referredBy,
          referredUserId: creatorId,
          captureId,
        });
        const creatorName =
          [userSnap.data()?.["displayName"], userSnap.data()?.["name"]]
            .map((value) => (typeof value === "string" ? value.trim() : ""))
            .find((value) => value.length > 0) ?? "New capturer";
        tx.set(referralRef, {
          referredUserId: creatorId,
          referredUserName: creatorName,
          referredAt: FieldValue.serverTimestamp(),
          status: "signedUp",
          lifetimeEarningsCents: 0,
        });
      }

      // ── 3. Calculate amounts (pure, unit-tested) ────────────────────────────
      const currentReferralStatus = referralSnap.exists
        ? normalizeReferralStatus(referralSnap.data()?.["status"])
        : "signedUp";
      const outcome = computeReferralOutcome({
        payoutCents: capture["payout_cents"],
        currentReferralStatus,
      });
      if (!outcome) {
        logger.info("Skipping: payout_cents not a positive amount", {
          captureId,
          payoutCents: capture["payout_cents"],
        });
        return { applied: false, reason: "no_positive_payout" };
      }

      // ── 4. Apply all writes atomically within the transaction ──────────────
      tx.update(referralRef, {
        lifetimeEarningsCents: FieldValue.increment(outcome.referrerCommissionCents),
        status: outcome.newReferralStatus,
        lastEarningAt: FieldValue.serverTimestamp(),
      });

      // `stats.referralEarningsCents` is the canonical field for unpaid
      // referral commissions; the payout system reads this to include it
      // in the next disbursement.
      tx.update(db.collection("users").doc(referredBy), {
        "stats.referralEarningsCents": FieldValue.increment(
          outcome.referrerCommissionCents,
        ),
        updatedAt: FieldValue.serverTimestamp(),
      });

      if (outcome.referredUserBonusCents > 0) {
        tx.update(userRef, {
          "stats.referralBonusCents": FieldValue.increment(
            outcome.referredUserBonusCents,
          ),
          updatedAt: FieldValue.serverTimestamp(),
        });
      }

      tx.update(captureRef, {
        referralBonusProcessedAt: FieldValue.serverTimestamp(),
        referralBonusReferrerId: referredBy,
        referralBonusCommissionCents: outcome.referrerCommissionCents,
        referralBonusUserBonusCents: outcome.referredUserBonusCents,
      });

      return {
        applied: true,
        creatorId,
        referrerId: referredBy,
        referrerCommissionCents: outcome.referrerCommissionCents,
        referredUserBonusCents: outcome.referredUserBonusCents,
        newReferralStatus: outcome.newReferralStatus,
      };
    });

    if (result.applied) {
      logger.info("Referral bonus applied successfully", { captureId, ...result });
    } else {
      logger.info("Referral bonus not applied", { captureId, reason: result.reason });
    }
  }
);

/**
 * onUserProfileWritten — server-authoritative referral registration.
 *
 * Firestore rules intentionally block clients from writing to
 * `referralCodes/{code}` and `users/{referrerId}/referrals/{uid}`, so this
 * trigger performs both writes via the Admin SDK when a user updates their
 * own document (which rules do allow):
 *
 *  1. When `referralCode` is set/changed, registers the O(1) lookup doc
 *     `referralCodes/{code} → { ownerId }` (first writer wins on collisions).
 *  2. When `referredBy` is newly set, validates the attribution — the
 *     accompanying `referredByCode` must resolve to the claimed referrer and
 *     self-referrals are rejected — then creates the referral record the
 *     payout trigger reads. Invalid attributions are cleared so
 *     `onCaptureApproved` can never pay an unverified referrer.
 */
export const onUserProfileWritten = onDocumentWritten(
  {
    document: "users/{userId}",
    region: "us-central1",
    maxInstances: FIRESTORE_TRIGGER_MAX_INSTANCES,
  },
  async (event) => {
    const userId = event.params.userId;
    const before = event.data?.before?.data() as Record<string, unknown> | undefined;
    const after = event.data?.after?.data() as Record<string, unknown> | undefined;
    if (!after) return; // deleted

    // ── 1. Referral-code lookup registration ────────────────────────────────
    // Runs when the code changes OR when the registration stamp is missing, so
    // codes that predate this trigger self-heal on the user's next doc write.
    const afterCode = normalizeReferralCode(after["referralCode"]);
    const beforeCode = normalizeReferralCode(before?.["referralCode"]);
    const needsCodeRegistration =
      afterCode !== null &&
      (afterCode !== beforeCode || after["referralCodeRegisteredAt"] === undefined);
    if (afterCode && needsCodeRegistration) {
      const lookupRef = db.collection("referralCodes").doc(afterCode);
      const ownerRef = db.collection("users").doc(userId);
      await db.runTransaction(async (tx) => {
        const lookupSnap = await tx.get(lookupRef);
        if (!lookupSnap.exists) {
          tx.set(lookupRef, {
            ownerId: userId,
            createdAt: FieldValue.serverTimestamp(),
          });
          tx.update(ownerRef, {
            referralCodeRegisteredAt: FieldValue.serverTimestamp(),
          });
          return;
        }
        const ownerId = lookupSnap.data()?.["ownerId"];
        if (ownerId === userId) {
          tx.update(ownerRef, {
            referralCodeRegisteredAt: FieldValue.serverTimestamp(),
          });
        } else {
          logger.warn("Referral code collision; keeping original owner", {
            code: afterCode,
            ownerId,
            claimantId: userId,
          });
          // Stamp anyway (with the collision marker) so this user's future
          // doc writes stop re-running the registration transaction.
          tx.update(ownerRef, {
            referralCodeRegisteredAt: FieldValue.serverTimestamp(),
            referralCodeCollision: true,
          });
        }
      });
    }

    // ── 2. Referral attribution ──────────────────────────────────────────────
    const referredBy = typeof after["referredBy"] === "string" ? after["referredBy"].trim() : "";
    const beforeReferredBy =
      typeof before?.["referredBy"] === "string" ? (before["referredBy"] as string).trim() : "";
    if (!referredBy || referredBy === beforeReferredBy) return;
    if (after["referralAttributionProcessedAt"] !== undefined) return;

    const userRef = db.collection("users").doc(userId);

    const invalidate = (reason: string) =>
      db.runTransaction(async (tx) => {
        const snap = await tx.get(userRef);
        if (!snap.exists) return;
        if ((snap.data()?.["referredBy"] as string | undefined)?.trim() !== referredBy) return;
        tx.update(userRef, {
          referredBy: FieldValue.delete(),
          referredByCode: FieldValue.delete(),
          referralAttributionProcessedAt: FieldValue.serverTimestamp(),
          referralAttributionInvalidReason: reason,
        });
        logger.warn("Cleared invalid referral attribution", { userId, referredBy, reason });
      });

    if (referredBy === userId) {
      await invalidate("self_referral");
      return;
    }

    const claimedCode = normalizeReferralCode(after["referredByCode"]);
    if (!claimedCode) {
      await invalidate("missing_or_invalid_code");
      return;
    }

    await db.runTransaction(async (tx) => {
      const userSnap = await tx.get(userRef);
      const user = userSnap.data() ?? {};
      const currentReferredBy =
        typeof user["referredBy"] === "string" ? (user["referredBy"] as string).trim() : "";
      if (currentReferredBy !== referredBy) return; // changed since event fired
      if (user["referralAttributionProcessedAt"] !== undefined) return;

      // All transaction reads must complete before the first write.
      const referrerRef = db.collection("users").doc(referredBy);
      const lookupRef = db.collection("referralCodes").doc(claimedCode);
      const referralRef = referrerRef.collection("referrals").doc(userId);
      const referrerSnap = await tx.get(referrerRef);
      const lookupSnap = await tx.get(lookupRef);
      const referralSnap = await tx.get(referralRef);

      const clearInvalidAttribution = (reason: string) =>
        tx.update(userRef, {
          referredBy: FieldValue.delete(),
          referredByCode: FieldValue.delete(),
          referralAttributionProcessedAt: FieldValue.serverTimestamp(),
          referralAttributionInvalidReason: reason,
        });

      if (!referrerSnap.exists) {
        clearInvalidAttribution("referrer_missing");
        return;
      }

      const lookupOwner = lookupSnap.exists ? lookupSnap.data()?.["ownerId"] : undefined;
      const referrerOwnCode = normalizeReferralCode(referrerSnap.data()?.["referralCode"]);
      const codeResolvesToReferrer =
        lookupOwner === referredBy || (!lookupSnap.exists && referrerOwnCode === claimedCode);

      if (!codeResolvesToReferrer) {
        clearInvalidAttribution("code_owner_mismatch");
        return;
      }

      // Backfill the lookup doc when the code predates lookup registration.
      if (!lookupSnap.exists) {
        tx.set(lookupRef, {
          ownerId: referredBy,
          createdAt: FieldValue.serverTimestamp(),
        });
      }

      if (!referralSnap.exists) {
        const displayName =
          [user["displayName"], user["name"], user["fullName"]]
            .map((value) => (typeof value === "string" ? value.trim() : ""))
            .find((value) => value.length > 0) ?? "New capturer";
        tx.set(referralRef, {
          referredUserId: userId,
          referredUserName: displayName,
          referredAt: FieldValue.serverTimestamp(),
          status: "signedUp",
          lifetimeEarningsCents: 0,
        });
      }

      tx.update(userRef, {
        referralAttributionProcessedAt: FieldValue.serverTimestamp(),
      });
    });

    logger.info("Referral attribution processed", { userId, referredBy });
  },
);

export const syncCaptureLifecycleToOperatingGraph = onDocumentWritten(
  {
    document: "capture_submissions/{captureId}",
    region: "us-central1",
    maxInstances: FIRESTORE_TRIGGER_MAX_INSTANCES,
  },
  async (event) => {
    const captureId = event.params.captureId;
    const before = event.data?.before?.data() as Record<string, unknown> | undefined;
    const after = event.data?.after?.data() as Record<string, unknown> | undefined;
    if (!after) {
      return;
    }

    await syncCaptureLifecycleOperatingGraph({
      captureId,
      before,
      after,
    });
  },
);

/**
 * updateCaptureStatus — HTTP endpoint for the backend API to call when a
 * capture is approved or paid. Writes/updates the `capture_submissions`
 * document, which automatically triggers `onCaptureApproved` above.
 *
 * POST /updateCaptureStatus
 * Headers: Authorization: Bearer <shared service secret OR Firebase ID token with admin/ops claims>
 * Body: {
 *   captureId:  string,   // Firestore document ID (= CaptureBundleContext.captureIdentifier)
 *   creatorId:  string,   // Firebase UID of the capturer
 *   status:     "submitted" | "under_review" | "approved" | "paid" | "rejected" | "needs_fix",
 *   payoutCents: number,  // final payout amount in cents (0 for non-paying statuses)
 * }
 *
 * AUTH IS MANDATORY AND FAIL-CLOSED. This endpoint mutates payout state and
 * triggers referral commissions, so unauthenticated access would let anyone
 * fabricate payouts. Configure the shared secret via the
 * CAPTURE_STATUS_UPDATE_SECRET environment variable (Functions secret/env),
 * or call with an admin-claimed Firebase ID token.
 */
export const updateCaptureStatus = onRequest(
  { region: "us-central1", maxInstances: HTTP_MAX_INSTANCES },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method not allowed" });
      return;
    }

    const decision = await authorizeCaptureStatusRequest({
      authorizationHeader: req.headers.authorization,
      sharedSecret: process.env.CAPTURE_STATUS_UPDATE_SECRET ?? null,
      verifyIdToken: async (token) => {
        const decoded = await getAuth().verifyIdToken(token);
        return decoded as Record<string, unknown>;
      },
    });
    if (!decision.allowed) {
      logger.warn("updateCaptureStatus rejected", { reason: decision.reason });
      res.status(401).json({ error: "Unauthorized" });
      return;
    }

    const parsed = parseCaptureStatusUpdate(req.body);
    if (!parsed.ok) {
      res.status(400).json({ error: parsed.error });
      return;
    }
    const { captureId, creatorId, status } = parsed.value;
    const cents = parsed.value.payoutCents;

    const docRef = db.collection("capture_submissions").doc(captureId);
    const update: Record<string, unknown> = {
      creator_id: creatorId,
      status,
      payout_cents: cents,
      updated_at: Timestamp.now(),
    };
    const operationalState = operationalStateForCaptureStatus(status);
    for (const [key, value] of Object.entries(operationalState)) {
      update[`operational_state.${key}`] = value;
    }

    // Only stamp approved_at / paid_at on the relevant transitions
    if (status === "approved") update["approved_at"] = Timestamp.now();
    if (status === "paid") update["paid_at"] = Timestamp.now();
    if (status === "approved" || status === "paid" || status === "needs_fix" || status === "rejected") {
      update["qa_reviewed_at"] = Timestamp.now();
    }

    try {
      await docRef.set(update, { merge: true });
      logger.info("capture_submissions updated", { captureId, creatorId, status, cents });
      res.status(200).json({ ok: true, captureId, status });
    } catch (err) {
      logger.error("Failed to update capture_submissions", { captureId, err });
      res.status(500).json({ error: "Internal error" });
    }
  }
);

type FirestoreJobDoc = { id: string; data: Record<string, unknown> };
type JsonResponse = {
  status(code: number): JsonResponse;
  json(body: unknown): void;
};

function parseRequestBody<T>(body: unknown): T | null {
  if (!body || typeof body !== "object" || Array.isArray(body)) return null;
  return body as T;
}

function requestPath(req: { path?: string; url?: string; originalUrl?: string }): string {
  const rawPath = req.path ?? req.originalUrl ?? req.url ?? "/";
  return rawPath.split("?")[0] ?? "/";
}

function proxyErrorOptions() {
  return {
    placesApiKey: process.env.BLUEPRINT_GOOGLE_PLACES_API_KEY
      ?? process.env.GOOGLE_PLACES_API_KEY
      ?? process.env.PLACES_API_KEY
      ?? null,
    geminiApiKey: process.env.BLUEPRINT_GEMINI_API_KEY
      ?? process.env.GEMINI_API_KEY
      ?? process.env.GOOGLE_AI_API_KEY
      ?? process.env.GEMINI_MAPS_API_KEY
      ?? null,
    geminiModel: process.env.BLUEPRINT_GEMINI_MAPS_GROUNDING_MODEL ?? null,
  };
}

function sendProxyError(res: JsonResponse, error: unknown): void {
  if (error instanceof NearbyProxyError) {
    res.status(error.statusCode).json({
      error: error.code,
      message: error.message,
    });
    return;
  }

  res.status(500).json({ error: "internal_error" });
}

async function loadActiveDemandSignals(): Promise<DemandSignalDocument[]> {
  const snapshot = await db.collection("demand_signals").limit(500).get();
  return snapshot.docs.map((doc) => {
    const data = doc.data();
    const expiresAtRaw = data["freshness_expires_at"];
    const freshnessExpiresAt =
      expiresAtRaw instanceof Timestamp
        ? expiresAtRaw.toDate().toISOString()
        : typeof expiresAtRaw === "string"
          ? expiresAtRaw
          : undefined;

    return {
      id: doc.id,
      source_type: String(data["source_type"] ?? "unknown"),
      source_ref: typeof data["source_ref"] === "string" ? data["source_ref"] : undefined,
      site_type: String(data["site_type"] ?? "unknown"),
      workflow: typeof data["workflow"] === "string" ? data["workflow"] : undefined,
      company_id: typeof data["company_id"] === "string" ? data["company_id"] : undefined,
      geo_scope: typeof data["geo_scope"] === "string" ? data["geo_scope"] : undefined,
      strength:
        data["strength"] === "critical" ||
        data["strength"] === "high" ||
        data["strength"] === "medium" ||
        data["strength"] === "low"
          ? data["strength"]
          : "medium",
      confidence: typeof data["confidence"] === "number" ? data["confidence"] : 0.7,
      freshness_expires_at: freshnessExpiresAt,
      citations: Array.isArray(data["citations"]) ? data["citations"].filter((v): v is string => typeof v === "string") : [],
      demand_source_kinds: Array.isArray(data["demand_source_kinds"])
        ? data["demand_source_kinds"].filter((v): v is DemandSignalDocument["demand_source_kinds"][number] => typeof v === "string")
        : ["inferred_signal"],
      summary: typeof data["summary"] === "string" ? data["summary"] : undefined,
    } satisfies DemandSignalDocument;
  });
}

async function loadStrategicWeights(): Promise<StrategicWeightConfig | undefined> {
  const snapshot = await db.collection("demand_strategic_weights").doc("current").get();
  if (!snapshot.exists) return undefined;

  const data = snapshot.data() ?? {};
  const numberRecordFromUnknown = (value: unknown): Record<string, number> => {
    if (!value || typeof value !== "object") return {};
    const entries = Object.entries(value as Record<string, unknown>)
      .filter(([, item]) => typeof item === "number")
      .map(([key, item]) => [key, item as number] satisfies [string, number]);
    return Object.fromEntries(entries);
  };

  return {
    generated_at:
      data["generated_at"] instanceof Timestamp
        ? data["generated_at"].toDate().toISOString()
        : typeof data["generated_at"] === "string"
          ? data["generated_at"]
          : undefined,
    source_run_id: typeof data["source_run_id"] === "string" ? data["source_run_id"] : undefined,
    site_type_weights: numberRecordFromUnknown(data["site_type_weights"]),
    workflow_weights: numberRecordFromUnknown(data["workflow_weights"]),
  } satisfies StrategicWeightConfig;
}

async function loadActiveCaptureJobs(): Promise<FirestoreJobDoc[]> {
  const snapshot = await db.collection("capture_jobs").where("active", "==", true).limit(200).get();
  return snapshot.docs.map((doc) => ({ id: doc.id, data: doc.data() as Record<string, unknown> }));
}

type DemandFeedInputs = {
  signals: DemandSignalDocument[];
  jobs: FirestoreJobDoc[];
  strategicWeights: StrategicWeightConfig | undefined;
};

// Shared feed inputs are identical for every caller; per-request ranking and
// filtering (which use the caller's location) still run per request in
// handleDemandOpportunityFeed. The feed is advisory UX, so a short TTL of
// staleness is acceptable. Set BLUEPRINT_DEMAND_FEED_CACHE_TTL_MS=0 to disable.
const demandFeedInputsCache = new SingleFlightTtlCache<DemandFeedInputs>(
  async () => {
    const [signals, jobs, strategicWeights] = await Promise.all([
      loadActiveDemandSignals(),
      loadActiveCaptureJobs(),
      loadStrategicWeights(),
    ]);
    return { signals, jobs, strategicWeights };
  },
  nonNegativeIntFromEnv("BLUEPRINT_DEMAND_FEED_CACHE_TTL_MS", DEFAULT_DEMAND_FEED_CACHE_TTL_MS),
);

// Debounce for capture_jobs demand-snapshot rewrites triggered by public
// demand submissions. The module variable short-circuits repeat refreshes on
// a warm instance; the Firestore marker doc is a best-effort cross-instance
// guard (a rare double refresh is acceptable, a refresh per submission is not).
// Scheduled refreshes stay unconditional. Set
// BLUEPRINT_DEMAND_SNAPSHOT_REFRESH_FRESHNESS_MS=0 to disable the debounce.
const DEMAND_SNAPSHOT_REFRESH_FRESHNESS_MS = nonNegativeIntFromEnv(
  "BLUEPRINT_DEMAND_SNAPSHOT_REFRESH_FRESHNESS_MS",
  DEFAULT_DEMAND_SNAPSHOT_REFRESH_FRESHNESS_MS,
);
const DEMAND_SNAPSHOT_REFRESH_MARKER_PATH = "demand_refresh_state/capture_jobs_snapshots";
let lastDemandSnapshotRefreshCompletedAtMs: number | null = null;

async function recordDemandSnapshotRefreshCompleted(nowMs: number): Promise<void> {
  lastDemandSnapshotRefreshCompletedAtMs = nowMs;
  try {
    await db.doc(DEMAND_SNAPSHOT_REFRESH_MARKER_PATH).set(
      {
        last_refresh_completed_at: Timestamp.fromMillis(nowMs),
        updated_at: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  } catch (error) {
    logger.warn("Failed to write demand snapshot refresh marker (best-effort)", { error });
  }
}

// Concurrent submissions on a warm instance share one in-flight refresh
// instead of each rewriting up to 200 capture_jobs; cross-instance overlap
// remains best-effort via the marker doc.
let demandSnapshotRefreshInFlight: Promise<void> | null = null;

async function refreshCaptureJobDemandSnapshotsIfStale(): Promise<void> {
  const nowMs = Date.now();
  if (
    isRefreshFresh(lastDemandSnapshotRefreshCompletedAtMs, nowMs, DEMAND_SNAPSHOT_REFRESH_FRESHNESS_MS)
  ) {
    return;
  }
  if (demandSnapshotRefreshInFlight) {
    return demandSnapshotRefreshInFlight;
  }
  demandSnapshotRefreshInFlight = (async () => {
    try {
      const marker = await db.doc(DEMAND_SNAPSHOT_REFRESH_MARKER_PATH).get();
      const completedAt = marker.data()?.["last_refresh_completed_at"];
      if (completedAt instanceof Timestamp) {
        const completedAtMs = completedAt.toMillis();
        lastDemandSnapshotRefreshCompletedAtMs = Math.max(
          lastDemandSnapshotRefreshCompletedAtMs ?? 0,
          completedAtMs,
        );
        if (isRefreshFresh(completedAtMs, nowMs, DEMAND_SNAPSHOT_REFRESH_FRESHNESS_MS)) return;
      }
    } catch (error) {
      logger.warn("Failed to read demand snapshot refresh marker (best-effort)", { error });
    }
    const [activeSignals, strategicWeights] = await Promise.all([
      loadActiveDemandSignals(),
      loadStrategicWeights(),
    ]);
    await refreshCaptureJobDemandSnapshots(activeSignals, strategicWeights);
  })().finally(() => {
    demandSnapshotRefreshInFlight = null;
  });
  return demandSnapshotRefreshInFlight;
}

async function refreshCaptureJobDemandSnapshots(
  signals: DemandSignalDocument[],
  strategicWeights?: StrategicWeightConfig,
): Promise<void> {
  const jobs = await loadActiveCaptureJobs();
  if (jobs.length === 0) {
    await recordDemandSnapshotRefreshCompleted(Date.now());
    return;
  }

  // Viewer-independent refresh: no origin, so every active job nationwide is
  // scored on demand/priority/payout and none is excluded by distance from a
  // fixed reference point. (Per-request feeds still rank by the caller's
  // real location in demandOpportunityFeed.)
  const annotated = annotateCaptureJobs(
    jobs,
    signals,
    null,
    Number.POSITIVE_INFINITY,
    200,
    strategicWeights,
  );

  const byId = new Map<string, CaptureJobApiRecord>(annotated.map((job) => [job.id, job]));
  const batch = db.batch();
  let updateCount = 0;

  for (const job of jobs) {
    const annotation = byId.get(job.id);
    if (!annotation) continue;
    batch.set(
      db.collection("capture_jobs").doc(job.id),
      {
        site_type: annotation.siteType ?? null,
        demand_score: annotation.demandScore ?? null,
        opportunity_score: annotation.opportunityScore ?? null,
        demand_summary: annotation.demandSummary ?? null,
        ranking_explanation: annotation.rankingExplanation ?? null,
        demand_source_kinds: annotation.demandSourceKinds,
        suggested_workflows: annotation.suggestedWorkflows,
        updated_at: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    updateCount += 1;
  }

  if (updateCount > 0) {
    await batch.commit();
    logger.info("capture_jobs demand snapshots refreshed", { updatedJobs: updateCount });
  }
  // Every completed refresh (submission-driven or scheduled) stamps the marker
  // so submission-driven refreshes debounce off the most recent completion.
  await recordDemandSnapshotRefreshCompleted(Date.now());
}

async function writeDemandSignals(
  signals: DemandSignalDocument[],
  createdAt: Timestamp,
  extraFields: Record<string, unknown> = {},
): Promise<void> {
  if (signals.length === 0) return;

  const batch = db.batch();
  for (const signal of signals) {
    batch.set(db.collection("demand_signals").doc(signal.id), {
      ...signal,
      ...extraFields,
      created_at: createdAt,
      updated_at: createdAt,
      freshness_expires_at: signal.freshness_expires_at ? Timestamp.fromDate(new Date(signal.freshness_expires_at)) : null,
    }, { merge: true });
  }
  await batch.commit();
}

async function handleSubmitRobotTeamDemand(
  req: { method?: string; body?: unknown },
  res: JsonResponse,
): Promise<void> {
  if (req.method !== "POST") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }

  // This endpoint is publicly reachable — persist only the bounded,
  // allowlisted payload, never the raw request body.
  const payload = sanitizeRobotTeamDemandPayload(parseRequestBody<unknown>(req.body));
  if (!payload) {
    res.status(400).json({ error: "company_name and site_types are required" });
    return;
  }

  const submissionRef = db.collection("robot_team_requests").doc();
  const createdAt = Timestamp.now();
  const signals = buildDemandSignalsForRobotTeamRequest(submissionRef.id, payload);

  try {
    await submissionRef.set({
      ...payload,
      created_at: createdAt,
      updated_at: createdAt,
      source_type: "robot_team_request",
    });
    await writeDemandSignals(signals, createdAt);
    await refreshCaptureJobDemandSnapshotsIfStale();
    res.status(201).json({
      submission_id: submissionRef.id,
      demand_signal_ids: signals.map((signal) => signal.id),
      created_at: createdAt.toDate().toISOString(),
    });
  } catch (error) {
    logger.error("Failed to persist robot team demand request", { error });
    res.status(500).json({ error: "Internal error" });
  }
}

async function handleSubmitSiteOperatorDemand(
  req: { method?: string; body?: unknown },
  res: JsonResponse,
): Promise<void> {
  if (req.method !== "POST") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }

  // Publicly reachable — persist only the bounded, allowlisted payload.
  const payload = sanitizeSiteOperatorDemandPayload(parseRequestBody<unknown>(req.body));
  if (!payload) {
    res.status(400).json({ error: "operator_name, site_name, site_address, and site_types are required" });
    return;
  }

  const submissionRef = db.collection("site_operator_submissions").doc();
  const createdAt = Timestamp.now();
  const signals = buildDemandSignalsForSiteOperatorSubmission(submissionRef.id, payload);

  try {
    await submissionRef.set({
      ...payload,
      created_at: createdAt,
      updated_at: createdAt,
      source_type: "site_operator_submission",
    });
    await writeDemandSignals(signals, createdAt);
    await refreshCaptureJobDemandSnapshotsIfStale();
    res.status(201).json({
      submission_id: submissionRef.id,
      demand_signal_ids: signals.map((signal) => signal.id),
      created_at: createdAt.toDate().toISOString(),
    });
  } catch (error) {
    logger.error("Failed to persist site operator demand submission", { error });
    res.status(500).json({ error: "Internal error" });
  }
}

async function handleDemandOpportunityFeed(
  req: { method?: string; body?: unknown },
  res: JsonResponse,
): Promise<void> {
  if (req.method !== "POST") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }

  const payload = parseRequestBody<DemandOpportunityFeedRequest>(req.body);
  if (!payload || typeof payload.lat !== "number" || typeof payload.lng !== "number") {
    res.status(400).json({ error: "lat and lng are required" });
    return;
  }

  try {
    const { signals, jobs, strategicWeights } = await demandFeedInputsCache.get();
    const radiusMeters = Math.max(100, Math.min(payload.radius_m ?? 16093, 160934));
    const limit = Math.max(1, Math.min(payload.limit ?? 25, 200));
    const captureJobs = annotateCaptureJobs(
      jobs,
      signals,
      { lat: payload.lat, lng: payload.lng },
      radiusMeters,
      limit,
      strategicWeights,
    );
    const nearbyOpportunities = await rankNearbyOpportunitiesForFeed(
      payload,
      signals,
      strategicWeights,
    );

    res.status(200).json({
      generated_at: new Date().toISOString(),
      nearby_opportunities: nearbyOpportunities,
      capture_jobs: captureJobs,
    });
  } catch (error) {
    logger.error("Failed to generate demand opportunity feed", { error });
    res.status(500).json({ error: "Internal error" });
  }
}

async function handleNearbyDiscoveryProxy(
  req: { method?: string; body?: unknown },
  res: JsonResponse,
): Promise<void> {
  if (req.method !== "POST") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }

  const payload = parseRequestBody<NearbyProxyDiscoveryRequest>(req.body);
  if (!payload || typeof payload.lat !== "number" || typeof payload.lng !== "number") {
    res.status(400).json({ error: "lat and lng are required" });
    return;
  }

  try {
    const response = await proxyNearbyDiscovery(payload, proxyErrorOptions());
    logger.info("Nearby discovery proxied", {
      provider_hint: payload.provider_hint ?? "places_nearby",
      provider_used: response.provider_used,
      fallback_used: response.fallback_used,
      place_count: response.places.length,
    });
    res.status(200).json(response);
  } catch (error) {
    logger.error("Nearby discovery proxy failed", {
      provider_hint: payload.provider_hint ?? "places_nearby",
      error,
    });
    sendProxyError(res, error);
  }
}

async function handlePlacesAutocompleteProxy(
  req: { method?: string; body?: unknown },
  res: JsonResponse,
): Promise<void> {
  if (req.method !== "POST") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }

  const payload = parseRequestBody<NearbyProxyAutocompleteRequest>(req.body);
  if (!payload?.query || typeof payload.query !== "string") {
    res.status(400).json({ error: "query is required" });
    return;
  }

  try {
    const response = await proxyPlacesAutocomplete(payload, proxyErrorOptions());
    logger.info("Places autocomplete proxied", {
      suggestion_count: response.suggestions.length,
    });
    res.status(200).json(response);
  } catch (error) {
    logger.error("Places autocomplete proxy failed", { error });
    sendProxyError(res, error);
  }
}

async function handlePlacesDetailsProxy(
  req: { method?: string; body?: unknown },
  res: JsonResponse,
): Promise<void> {
  if (req.method !== "POST") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }

  const payload = parseRequestBody<NearbyProxyDetailsRequest>(req.body);
  if (!payload || !Array.isArray(payload.place_ids) || payload.place_ids.length === 0) {
    res.status(400).json({ error: "place_ids is required" });
    return;
  }

  try {
    const response = await proxyPlaceDetails(payload, proxyErrorOptions());
    logger.info("Places details proxied", {
      place_count: response.places.length,
    });
    res.status(200).json(response);
  } catch (error) {
    logger.error("Places details proxy failed", { error });
    sendProxyError(res, error);
  }
}

async function runDailyDemandResearch(now: Date = new Date()): Promise<void> {
  const runRef = db.collection("demand_research_runs").doc();
  const startedAt = Timestamp.fromDate(now);
  await runRef.set({
    run_type: "daily_web_research",
    status: "running",
    created_at: startedAt,
    updated_at: startedAt,
  });

  try {
    const research = await fetchDailyResearchFindings(fetch, now);
    const signals = buildDemandSignalsForWebResearchFindings(runRef.id, research.findings, now);
    const batch = db.batch();

    for (const finding of research.findings) {
      batch.set(db.collection("demand_research_findings").doc(finding.id), {
        ...finding,
        research_run_id: runRef.id,
        created_at: startedAt,
        updated_at: startedAt,
        published_at: finding.published_at ? Timestamp.fromDate(new Date(finding.published_at)) : null,
      }, { merge: true });
    }

    await batch.commit();
    await writeDemandSignals(signals, startedAt, { research_run_id: runRef.id });

    const [activeSignals, strategicWeights] = await Promise.all([
      loadActiveDemandSignals(),
      loadStrategicWeights(),
    ]);
    await refreshCaptureJobDemandSnapshots(activeSignals, strategicWeights);

    await runRef.set({
      status: "succeeded",
      article_count: research.articles.length,
      finding_count: research.findings.length,
      demand_signal_count: signals.length,
      updated_at: FieldValue.serverTimestamp(),
      completed_at: FieldValue.serverTimestamp(),
    }, { merge: true });
  } catch (error) {
    logger.error("Daily demand research failed", { error });
    await runRef.set({
      status: "failed",
      updated_at: FieldValue.serverTimestamp(),
      completed_at: FieldValue.serverTimestamp(),
      error_message: error instanceof Error ? error.message : "unknown_error",
    }, { merge: true });
    throw error;
  }
}

async function runWeeklyDemandStrategicWeightRefresh(now: Date = new Date()): Promise<void> {
  const runRef = db.collection("demand_research_runs").doc();
  const startedAt = Timestamp.fromDate(now);
  await runRef.set({
    run_type: "weekly_deep_research",
    status: "running",
    created_at: startedAt,
    updated_at: startedAt,
  });

  try {
    const signals = await loadActiveDemandSignals();
    const strategicWeights = buildStrategicWeightsFromSignals(signals, now);
    await db.collection("demand_strategic_weights").doc("current").set({
      ...strategicWeights,
      source_run_id: runRef.id,
      generated_at: startedAt,
      updated_at: FieldValue.serverTimestamp(),
    }, { merge: true });
    await refreshCaptureJobDemandSnapshots(signals, {
      ...strategicWeights,
      source_run_id: runRef.id,
    });
    await runRef.set({
      status: "succeeded",
      site_type_count: Object.keys(strategicWeights.site_type_weights).length,
      workflow_count: Object.keys(strategicWeights.workflow_weights ?? {}).length,
      updated_at: FieldValue.serverTimestamp(),
      completed_at: FieldValue.serverTimestamp(),
    }, { merge: true });
  } catch (error) {
    logger.error("Weekly demand strategic weight refresh failed", { error });
    await runRef.set({
      status: "failed",
      updated_at: FieldValue.serverTimestamp(),
      completed_at: FieldValue.serverTimestamp(),
      error_message: error instanceof Error ? error.message : "unknown_error",
    }, { merge: true });
    throw error;
  }
}

export const submitRobotTeamDemand = onRequest(
  { region: "us-central1", maxInstances: HTTP_MAX_INSTANCES },
  handleSubmitRobotTeamDemand,
);

export const submitSiteOperatorDemand = onRequest(
  { region: "us-central1", maxInstances: HTTP_MAX_INSTANCES },
  handleSubmitSiteOperatorDemand,
);

export const demandOpportunityFeed = onRequest(
  { region: "us-central1", maxInstances: HTTP_MAX_INSTANCES },
  handleDemandOpportunityFeed,
);

export const nearbyDiscoveryProxy = onRequest(
  { region: "us-central1", maxInstances: HTTP_MAX_INSTANCES },
  handleNearbyDiscoveryProxy,
);

export const placesAutocompleteProxy = onRequest(
  { region: "us-central1", maxInstances: HTTP_MAX_INSTANCES },
  handlePlacesAutocompleteProxy,
);

export const placesDetailsProxy = onRequest(
  { region: "us-central1", maxInstances: HTTP_MAX_INSTANCES },
  handlePlacesDetailsProxy,
);

export const api = onRequest(
  { region: "us-central1", maxInstances: HTTP_MAX_INSTANCES },
  async (req, res) => {
    const path = requestPath(req);
    if (path === "/v1/demand/robot-team-requests") {
      await handleSubmitRobotTeamDemand(req, res);
      return;
    }
    if (path === "/v1/demand/site-operator-submissions") {
      await handleSubmitSiteOperatorDemand(req, res);
      return;
    }
    if (path === "/v1/opportunities/feed") {
      await handleDemandOpportunityFeed(req, res);
      return;
    }
    if (path === "/v1/nearby/discovery") {
      await handleNearbyDiscoveryProxy(req, res);
      return;
    }
    if (path === "/v1/places/autocomplete") {
      await handlePlacesAutocompleteProxy(req, res);
      return;
    }
    if (path === "/v1/places/details") {
      await handlePlacesDetailsProxy(req, res);
      return;
    }

    res.status(404).json({ error: "Not found" });
  },
);

export const scheduledDailyDemandResearch = onSchedule(
  {
    region: "us-central1",
    schedule: "0 9 * * *",
    timeZone: "America/New_York",
    maxInstances: SCHEDULED_MAX_INSTANCES,
  },
  async () => {
    await runDailyDemandResearch();
  },
);

export const scheduledWeeklyDemandDeepResearch = onSchedule(
  {
    region: "us-central1",
    schedule: "0 10 * * 1",
    timeZone: "America/New_York",
    maxInstances: SCHEDULED_MAX_INSTANCES,
  },
  async () => {
    await runWeeklyDemandStrategicWeightRefresh();
  },
);
