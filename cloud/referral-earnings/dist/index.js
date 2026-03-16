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
if (getApps().length === 0)
    initializeApp();
const db = getFirestore();
const COMMISSION_RATE = 0.1; // 10 % ongoing commission to referrer
const FIRST_CAPTURE_BONUS_RATE = 0.1; // 10 % one-time bonus to referred user
function nextReferralStatus(current) {
    if (current === "signedUp")
        return "firstCapture";
    return "active";
}
export const onCaptureApproved = onDocumentWritten({
    document: "capture_submissions/{captureId}",
    region: "us-central1",
}, async (event) => {
    const captureId = event.params.captureId;
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!after)
        return; // document deleted — nothing to do
    const newStatus = after["status"];
    const oldStatus = before?.["status"];
    const isNowPaying = newStatus === "approved" || newStatus === "paid";
    const wasAlreadyPaying = oldStatus === "approved" || oldStatus === "paid";
    if (!isNowPaying || wasAlreadyPaying)
        return;
    // Idempotency guard: skip if already processed
    if (after["referralBonusProcessedAt"] !== undefined) {
        logger.info("Referral bonus already processed, skipping", { captureId });
        return;
    }
    const creatorId = after["creator_id"];
    const payoutCents = after["payout_cents"];
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
    const referredBy = userSnap.data()?.["referredBy"];
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
    const currentReferralStatus = referralSnap.data()?.["status"] ??
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
        "stats.referralEarningsCents": FieldValue.increment(referrerCommissionCents),
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
});
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
export const updateCaptureStatus = onRequest({ region: "us-central1" }, async (req, res) => {
    if (req.method !== "POST") {
        res.status(405).json({ error: "Method not allowed" });
        return;
    }
    const { captureId, creatorId, status, payoutCents } = req.body;
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
    const update = {
        creator_id: creatorId,
        status,
        payout_cents: cents,
        updated_at: Timestamp.now(),
    };
    // Only stamp approved_at / paid_at on the relevant transitions
    if (status === "approved")
        update["approved_at"] = Timestamp.now();
    if (status === "paid")
        update["paid_at"] = Timestamp.now();
    try {
        await docRef.set(update, { merge: true });
        logger.info("capture_submissions updated", { captureId, creatorId, status, cents });
        res.status(200).json({ ok: true, captureId, status });
    }
    catch (err) {
        logger.error("Failed to update capture_submissions", { captureId, err });
        res.status(500).json({ error: "Internal error" });
    }
});
