package app.blueprint.capture.data.capture

import app.blueprint.capture.data.util.awaitResult
import com.google.firebase.Timestamp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.Query
import javax.inject.Inject
import javax.inject.Singleton

enum class CaptureSubmissionStage {
    InReview,
    NeedsRecapture,
    Paid,
}

data class CaptureHistoryEntry(
    val captureId: String,
    val jobId: String?,
    val status: String,
    val payoutCents: Int,
    val submittedAtMs: Long?,
    val stage: CaptureSubmissionStage,
)

data class SubmissionSummary(
    val inReviewCount: Int = 0,
    val needsRecaptureCount: Int = 0,
    val paidCount: Int = 0,
) {
    val total: Int get() = inReviewCount + needsRecaptureCount + paidCount
}

@Singleton
class CaptureHistoryRepository @Inject constructor(
    private val firestore: FirebaseFirestore,
    private val auth: FirebaseAuth,
) {
    /** Fetches the current user's most recent 100 capture submissions. */
    suspend fun fetchHistory(): List<CaptureHistoryEntry> {
        val uid = auth.currentUser?.uid ?: return emptyList()
        return runCatching {
            val snap = firestore.collection("capture_submissions")
                .whereEqualTo("creator_id", uid)
                .orderBy("submitted_at", Query.Direction.DESCENDING)
                .limit(100)
                .get()
                .awaitResult()
            snap.documents.mapNotNull { doc ->
                val data = doc.data ?: return@mapNotNull null
                val status = data["status"] as? String ?: "submitted"
                val payoutCents = (data["payout_cents"] as? Number)?.toInt() ?: 0
                val submittedAtMs = (data["submitted_at"] as? Timestamp)?.toDate()?.time
                CaptureHistoryEntry(
                    captureId = doc.id,
                    jobId = data["job_id"] as? String,
                    status = status,
                    payoutCents = payoutCents,
                    submittedAtMs = submittedAtMs,
                    stage = statusToStage(status),
                )
            }
        }.getOrDefault(emptyList())
    }

    /** Returns a count summary bucketed into the three feed stages. */
    suspend fun fetchSummary(): SubmissionSummary {
        val history = fetchHistory()
        return SubmissionSummary(
            inReviewCount = history.count { it.stage == CaptureSubmissionStage.InReview },
            needsRecaptureCount = history.count { it.stage == CaptureSubmissionStage.NeedsRecapture },
            paidCount = history.count { it.stage == CaptureSubmissionStage.Paid },
        )
    }

    private fun statusToStage(status: String): CaptureSubmissionStage = when (status) {
        "needs_recapture", "needs_fix", "rejected" -> CaptureSubmissionStage.NeedsRecapture
        "paid" -> CaptureSubmissionStage.Paid
        else -> CaptureSubmissionStage.InReview
    }
}
