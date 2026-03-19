package app.blueprint.capture.data.session

import android.content.SharedPreferences
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

@Singleton
class SessionPreferences @Inject constructor(
    private val sharedPreferences: SharedPreferences,
) {
    companion object {
        private const val KEY_ONBOARDING_COMPLETE = "onboarding_complete"
        private const val KEY_AUTH_SKIPPED = "auth_skipped"
        private const val KEY_INVITE_CODE_COMPLETE = "invite_code_complete"
        private const val KEY_PERMISSIONS_COMPLETE = "permissions_complete"
        private const val KEY_WALKTHROUGH_COMPLETE = "walkthrough_complete"
        private const val KEY_GLASSES_SETUP_COMPLETE = "glasses_setup_complete"
        private const val KEY_UPLOAD_AUTO_CLEAR = "upload_auto_clear"
    }

    private val onboardingCompletedState = MutableStateFlow(
        sharedPreferences.getBoolean(KEY_ONBOARDING_COMPLETE, false),
    )
    private val authSkippedState = MutableStateFlow(
        sharedPreferences.getBoolean(KEY_AUTH_SKIPPED, false),
    )
    private val inviteCodeCompletedState = MutableStateFlow(
        sharedPreferences.getBoolean(KEY_INVITE_CODE_COMPLETE, false),
    )
    private val permissionsCompletedState = MutableStateFlow(
        sharedPreferences.getBoolean(KEY_PERMISSIONS_COMPLETE, false),
    )
    private val walkthroughCompletedState = MutableStateFlow(
        sharedPreferences.getBoolean(KEY_WALKTHROUGH_COMPLETE, false),
    )
    private val glassesSetupCompletedState = MutableStateFlow(
        sharedPreferences.getBoolean(KEY_GLASSES_SETUP_COMPLETE, false),
    )
    private val uploadAutoClearState = MutableStateFlow(
        sharedPreferences.getBoolean(KEY_UPLOAD_AUTO_CLEAR, true),
    )

    val onboardingCompleted: StateFlow<Boolean> = onboardingCompletedState.asStateFlow()
    val authSkipped: StateFlow<Boolean> = authSkippedState.asStateFlow()
    val inviteCodeCompleted: StateFlow<Boolean> = inviteCodeCompletedState.asStateFlow()
    val permissionsCompleted: StateFlow<Boolean> = permissionsCompletedState.asStateFlow()
    val walkthroughCompleted: StateFlow<Boolean> = walkthroughCompletedState.asStateFlow()
    val glassesSetupCompleted: StateFlow<Boolean> = glassesSetupCompletedState.asStateFlow()
    val uploadAutoClear: StateFlow<Boolean> = uploadAutoClearState.asStateFlow()

    fun setOnboardingCompleted(completed: Boolean) {
        sharedPreferences.edit().putBoolean(KEY_ONBOARDING_COMPLETE, completed).apply()
        onboardingCompletedState.value = completed
    }

    fun setAuthSkipped(skipped: Boolean) {
        sharedPreferences.edit().putBoolean(KEY_AUTH_SKIPPED, skipped).apply()
        authSkippedState.value = skipped
    }

    fun setInviteCodeCompleted(completed: Boolean) {
        sharedPreferences.edit().putBoolean(KEY_INVITE_CODE_COMPLETE, completed).apply()
        inviteCodeCompletedState.value = completed
    }

    fun setPermissionsCompleted(completed: Boolean) {
        sharedPreferences.edit().putBoolean(KEY_PERMISSIONS_COMPLETE, completed).apply()
        permissionsCompletedState.value = completed
    }

    fun setWalkthroughCompleted(completed: Boolean) {
        sharedPreferences.edit().putBoolean(KEY_WALKTHROUGH_COMPLETE, completed).apply()
        walkthroughCompletedState.value = completed
    }

    fun setGlassesSetupCompleted(completed: Boolean) {
        sharedPreferences.edit().putBoolean(KEY_GLASSES_SETUP_COMPLETE, completed).apply()
        glassesSetupCompletedState.value = completed
    }

    fun setUploadAutoClear(enabled: Boolean) {
        sharedPreferences.edit().putBoolean(KEY_UPLOAD_AUTO_CLEAR, enabled).apply()
        uploadAutoClearState.value = enabled
    }
}
