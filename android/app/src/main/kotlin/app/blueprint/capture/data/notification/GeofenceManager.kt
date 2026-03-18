package app.blueprint.capture.data.notification

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingClient
import com.google.android.gms.location.GeofencingEvent
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

data class GeofenceJobTarget(
    val jobId: String,
    val title: String,
    val lat: Double,
    val lng: Double,
    val radiusM: Float = 300f,
    val payoutDollars: Int = 0,
    val isReserved: Boolean = false,
)

@Singleton
class GeofenceManager @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    private val client: GeofencingClient = LocationServices.getGeofencingClient(context)
    private val activeIds = mutableListOf<String>()

    private val pendingIntent: PendingIntent by lazy {
        val intent = Intent(context, GeofenceBroadcastReceiver::class.java)
        PendingIntent.getBroadcast(
            context,
            REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
        )
    }

    /**
     * Registers up to [maxRegions] geofences around active job sites.
     * Reserved jobs are prioritised over non-reserved ones (matching iOS NearbyAlertsManager).
     * Requires ACCESS_FINE_LOCATION and ACCESS_BACKGROUND_LOCATION (Android 10+).
     */
    fun scheduleNearbyAlerts(targets: List<GeofenceJobTarget>, maxRegions: Int = 10) {
        clearAll()

        if (!hasFineLocation()) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && !hasBackgroundLocation()) return

        // Reserved jobs first, then fill remaining slots in feed order
        val prioritised = buildList {
            addAll(targets.filter { it.isReserved })
            targets.filterNot { it.isReserved }.forEach { t ->
                if (size < maxRegions) add(t)
            }
        }.take(maxRegions)

        if (prioritised.isEmpty()) return

        val geofences = prioritised.map { target ->
            val id = geofenceId(target.jobId)
            activeIds += id
            Geofence.Builder()
                .setRequestId(id)
                .setCircularRegion(target.lat, target.lng, target.radiusM)
                .setExpirationDuration(Geofence.NEVER_EXPIRE)
                .setTransitionTypes(Geofence.GEOFENCE_TRANSITION_ENTER)
                .build()
        }

        val request = GeofencingRequest.Builder()
            .setInitialTrigger(GeofencingRequest.INITIAL_TRIGGER_ENTER)
            .addGeofences(geofences)
            .build()

        runCatching { client.addGeofences(request, pendingIntent) }
    }

    fun clearAll() {
        if (activeIds.isNotEmpty()) {
            runCatching { client.removeGeofences(activeIds.toList()) }
            activeIds.clear()
        }
    }

    private fun hasFineLocation(): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED

    private fun hasBackgroundLocation(): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_BACKGROUND_LOCATION) ==
            PackageManager.PERMISSION_GRANTED

    companion object {
        private const val REQUEST_CODE = 9001
        fun geofenceId(jobId: String) = "blueprint_job_$jobId"
    }
}

/** Handles geofence entry events and posts a heads-up notification. */
class GeofenceBroadcastReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val event = GeofencingEvent.fromIntent(intent) ?: return
        if (event.hasError()) return
        val geofences = event.triggeringGeofences ?: return
        for (geofence in geofences) {
            val jobId = geofence.requestId.removePrefix("blueprint_job_")
            postProximityNotification(context, jobId)
        }
    }

    private fun postProximityNotification(context: Context, jobId: String) {
        val channelId = "blueprint_proximity"
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    channelId,
                    "Nearby scan jobs",
                    NotificationManager.IMPORTANCE_DEFAULT,
                ).apply { description = "Alerts when you're near an active capture job." }
            )
        }

        val notification = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(android.R.drawable.ic_dialog_map)
            .setContentTitle("You're near a scan job")
            .setContentText("Open Blueprint Capture to start scanning and earn.")
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()

        val notifId = jobId.hashCode().let { if (it == Int.MIN_VALUE) 1 else kotlin.math.abs(it) }
        manager.notify(notifId, notification)
    }
}
