package app.blueprint.capture.data.notification

import android.content.Context
import android.content.pm.PackageInfo
import android.os.Build
import android.util.Log
import app.blueprint.capture.data.auth.AuthRepository
import app.blueprint.capture.data.config.LocalConfigProvider
import com.google.firebase.messaging.FirebaseMessaging
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await

@Singleton
class PushNotificationManager @Inject constructor(
    @ApplicationContext private val context: Context,
    private val authRepository: AuthRepository,
    private val localConfigProvider: LocalConfigProvider,
    private val backendApi: NotificationBackendApi,
    private val notificationPreferencesRepository: NotificationPreferencesRepository,
) {
    private val managerScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val authorizationStatusState = MutableStateFlow(NotificationAuthorizationStatus.fromContext(context))
    private val fcmTokenState = MutableStateFlow("")
    private var didStart = false
    private var hasLoggedMissingBackendBaseUrl = false

    val authorizationStatus = authorizationStatusState.asStateFlow()
    val fcmToken = fcmTokenState.asStateFlow()

    fun start() {
        if (didStart) {
            return
        }
        didStart = true

        managerScope.launch {
            refreshFcmToken()
            authRepository.authState.collectLatest {
                refreshAuthorizationStatus()
                syncCurrentDevice()
                notificationPreferencesRepository.refreshFromBackendIfPossible()
            }
        }
    }

    suspend fun syncCurrentDevice() {
        val creatorId = authRepository.currentUserId().orEmpty()
        if (creatorId.isBlank()) {
            return
        }
        if (!localConfigProvider.current().hasBackend) {
            logMissingBackend("Skipping notification backend calls")
            return
        }

        val token = refreshFcmToken().orEmpty()
        runCatching {
            backendApi.registerNotificationDevice(
                creatorId = creatorId,
                registration = notificationRegistrationNow(
                    creatorId = creatorId,
                    fcmToken = token,
                    authorizationStatus = authorizationStatusState.value,
                    appVersion = appVersion(),
                ),
            )
        }.onFailure { error ->
            Log.w(
                "PushNotifications",
                "Failed to sync device registration: ${error.localizedMessage ?: "unknown error"}",
                error,
            )
        }
    }

    suspend fun refreshAuthorizationStatus() {
        authorizationStatusState.value = NotificationAuthorizationStatus.fromContext(context)
    }

    private suspend fun refreshFcmToken(): String? {
        return runCatching {
            FirebaseMessaging.getInstance().token.await()
        }.onSuccess { token ->
            fcmTokenState.value = token.orEmpty()
        }.onFailure { error ->
            Log.w(
                "PushNotifications",
                "Failed to fetch FCM token: ${error.localizedMessage ?: "unknown error"}",
                error,
            )
        }.getOrNull()
    }

    private fun appVersion(): String {
        val packageInfo: PackageInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.packageManager.getPackageInfo(
                context.packageName,
                android.content.pm.PackageManager.PackageInfoFlags.of(0),
            )
        } else {
            @Suppress("DEPRECATION")
            context.packageManager.getPackageInfo(context.packageName, 0)
        }
        val short = packageInfo.versionName ?: "1.0"
        val build = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            packageInfo.longVersionCode.toString()
        } else {
            @Suppress("DEPRECATION")
            packageInfo.versionCode.toString()
        }
        return "$short ($build)"
    }

    private fun logMissingBackend(prefix: String) {
        if (!hasLoggedMissingBackendBaseUrl) {
            hasLoggedMissingBackendBaseUrl = true
            Log.i(
                "PushNotifications",
                "$prefix because BLUEPRINT_BACKEND_BASE_URL is not configured for this build",
            )
        } else {
            Log.i("PushNotifications", "$prefix because BLUEPRINT_BACKEND_BASE_URL is not configured")
        }
    }
}
