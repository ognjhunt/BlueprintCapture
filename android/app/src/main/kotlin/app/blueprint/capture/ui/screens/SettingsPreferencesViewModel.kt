package app.blueprint.capture.ui.screens

import androidx.lifecycle.ViewModel
import app.blueprint.capture.data.notification.NotificationPreferenceKey
import app.blueprint.capture.data.notification.NotificationPreferences
import app.blueprint.capture.data.notification.NotificationPreferencesRepository
import app.blueprint.capture.data.session.SessionPreferences
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.StateFlow

@HiltViewModel
class SettingsPreferencesViewModel @Inject constructor(
    private val sessionPreferences: SessionPreferences,
    private val notificationPreferencesRepository: NotificationPreferencesRepository,
) : ViewModel() {
    val uploadAutoClear: StateFlow<Boolean> = sessionPreferences.uploadAutoClear
    val notificationPreferences: StateFlow<NotificationPreferences> = notificationPreferencesRepository.preferences

    fun setUploadAutoClear(enabled: Boolean) {
        sessionPreferences.setUploadAutoClear(enabled)
    }

    fun setNotificationPreference(
        key: NotificationPreferenceKey,
        enabled: Boolean,
    ) {
        notificationPreferencesRepository.set(key, enabled)
    }
}
