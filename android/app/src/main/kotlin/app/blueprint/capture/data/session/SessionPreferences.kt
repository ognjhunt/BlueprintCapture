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

    val onboardingCompleted: StateFlow<Boolean> = onboardingCompletedState.asStateFlow()
    val authSkipped: StateFlow<Boolean> = authSkippedState.asStateFlow()
    val inviteCodeCompleted: StateFlow<Boolean> = inviteCodeCompletedState.asStateFlow()
    val permissionsCompleted: StateFlow<Boolean> = permissionsCompletedState.asStateFlow()

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
}
