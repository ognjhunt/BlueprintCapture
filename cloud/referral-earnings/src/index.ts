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

import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { onRequest } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { initializeApp, getApps } from "firebase-admin/app";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import {
  annotateCaptureJobs,
  buildDemandSignalsForRobotTeamRequest,
  buildDemandSignalsForSiteOperatorSubmission,
  rankNearbyOpportunities,
  type CaptureJobApiRecord,
  type DemandOpportunityFeedRequest,
  type DemandSignalDocument,
  type RobotTeamDemandRequestPayload,
  type SiteOperatorDemandSubmissionPayload,
} from "./demand-opportunities.js";

if (getApps().length === 0) initializeApp();

const db = getFirestore();

const COMMISSION_RATE = 0.1;        // 10 % ongoing commission to referrer
const FIRST_CAPTURE_BONUS_RATE = 0.1; // 10 % one-time bonus to referred user

type ReferralStatus = "invited" | "signedUp" | "firstCapture" | "active";

function nextReferralStatus(current: ReferralStatus): ReferralStatus {
  if (current === "signedUp") return "firstCapture";
  return "active";
}

export const onCaptureApproved = onDocumentWritten(
  {
    document: "capture_submissions/{captureId}",
    region: "us-central1",
  },
  async (event) => {
    const captureId = event.params.captureId;
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();

    if (!after) return; // document deleted — nothing to do

    const newStatus = after["status"] as string | undefined;
    const oldStatus = before?.["status"] as string | undefined;

    const isNowPaying = newStatus === "approved" || newStatus === "paid";
    const wasAlreadyPaying = oldStatus === "approved" || oldStatus === "paid";

    if (!isNowPaying || wasAlreadyPaying) return;

    // Idempotency guard: skip if already processed
    if (after["referralBonusProcessedAt"] !== undefined) {
      logger.info("Referral bonus already processed, skipping", { captureId });
      return;
    }

    const creatorId = after["creator_id"] as string | undefined;
    const payoutCents = after["payout_cents"] as number | undefined;

    if (!creatorId || !payoutCents || payoutCents <= 0) {
      logger.info("Skipping: missing creator_id or payout_cents", {
        captureId,
        creatorId,
        payoutCents,
      });
      return;
    }

    // ── 1. Load the capturer's user document to find their referrer ──────────
    const userRef = db.collection("users").doc(creatorId);
    const userSnap = await userRef.get();

    if (!userSnap.exists) {
      logger.warn("Creator user document not found", { creatorId, captureId });
      return;
    }

    const referredBy = userSnap.data()?.["referredBy"] as string | undefined;

    if (!referredBy) {
      // Not a referred user — stamp the doc so we don't check again
      await db.collection("capture_submissions").doc(captureId).update({
        referralBonusProcessedAt: FieldValue.serverTimestamp(),
        referralBonusSkippedReason: "no_referrer",
      });
      return;
    }

    // ── 2. Load the referral record ──────────────────────────────────────────
    const referralRef = db
      .collection("users")
      .doc(referredBy)
      .collection("referrals")
      .doc(creatorId);

    const referralSnap = await referralRef.get();

    if (!referralSnap.exists) {
      logger.warn("Referral record not found", {
        referrerId: referredBy,
        referredUserId: creatorId,
        captureId,
      });
      // Still stamp so we don't retry forever
      await db.collection("capture_submissions").doc(captureId).update({
        referralBonusProcessedAt: FieldValue.serverTimestamp(),
        referralBonusSkippedReason: "referral_record_missing",
      });
      return;
    }

    const currentReferralStatus =
      (referralSnap.data()?.["status"] as ReferralStatus | undefined) ??
      "signedUp";

    const isFirstCapture = currentReferralStatus === "signedUp";

    // ── 3. Calculate amounts ─────────────────────────────────────────────────
    const referrerCommissionCents = Math.floor(payoutCents * COMMISSION_RATE);

    // Referred user gets their bonus only on the very first approved capture
    const referredUserBonusCents = isFirstCapture
      ? Math.floor(payoutCents * FIRST_CAPTURE_BONUS_RATE)
      : 0;

    const newReferralStatus = nextReferralStatus(currentReferralStatus);

    logger.info("Processing referral bonus", {
      captureId,
      creatorId,
      referrerId: referredBy,
      payoutCents,
      referrerCommissionCents,
      referredUserBonusCents,
      currentReferralStatus,
      newReferralStatus,
    });

    // ── 4. Apply all writes atomically ───────────────────────────────────────
    const batch = db.batch();

    // 4a. Update referral record: lifetime earnings + status
    batch.update(referralRef, {
      lifetimeEarningsCents: FieldValue.increment(referrerCommissionCents),
      status: newReferralStatus,
      lastEarningAt: FieldValue.serverTimestamp(),
    });

    // 4b. Credit referrer's referral earnings balance
    //     `stats.referralEarningsCents` is the canonical field for unpaid
    //     referral commissions; the payout system reads this to include it
    //     in the next disbursement.
    batch.update(db.collection("users").doc(referredBy), {
      "stats.referralEarningsCents": FieldValue.increment(
        referrerCommissionCents
      ),
      updatedAt: FieldValue.serverTimestamp(),
    });

    // 4c. Credit referred user's first-capture bonus (one-time only)
    if (referredUserBonusCents > 0) {
      batch.update(userRef, {
        "stats.referralBonusCents": FieldValue.increment(referredUserBonusCents),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }

    // 4d. Stamp the capture so this function never runs for it again
    batch.update(db.collection("capture_submissions").doc(captureId), {
      referralBonusProcessedAt: FieldValue.serverTimestamp(),
      referralBonusReferrerId: referredBy,
      referralBonusCommissionCents: referrerCommissionCents,
      referralBonusUserBonusCents: referredUserBonusCents,
    });

    await batch.commit();

    logger.info("Referral bonus applied successfully", {
      captureId,
      creatorId,
      referrerId: referredBy,
      referrerCommissionCents,
      referredUserBonusCents,
      newReferralStatus,
    });
  }
);

/**
 * updateCaptureStatus — HTTP endpoint for the backend API to call when a
 * capture is approved or paid. Writes/updates the `capture_submissions`
 * document, which automatically triggers `onCaptureApproved` above.
 *
 * POST /updateCaptureStatus
 * Headers: Authorization: Bearer <FIREBASE_APP_CHECK_TOKEN or Admin token>
 * Body: {
 *   captureId:  string,   // Firestore document ID (= CaptureBundleContext.captureIdentifier)
 *   creatorId:  string,   // Firebase UID of the capturer
 *   status:     "approved" | "paid" | "rejected" | "needs_fix",
 *   payoutCents: number,  // final payout amount in cents (0 for non-paying statuses)
 * }
 */
export const updateCaptureStatus = onRequest(
  { region: "us-central1" },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method not allowed" });
      return;
    }

    const { captureId, creatorId, status, payoutCents } = req.body as {
      captureId?: string;
      creatorId?: string;
      status?: string;
      payoutCents?: number;
    };

    if (!captureId || typeof captureId !== "string") {
      res.status(400).json({ error: "captureId is required" });
      return;
    }
    if (!creatorId || typeof creatorId !== "string") {
      res.status(400).json({ error: "creatorId is required" });
      return;
    }
    const validStatuses = ["submitted", "under_review", "approved", "paid", "needs_fix", "rejected"];
    if (!status || !validStatuses.includes(status)) {
      res.status(400).json({ error: `status must be one of: ${validStatuses.join(", ")}` });
      return;
    }
    const cents = typeof payoutCents === "number" ? Math.max(0, Math.floor(payoutCents)) : 0;

    const docRef = db.collection("capture_submissions").doc(captureId);
    const update: Record<string, unknown> = {
      creator_id: creatorId,
      status,
      payout_cents: cents,
      updated_at: Timestamp.now(),
    };

    // Only stamp approved_at / paid_at on the relevant transitions
    if (status === "approved") update["approved_at"] = Timestamp.now();
    if (status === "paid") update["paid_at"] = Timestamp.now();

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

function parseRequestBody<T>(body: unknown): T | null {
  if (!body || typeof body !== "object" || Array.isArray(body)) return null;
  return body as T;
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

async function loadActiveCaptureJobs(): Promise<FirestoreJobDoc[]> {
  const snapshot = await db.collection("capture_jobs").where("active", "==", true).limit(200).get();
  return snapshot.docs.map((doc) => ({ id: doc.id, data: doc.data() as Record<string, unknown> }));
}

async function refreshCaptureJobDemandSnapshots(signals: DemandSignalDocument[]): Promise<void> {
  const jobs = await loadActiveCaptureJobs();
  if (jobs.length === 0) return;

  const annotated = annotateCaptureJobs(
    jobs,
    signals,
    { lat: 37.7749, lng: -122.4194 },
    1000 * 1609.34,
    200,
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
}

export const submitRobotTeamDemand = onRequest(
  { region: "us-central1" },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method not allowed" });
      return;
    }

    const payload = parseRequestBody<RobotTeamDemandRequestPayload>(req.body);
    if (!payload?.company_name || !Array.isArray(payload.site_types) || payload.site_types.length === 0) {
      res.status(400).json({ error: "company_name and site_types are required" });
      return;
    }

    const submissionRef = db.collection("robot_team_requests").doc();
    const createdAt = Timestamp.now();
    const signals = buildDemandSignalsForRobotTeamRequest(submissionRef.id, payload);
    const batch = db.batch();

    batch.set(submissionRef, {
      ...payload,
      created_at: createdAt,
      updated_at: createdAt,
      source_type: "robot_team_request",
    });

    for (const signal of signals) {
      batch.set(db.collection("demand_signals").doc(signal.id), {
        ...signal,
        created_at: createdAt,
        updated_at: createdAt,
        freshness_expires_at: signal.freshness_expires_at ? Timestamp.fromDate(new Date(signal.freshness_expires_at)) : null,
      });
    }

    try {
      await batch.commit();
      await refreshCaptureJobDemandSnapshots(await loadActiveDemandSignals());
      res.status(201).json({
        submission_id: submissionRef.id,
        demand_signal_ids: signals.map((signal) => signal.id),
        created_at: createdAt.toDate().toISOString(),
      });
    } catch (error) {
      logger.error("Failed to persist robot team demand request", { error });
      res.status(500).json({ error: "Internal error" });
    }
  },
);

export const submitSiteOperatorDemand = onRequest(
  { region: "us-central1" },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method not allowed" });
      return;
    }

    const payload = parseRequestBody<SiteOperatorDemandSubmissionPayload>(req.body);
    if (!payload?.operator_name || !payload.site_name || !payload.site_address || !Array.isArray(payload.site_types) || payload.site_types.length === 0) {
      res.status(400).json({ error: "operator_name, site_name, site_address, and site_types are required" });
      return;
    }

    const submissionRef = db.collection("site_operator_submissions").doc();
    const createdAt = Timestamp.now();
    const signals = buildDemandSignalsForSiteOperatorSubmission(submissionRef.id, payload);
    const batch = db.batch();

    batch.set(submissionRef, {
      ...payload,
      created_at: createdAt,
      updated_at: createdAt,
      source_type: "site_operator_submission",
    });

    for (const signal of signals) {
      batch.set(db.collection("demand_signals").doc(signal.id), {
        ...signal,
        created_at: createdAt,
        updated_at: createdAt,
        freshness_expires_at: signal.freshness_expires_at ? Timestamp.fromDate(new Date(signal.freshness_expires_at)) : null,
      });
    }

    try {
      await batch.commit();
      await refreshCaptureJobDemandSnapshots(await loadActiveDemandSignals());
      res.status(201).json({
        submission_id: submissionRef.id,
        demand_signal_ids: signals.map((signal) => signal.id),
        created_at: createdAt.toDate().toISOString(),
      });
    } catch (error) {
      logger.error("Failed to persist site operator demand submission", { error });
      res.status(500).json({ error: "Internal error" });
    }
  },
);

export const demandOpportunityFeed = onRequest(
  { region: "us-central1" },
  async (req, res) => {
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
      const signals = await loadActiveDemandSignals();
      const jobs = await loadActiveCaptureJobs();
      const radiusMeters = Math.max(100, Math.min(payload.radius_m ?? 16093, 160934));
      const limit = Math.max(1, Math.min(payload.limit ?? 25, 200));
      const captureJobs = annotateCaptureJobs(
        jobs,
        signals,
        { lat: payload.lat, lng: payload.lng },
        radiusMeters,
        limit,
      );
      const nearbyOpportunities = rankNearbyOpportunities(payload, signals);

      res.status(200).json({
        generated_at: new Date().toISOString(),
        nearby_opportunities: nearbyOpportunities,
        capture_jobs: captureJobs,
      });
    } catch (error) {
      logger.error("Failed to generate demand opportunity feed", { error });
      res.status(500).json({ error: "Internal error" });
    }
  },
);
