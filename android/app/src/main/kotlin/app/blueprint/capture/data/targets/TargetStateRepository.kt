package app.blueprint.capture.data.targets

import app.blueprint.capture.data.model.TargetAvailabilityStatus
import app.blueprint.capture.data.util.awaitResult
import com.google.firebase.Timestamp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FieldPath
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.SetOptions
import java.util.Date
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow

data class TargetState(
    val status: TargetAvailabilityStatus,
    val reservedBy: String? = null,
    val reservedUntilMs: Long? = null,
    val checkedInBy: String? = null,
    val completedAtMs: Long? = null,
    val lat: Double? = null,
    val lng: Double? = null,
    val updatedAtMs: Long? = null,
)

data class TargetReservation(
    val targetId: String,
    val reservedUntilMs: Long,
)

@Singleton
class TargetStateRepository @Inject constructor(
    private val firestore: FirebaseFirestore,
    private val auth: FirebaseAuth,
) {
    private val collection get() = firestore.collection("target_state")
    private val currentUserId get() = auth.currentUser?.uid ?: "anonymous"

    /** Batch-fetches live states for up to N target IDs (chunked into groups of 10). */
    suspend fun batchFetchStates(targetIds: List<String>): Map<String, TargetState> {
        if (targetIds.isEmpty()) return emptyMap()
        val result = mutableMapOf<String, TargetState>()
        for (chunk in targetIds.chunked(10)) {
            runCatching {
                val snapshot = collection
                    .whereIn(FieldPath.documentId(), chunk)
                    .get()
                    .awaitResult()
                for (doc in snapshot.documents) {
                    toState(doc.data ?: emptyMap())?.let { result[doc.id] = it }
                }
            }
        }
        return result
    }

    /** Real-time listener for a single target's state. */
    fun observeState(targetId: String): Flow<TargetState?> = callbackFlow {
        val listener = collection.document(targetId)
            .addSnapshotListener { snapshot, _ ->
                trySend(snapshot?.data?.let { toState(it) })
            }
        awaitClose { listener.remove() }
    }

    /** Reserve a target for the current user for the given duration. */
    suspend fun reserve(
        targetId: String,
        lat: Double? = null,
        lng: Double? = null,
        durationMs: Long = 20 * 60 * 1000L,
    ): Result<TargetReservation> = runCatching {
        val now = System.currentTimeMillis()
        val untilMs = now + durationMs
        val doc = collection.document(targetId)

        // Optimistic conflict check
        runCatching {
            val snap = doc.get().awaitResult()
            val state = snap.data?.let { toState(it) }
            if (state != null) {
                if (state.status == TargetAvailabilityStatus.Reserved) {
                    val expMs = state.reservedUntilMs
                    if (expMs != null && expMs > now && state.reservedBy != currentUserId) {
                        error("Target is already reserved by another user")
                    }
                }
                if (state.status == TargetAvailabilityStatus.Completed) {
                    error("Target is already completed")
                }
            }
        }

        val payload = mutableMapOf<String, Any>(
            "status" to TargetAvailabilityStatus.Reserved.firestoreValue,
            "reservedBy" to currentUserId,
            "reservedUntil" to Timestamp(Date(untilMs)),
            "updatedAt" to FieldValue.serverTimestamp(),
        )
        lat?.let { payload["lat"] = it }
        lng?.let { payload["lng"] = it }
        doc.set(payload, SetOptions.merge()).awaitResult()
        TargetReservation(targetId = targetId, reservedUntilMs = untilMs)
    }

    /** Cancel the current user's reservation on a target. */
    suspend fun cancelReservation(targetId: String) {
        runCatching {
            val doc = collection.document(targetId)
            val snap = doc.get().awaitResult()
            val reservedBy = snap.data?.get("reservedBy") as? String
            if (reservedBy == null || reservedBy == currentUserId) {
                doc.set(
                    mapOf(
                        "status" to TargetAvailabilityStatus.Available.firestoreValue,
                        "reservedBy" to FieldValue.delete(),
                        "reservedUntil" to FieldValue.delete(),
                        "updatedAt" to FieldValue.serverTimestamp(),
                    ),
                    SetOptions.merge(),
                ).awaitResult()
            }
        }
    }

    /** Transition reserved → in_progress (check-in). */
    suspend fun checkIn(targetId: String): Result<Unit> = runCatching {
        val doc = collection.document(targetId)
        val snap = doc.get().awaitResult()
        val state = snap.data?.let { toState(it) }
        val now = System.currentTimeMillis()
        if (state?.status == TargetAvailabilityStatus.Reserved &&
            state.reservedBy == currentUserId &&
            (state.reservedUntilMs ?: now) > now
        ) {
            doc.set(
                mapOf(
                    "status" to TargetAvailabilityStatus.InProgress.firestoreValue,
                    "checkedInBy" to currentUserId,
                    "updatedAt" to FieldValue.serverTimestamp(),
                ),
                SetOptions.merge(),
            ).awaitResult()
            return@runCatching
        }
        error("Cannot check in: valid reservation not found for current user")
    }

    /** Transition in_progress → completed. */
    suspend fun complete(targetId: String): Result<Unit> = runCatching {
        val doc = collection.document(targetId)
        val snap = doc.get().awaitResult()
        val state = snap.data?.let { toState(it) }
        if (state?.status == TargetAvailabilityStatus.InProgress && state.checkedInBy == currentUserId) {
            doc.set(
                mapOf(
                    "status" to TargetAvailabilityStatus.Completed.firestoreValue,
                    "completedAt" to FieldValue.serverTimestamp(),
                    "updatedAt" to FieldValue.serverTimestamp(),
                ),
                SetOptions.merge(),
            ).awaitResult()
            return@runCatching
        }
        error("Cannot complete: target is not in_progress or owned by current user")
    }

    /** Returns the current user's active (non-expired) reservation, if any. */
    suspend fun fetchActiveReservationForCurrentUser(): TargetReservation? = runCatching {
        val nowTs = Timestamp(Date())
        val snap = collection
            .whereEqualTo("status", TargetAvailabilityStatus.Reserved.firestoreValue)
            .whereEqualTo("reservedBy", currentUserId)
            .whereGreaterThan("reservedUntil", nowTs)
            .limit(1)
            .get()
            .awaitResult()
        snap.documents.firstOrNull()?.let { doc ->
            val untilMs = (doc.data?.get("reservedUntil") as? Timestamp)?.toDate()?.time
                ?: return@let null
            TargetReservation(targetId = doc.documentID, reservedUntilMs = untilMs)
        }
    }.getOrNull()

    private fun toState(data: Map<String, Any>): TargetState? {
        val statusStr = data["status"] as? String
            ?: return TargetState(status = TargetAvailabilityStatus.Available)
        val status = TargetAvailabilityStatus.fromFirestoreValue(statusStr) ?: return null
        return TargetState(
            status = status,
            reservedBy = data["reservedBy"] as? String,
            reservedUntilMs = (data["reservedUntil"] as? Timestamp)?.toDate()?.time,
            checkedInBy = data["checkedInBy"] as? String,
            completedAtMs = (data["completedAt"] as? Timestamp)?.toDate()?.time,
            lat = data["lat"] as? Double,
            lng = data["lng"] as? Double,
            updatedAtMs = (data["updatedAt"] as? Timestamp)?.toDate()?.time,
        )
    }
}
