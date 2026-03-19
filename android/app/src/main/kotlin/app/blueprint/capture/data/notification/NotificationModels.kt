package app.blueprint.capture.data.notification

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import java.time.Instant
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

enum class NotificationPreferenceKey(
    val title: String,
    val subtitle: String,
) {
    NearbyJobs(
        title = "Nearby job alerts",
        subtitle = "Nearby approved jobs that enter your geofence",
    ),
    Reservations(
        title = "Reservation alerts",
        subtitle = "Reservation reminders and expiry updates",
    ),
    CaptureStatus(
        title = "Capture status",
        subtitle = "Approved, needs fix, rejected, and paid captures",
    ),
    Payouts(
        title = "Payout updates",
        subtitle = "Scheduled, sent, and failed payout events",
    ),
    Account(
        title = "Account alerts",
        subtitle = "Payout method and account action required alerts",
    ),
}

@Serializable
data class NotificationPreferences(
    @SerialName("nearby_jobs") val nearbyJobs: Boolean = true,
    @SerialName("reservations") val reservations: Boolean = true,
    @SerialName("capture_status") val captureStatus: Boolean = true,
    @SerialName("payouts") val payouts: Boolean = true,
    @SerialName("account") val account: Boolean = true,
) {
    fun isEnabled(key: NotificationPreferenceKey): Boolean = when (key) {
        NotificationPreferenceKey.NearbyJobs -> nearbyJobs
        NotificationPreferenceKey.Reservations -> reservations
        NotificationPreferenceKey.CaptureStatus -> captureStatus
        NotificationPreferenceKey.Payouts -> payouts
        NotificationPreferenceKey.Account -> account
    }

    fun with(key: NotificationPreferenceKey, enabled: Boolean): NotificationPreferences = when (key) {
        NotificationPreferenceKey.NearbyJobs -> copy(nearbyJobs = enabled)
        NotificationPreferenceKey.Reservations -> copy(reservations = enabled)
        NotificationPreferenceKey.CaptureStatus -> copy(captureStatus = enabled)
        NotificationPreferenceKey.Payouts -> copy(payouts = enabled)
        NotificationPreferenceKey.Account -> copy(account = enabled)
    }
}

@Serializable
data class NotificationDeviceRegistration(
    @SerialName("creator_id") val creatorId: String,
    @SerialName("platform") val platform: String,
    @SerialName("fcm_token") val fcmToken: String,
    @SerialName("authorization_status") val authorizationStatus: String,
    @SerialName("app_version") val appVersion: String,
    @SerialName("last_seen_at") val lastSeenAt: String,
)

enum class NotificationAuthorizationStatus(val serverValue: String) {
    NotDetermined("not_determined"),
    Denied("denied"),
    Authorized("authorized");

    companion object {
        fun fromContext(context: Context): NotificationAuthorizationStatus {
            if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) {
                return Denied
            }
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                return Authorized
            }
            return if (
                ContextCompat.checkSelfPermission(
                    context,
                    Manifest.permission.POST_NOTIFICATIONS,
                ) == PackageManager.PERMISSION_GRANTED
            ) {
                Authorized
            } else {
                NotDetermined
            }
        }
    }
}

fun notificationRegistrationNow(
    creatorId: String,
    fcmToken: String,
    authorizationStatus: NotificationAuthorizationStatus,
    appVersion: String,
): NotificationDeviceRegistration = NotificationDeviceRegistration(
    creatorId = creatorId,
    platform = "Android",
    fcmToken = fcmToken,
    authorizationStatus = authorizationStatus.serverValue,
    appVersion = appVersion,
    lastSeenAt = Instant.now().toString(),
)
