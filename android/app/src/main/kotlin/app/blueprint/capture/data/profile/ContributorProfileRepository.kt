package app.blueprint.capture.data.profile

import app.blueprint.capture.data.model.ContributorProfile
import app.blueprint.capture.data.model.ContributorStats
import app.blueprint.capture.data.util.awaitResult
import com.google.firebase.firestore.DocumentSnapshot
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.SetOptions
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.flowOf

@Singleton
class ContributorProfileRepository @Inject constructor(
    private val firestore: FirebaseFirestore,
) {
    fun observeProfile(uid: String?): Flow<ContributorProfile?> {
        if (uid.isNullOrBlank()) {
            return flowOf(null)
        }

        return callbackFlow {
            val registration = firestore.collection("users").document(uid)
                .addSnapshotListener { snapshot, error ->
                    if (error != null) {
                        trySend(null)
                        return@addSnapshotListener
                    }

                    val profile = if (snapshot?.exists() == true) {
                        snapshot.toContributorProfile(uid)
                    } else {
                        null
                    }
                    trySend(profile)
                }

            awaitClose { registration.remove() }
        }
    }

    suspend fun updateProfile(
        uid: String,
        name: String,
        phoneNumber: String,
        company: String,
    ) {
        firestore.collection("users").document(uid)
            .set(
                mapOf(
                    "name" to name.trim(),
                    "phone_number" to phoneNumber.trim(),
                    "company" to company.trim(),
                ),
                SetOptions.merge(),
            )
            .awaitResult()
    }

    private fun DocumentSnapshot.toContributorProfile(uid: String): ContributorProfile {
        val data = data.orEmpty()
        val stats = data["stats"] as? Map<*, *> ?: emptyMap<String, Any>()
        return ContributorProfile(
            uid = uid,
            name = data["name"] as? String ?: "",
            email = data["email"] as? String ?: "",
            phoneNumber = data["phone_number"] as? String ?: "",
            company = data["company"] as? String ?: "",
            role = data["role"] as? String ?: "capturer",
            stats = ContributorStats(
                totalCaptures = stats.intValue("totalCaptures"),
                approvedCaptures = stats.intValue("approvedCaptures"),
                averageQuality = stats.intValue("avgQuality"),
                totalEarningsCents = stats.intValue("totalEarnings"),
                availableBalanceCents = stats.intValue("availableBalance"),
                referralEarningsCents = stats.intValue("referralEarningsCents"),
                referralBonusCents = stats.intValue("referralBonusCents"),
            ),
        )
    }
}

private fun Map<*, *>.intValue(key: String): Int {
    val value = get(key)
    return when (value) {
        is Int -> value
        is Long -> value.toInt()
        is Double -> value.toInt()
        is Number -> value.toInt()
        is String -> value.toIntOrNull() ?: 0
        else -> 0
    }
}
