package app.blueprint.capture.data.notification

import android.content.SharedPreferences
import android.util.Log
import app.blueprint.capture.data.auth.AuthRepository
import app.blueprint.capture.data.config.LocalConfigProvider
import app.blueprint.capture.data.ops.OperationalTelemetry
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

@Singleton
class NotificationPreferencesRepository @Inject constructor(
    private val sharedPreferences: SharedPreferences,
    private val authRepository: AuthRepository,
    private val localConfigProvider: LocalConfigProvider,
    private val backendApi: NotificationBackendApi,
    private val operationalTelemetry: OperationalTelemetry,
) {
    private val repositoryScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val preferencesState = MutableStateFlow(load())
    private var hasLoggedMissingBackendBaseUrl = false

    val preferences: StateFlow<NotificationPreferences> = preferencesState.asStateFlow()

    fun set(key: NotificationPreferenceKey, enabled: Boolean) {
        val current = preferencesState.value
        if (current.isEnabled(key) == enabled) {
            return
        }
        val updated = current.with(key, enabled)
        preferencesState.value = updated
        persist(updated)

        repositoryScope.launch {
            syncToBackendIfPossible()
        }
    }

    suspend fun refreshFromBackendIfPossible() {
        val creatorId = authRepository.currentUserId().orEmpty()
        if (creatorId.isBlank()) {
            return
        }
        if (!localConfigProvider.current().hasBackend) {
            logMissingBackend("Skipping preference refresh")
            return
        }

        runCatching {
            backendApi.fetchNotificationPreferences(creatorId)
        }.onSuccess { remote ->
            if (remote != null) {
                preferencesState.value = remote
                persist(remote)
            }
            operationalTelemetry.recordSuccess(operation = "notification_preferences_refresh")
        }.onFailure { error ->
            operationalTelemetry.recordFailure(
                operation = "notification_preferences_refresh",
                detail = error.localizedMessage,
            )
            Log.w(
                "NotificationPrefs",
                "Failed to refresh preferences: ${error.localizedMessage ?: "unknown error"}",
                error,
            )
        }
    }

    suspend fun syncToBackendIfPossible() {
        val creatorId = authRepository.currentUserId().orEmpty()
        if (creatorId.isBlank()) {
            return
        }
        if (!localConfigProvider.current().hasBackend) {
            logMissingBackend("Skipping preference sync")
            return
        }

        runCatching {
            backendApi.updateNotificationPreferences(creatorId, preferencesState.value)
            operationalTelemetry.recordSuccess(operation = "notification_preferences_sync")
        }.onFailure { error ->
            operationalTelemetry.recordFailure(
                operation = "notification_preferences_sync",
                detail = error.localizedMessage,
            )
            Log.w(
                "NotificationPrefs",
                "Failed to sync preferences: ${error.localizedMessage ?: "unknown error"}",
                error,
            )
        }
    }

    private fun load(): NotificationPreferences = NotificationPreferences(
        nearbyJobs = sharedPreferences.getBoolean(KEY_NEARBY_JOBS, true),
        reservations = sharedPreferences.getBoolean(KEY_RESERVATIONS, true),
        captureStatus = sharedPreferences.getBoolean(KEY_CAPTURE_STATUS, true),
        payouts = sharedPreferences.getBoolean(KEY_PAYOUTS, true),
        account = sharedPreferences.getBoolean(KEY_ACCOUNT, true),
    )

    private fun persist(preferences: NotificationPreferences) {
        sharedPreferences.edit()
            .putBoolean(KEY_NEARBY_JOBS, preferences.nearbyJobs)
            .putBoolean(KEY_RESERVATIONS, preferences.reservations)
            .putBoolean(KEY_CAPTURE_STATUS, preferences.captureStatus)
            .putBoolean(KEY_PAYOUTS, preferences.payouts)
            .putBoolean(KEY_ACCOUNT, preferences.account)
            .apply()
    }

    private fun logMissingBackend(prefix: String) {
        if (!hasLoggedMissingBackendBaseUrl) {
            hasLoggedMissingBackendBaseUrl = true
            Log.i(
                "NotificationPrefs",
                "$prefix because BLUEPRINT_BACKEND_BASE_URL is not configured for this build",
            )
        } else {
            Log.i("NotificationPrefs", "$prefix because BLUEPRINT_BACKEND_BASE_URL is not configured")
        }
    }

    private companion object {
        const val KEY_NEARBY_JOBS = "notifications.preference.nearby_jobs"
        const val KEY_RESERVATIONS = "notifications.preference.reservations"
        const val KEY_CAPTURE_STATUS = "notifications.preference.capture_status"
        const val KEY_PAYOUTS = "notifications.preference.payouts"
        const val KEY_ACCOUNT = "notifications.preference.account"
    }
}
