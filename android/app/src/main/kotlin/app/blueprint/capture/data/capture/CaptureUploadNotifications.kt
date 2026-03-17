package app.blueprint.capture.data.capture

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.work.ForegroundInfo
import app.blueprint.capture.MainActivity
import app.blueprint.capture.data.model.UploadQueueItem
import app.blueprint.capture.data.model.UploadQueueStatus

object CaptureUploadNotifications {
    private const val CHANNEL_ID = "capture_uploads"
    private const val CHANNEL_NAME = "Capture uploads"
    private const val CHANNEL_DESCRIPTION = "Progress for capture bundle uploads and submission registration."

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = CHANNEL_DESCRIPTION
        }
        manager.createNotificationChannel(channel)
    }

    fun buildForegroundInfo(item: UploadQueueItem): ForegroundInfo {
        val context = appContext ?: error("Notification context was not initialized.")
        ensureChannel(context)

        val active = item.status == UploadQueueStatus.Queued ||
            item.status == UploadQueueStatus.Preparing ||
            item.status == UploadQueueStatus.Uploading ||
            item.status == UploadQueueStatus.Registering

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(
                if (active) {
                    android.R.drawable.stat_sys_upload
                } else {
                    android.R.drawable.stat_sys_upload_done
                },
            )
            .setContentTitle(titleFor(item))
            .setContentText(detailFor(item))
            .setOnlyAlertOnce(true)
            .setOngoing(active)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setContentIntent(contentIntent(context))
            .setProgress(
                100,
                (item.progress * 100).toInt().coerceIn(0, 100),
                item.status == UploadQueueStatus.Queued || item.status == UploadQueueStatus.Preparing,
            )
            .build()

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ForegroundInfo(
                notificationIdFor(item.id),
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            ForegroundInfo(notificationIdFor(item.id), notification)
        }
    }

    fun initialize(context: Context) {
        appContext = context.applicationContext
        ensureChannel(context.applicationContext)
    }

    private fun titleFor(item: UploadQueueItem): String {
        return when (item.status) {
            UploadQueueStatus.Saved -> "Capture saved"
            UploadQueueStatus.Queued,
            UploadQueueStatus.Preparing,
            -> "Preparing upload"
            UploadQueueStatus.Uploading -> "Uploading capture"
            UploadQueueStatus.Registering -> "Submitting capture"
            UploadQueueStatus.Completed -> "Capture submitted"
            UploadQueueStatus.Failed -> "Upload issue"
        }
    }

    private fun detailFor(item: UploadQueueItem): String {
        val base = item.detail.ifBlank { item.label }
        return if (base == item.label) {
            item.label
        } else {
            "${item.label} • $base"
        }
    }

    private fun contentIntent(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun notificationIdFor(uploadId: String): Int {
        return uploadId.hashCode().let { if (it == Int.MIN_VALUE) 1 else kotlin.math.abs(it) }
    }

    @Volatile
    private var appContext: Context? = null
}
