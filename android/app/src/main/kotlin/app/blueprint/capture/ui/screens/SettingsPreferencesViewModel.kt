package app.blueprint.capture.ui.screens

import androidx.lifecycle.ViewModel
import app.blueprint.capture.data.session.SessionPreferences
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.StateFlow

@HiltViewModel
class SettingsPreferencesViewModel @Inject constructor(
    private val sessionPreferences: SessionPreferences,
) : ViewModel() {
    val uploadAutoClear: StateFlow<Boolean> = sessionPreferences.uploadAutoClear

    fun setUploadAutoClear(enabled: Boolean) {
        sessionPreferences.setUploadAutoClear(enabled)
    }
}
