package app.blueprint.capture.data.targets

import android.location.Location
import app.blueprint.capture.data.model.CapturePermissionTone
import app.blueprint.capture.data.model.ScanTarget
import app.blueprint.capture.data.model.VenuePermission
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
    fun observeActiveTargets(userLocation: Location? = null): Flow<List<ScanTarget>> = callbackFlow {
        val registration = firestore.collection("capture_jobs")
            .whereEqualTo("active", true)
            .addSnapshotListener { snapshot, error ->
                if (error != null) {
                    // Surface empty list on error — demo fallbacks removed for production
                    trySend(emptyList())
                    return@addSnapshotListener
                }

                val items = snapshot?.documents.orEmpty()
                    .mapNotNull { doc ->
                        val title = doc.getString("title") ?: return@mapNotNull null
                        val payoutCents = doc.number("quoted_payout_cents")
                            ?: doc.number("payout_cents")
                            ?: return@mapNotNull null
                        val estimatedMinutes = doc.number("est_minutes") ?: 20
                        val workflowSteps = doc.stringList("workflow_steps")
                            .ifEmpty { doc.stringList("instructions") }
                        val address = doc.getString("address").orEmpty()
                        val lat = doc.numberDouble("lat") ?: doc.numberDouble("latitude")
                        val lng = doc.numberDouble("lng") ?: doc.numberDouble("longitude")
                        val priorityWeight = doc.numberDouble("priority_weight") ?: 0.0
                        val checkinRadiusM = doc.number("checkin_radius_m") ?: 150

                        // Compute distance when user location + job coordinates are both available
                        val distanceM: Double? = if (lat != null && lng != null && userLocation != null) {
                            val results = FloatArray(1)
                            Location.distanceBetween(
                                userLocation.latitude, userLocation.longitude,
                                lat, lng, results,
                            )
                            results[0].toDouble()
                        } else {
                            null
                        }

                        // readyNow = within checkin radius, OR fallback priority/freshness signals
                        val readyNow = (distanceM != null && distanceM <= checkinRadiusM) ||
                            (doc.number("priority") ?: 0) > 0 ||
                            recentlyUpdated(doc.get("updated_at"))

                        val subtitle = when {
                            workflowSteps.isNotEmpty() -> workflowSteps.first()
                            address.isNotBlank() -> address
                            else -> "Curated capture opportunity"
                        }
                        val rightsProfile = doc.getString("rights_profile")
                        val venuePermission = doc.venuePermission(rightsProfile)

                        ScanTarget(
                            id = doc.id,
                            title = title,
                            subtitle = subtitle,
                            payoutText = "$${payoutCents / 100}",
                            distanceText = distanceM
                                ?.let { formatDistanceMiles(it) }
                                ?: doc.distanceText()
                                ?: "${estimatedMinutes} min",
                            readyNow = readyNow,
                            addressText = address.ifBlank { subtitle },
                            categoryLabel = doc.getString("category")?.uppercase(),
                            estimatedMinutes = estimatedMinutes,
                            permissionTone = doc.permissionTone(readyNow, rightsProfile),
                            imageUrl = doc.getString("preview_url") ?: doc.getString("image_url"),
                            workflowName = doc.getString("workflow_name") ?: title,
                            workflowSteps = workflowSteps,
                            zone = doc.getString("zone"),
                            owner = doc.getString("owner"),
                            siteSubmissionId = doc.getString("site_submission_id"),
                            quotedPayoutCents = doc.number("quoted_payout_cents")
                                ?: doc.number("payout_cents"),
                            requestedOutputs = doc.stringList("requested_outputs")
                                .ifEmpty { listOf("qualification") },
                            rightsProfile = rightsProfile,
                            lat = lat,
                            lng = lng,
                            priorityWeight = priorityWeight,
                            checkinRadiusM = checkinRadiusM,
                            venuePermission = venuePermission,
                        )
                    }

                trySend(rankForFeed(items, userLocation))
            }

        awaitClose { registration.remove() }
    }

    companion object {
        /**
         * iOS-parity feed ranking (mirrors rankJobsForFeed in ScanHomeViewModel.swift):
         * 1. readyNow (within check-in radius) first
         * 2. Higher priorityWeight
         * 3. Higher quoted payout
         * 4. Closer distance (when location available)
         * 5. Alphabetical job ID tiebreaker
         */
        fun rankForFeed(targets: List<ScanTarget>, userLocation: Location?): List<ScanTarget> =
            targets.sortedWith(
                compareByDescending<ScanTarget> { it.readyNow }
                    .thenByDescending { it.priorityWeight }
                    .thenByDescending { it.quotedPayoutCents ?: 0 }
                    .thenBy { target ->
                        if (userLocation != null && target.lat != null && target.lng != null) {
                            val results = FloatArray(1)
                            Location.distanceBetween(
                                userLocation.latitude, userLocation.longitude,
                                target.lat, target.lng, results,
                            )
                            results[0].toDouble()
                        } else {
                            Double.MAX_VALUE
                        }
                    }
                    .thenBy { it.id },
            )

        fun formatDistanceMiles(distanceM: Double): String =
            String.format("%.1f mi", distanceM / 1609.34)
    }
}

// ---------------------------------------------------------------------------
// DocumentSnapshot extension helpers
// ---------------------------------------------------------------------------

private fun com.google.firebase.firestore.DocumentSnapshot.distanceText(): String? {
    val explicit = getString("distance_text")?.takeIf(String::isNotBlank)
    if (explicit != null) return explicit
    val miles = numberDouble("distance_miles") ?: numberDouble("distanceMiles")
    return miles?.let { String.format("%.1f mi", it) }
}

private fun com.google.firebase.firestore.DocumentSnapshot.permissionTone(
    readyNow: Boolean,
    rightsProfile: String?,
): CapturePermissionTone {
    val raw = listOfNotNull(
        getString("permission_tier"),
        rightsProfile,
        getString("capture_policy"),
    ).joinToString(" ").lowercase()

    return when {
        raw.contains("blocked") || raw.contains("restrict") || raw.contains("forbid") ->
            CapturePermissionTone.Blocked
        raw.contains("documented") || raw.contains("approved") ->
            CapturePermissionTone.Approved
        raw.contains("permission") || raw.contains("access") ->
            CapturePermissionTone.Permission
        raw.contains("review") -> CapturePermissionTone.Review
        readyNow -> CapturePermissionTone.Approved
        else -> CapturePermissionTone.Review
    }
}

private fun com.google.firebase.firestore.DocumentSnapshot.venuePermission(
    rightsProfile: String?,
): VenuePermission {
    val raw = listOfNotNull(
        rightsProfile,
        getString("capture_consent_status"),
        getString("venue_permission"),
    ).joinToString(" ").lowercase()
    return when {
        raw.contains("blocked") || raw.contains("prohibited") -> VenuePermission.Blocked
        raw.contains("documented") || raw.contains("approved") -> VenuePermission.Documented
        raw.contains("policy") -> VenuePermission.PolicyOnly
        else -> VenuePermission.Unknown
    }
}

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

private fun com.google.firebase.firestore.DocumentSnapshot.numberDouble(key: String): Double? {
    val raw = get(key)
    return when (raw) {
        is Int -> raw.toDouble()
        is Long -> raw.toDouble()
        is Double -> raw
        is Float -> raw.toDouble()
        is Number -> raw.toDouble()
        is String -> raw.toDoubleOrNull()
        else -> null
    }
}

private fun com.google.firebase.firestore.DocumentSnapshot.stringList(key: String): List<String> =
    (get(key) as? List<*>)
        .orEmpty()
        .mapNotNull { it?.toString()?.takeIf(String::isNotBlank) }
