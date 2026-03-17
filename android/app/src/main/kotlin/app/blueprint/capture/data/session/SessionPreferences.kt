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
    }

    private val onboardingCompletedState = MutableStateFlow(
        sharedPreferences.getBoolean(KEY_ONBOARDING_COMPLETE, false),
    )

    val onboardingCompleted: StateFlow<Boolean> = onboardingCompletedState.asStateFlow()

    fun setOnboardingCompleted(completed: Boolean) {
        sharedPreferences.edit().putBoolean(KEY_ONBOARDING_COMPLETE, completed).apply()
        onboardingCompletedState.value = completed
    }
}
