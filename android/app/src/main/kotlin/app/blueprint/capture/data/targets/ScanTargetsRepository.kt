package app.blueprint.capture.data.targets

import app.blueprint.capture.data.model.DemoData
import app.blueprint.capture.data.model.ScanTarget
import com.google.firebase.Timestamp
import com.google.firebase.firestore.FirebaseFirestore
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow

@Singleton
class ScanTargetsRepository @Inject constructor(
    private val firestore: FirebaseFirestore,
) {
    fun observeActiveTargets(): Flow<List<ScanTarget>> = callbackFlow {
        val registration = firestore.collection("capture_jobs")
            .whereEqualTo("active", true)
            .addSnapshotListener { snapshot, error ->
                if (error != null) {
                    trySend(DemoData.scanTargets)
                    return@addSnapshotListener
                }

                val items = snapshot?.documents.orEmpty()
                    .mapNotNull { doc ->
                        val title = doc.getString("title") ?: return@mapNotNull null
                        val payoutCents = doc.number("quoted_payout_cents")
                            ?: doc.number("payout_cents")
                            ?: return@mapNotNull null
                        val durationMinutes = doc.number("est_minutes") ?: 20
                        val instructions = doc.get("workflow_steps") as? List<*>
                        val address = doc.getString("address").orEmpty()
                        val subtitle = when {
                            !instructions.isNullOrEmpty() -> instructions.firstOrNull()?.toString().orEmpty()
                            address.isNotBlank() -> address
                            else -> "Curated capture opportunity"
                        }

                        ScanTarget(
                            id = doc.id,
                            title = title,
                            subtitle = subtitle,
                            payoutText = "$${payoutCents / 100}",
                            distanceText = "${durationMinutes} min",
                            readyNow = (doc.number("priority") ?: 0) > 0 ||
                                recentlyUpdated(doc.get("updated_at")),
                        )
                    }
                    .sortedWith(
                        compareByDescending<ScanTarget> { it.readyNow }
                            .thenByDescending { payoutValue(it.payoutText) },
                    )

                trySend(if (items.isEmpty()) DemoData.scanTargets else items)
            }

        awaitClose { registration.remove() }
    }
}

private fun payoutValue(payoutText: String): Int = payoutText.removePrefix("$").toIntOrNull() ?: 0

private fun recentlyUpdated(value: Any?): Boolean {
    val updatedAt = when (value) {
        is Timestamp -> value.toDate().time
        is java.util.Date -> value.time
        else -> return false
    }
    val fifteenMinutesMs = 15 * 60 * 1000L
    return System.currentTimeMillis() - updatedAt <= fifteenMinutesMs
}

private fun com.google.firebase.firestore.DocumentSnapshot.number(key: String): Int? {
    val raw = get(key)
    return when (raw) {
        is Int -> raw
        is Long -> raw.toInt()
        is Double -> raw.toInt()
        is Number -> raw.toInt()
        is String -> raw.toIntOrNull()
        else -> null
    }
}
