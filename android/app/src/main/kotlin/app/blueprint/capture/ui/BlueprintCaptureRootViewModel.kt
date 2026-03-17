package app.blueprint.capture.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.blueprint.capture.data.auth.AuthRepository
import app.blueprint.capture.data.model.DemoData
import app.blueprint.capture.data.model.MainTab
import app.blueprint.capture.data.model.RootStage
import app.blueprint.capture.data.model.UploadQueueItem
import app.blueprint.capture.data.session.SessionPreferences
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn

data class BlueprintCaptureRootUiState(
    val stage: RootStage = RootStage.Onboarding,
    val selectedTab: MainTab = MainTab.Scan,
    val uploads: List<UploadQueueItem> = DemoData.uploadQueue,
)

@HiltViewModel
class BlueprintCaptureRootViewModel @Inject constructor(
    private val sessionPreferences: SessionPreferences,
    private val authRepository: AuthRepository,
) : ViewModel() {
    private val selectedTab = MutableStateFlow(MainTab.Scan)
    private val uploads = MutableStateFlow(DemoData.uploadQueue)

    val uiState: StateFlow<BlueprintCaptureRootUiState> = combine(
        sessionPreferences.onboardingCompleted,
        authRepository.authState,
        selectedTab,
        uploads,
    ) { onboardingComplete, user, tab, uploadQueue ->
        BlueprintCaptureRootUiState(
            stage = when {
                !onboardingComplete -> RootStage.Onboarding
                user == null -> RootStage.Auth
                else -> RootStage.App
            },
            selectedTab = tab,
            uploads = uploadQueue,
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = BlueprintCaptureRootUiState(),
    )

    fun completeOnboarding() {
        sessionPreferences.setOnboardingCompleted(true)
    }

    fun selectTab(tab: MainTab) {
        selectedTab.value = tab
    }

    fun queueCapture(label: String) {
        if (uploads.value.any { it.id == "upload-new" }) {
            return
        }
        uploads.value = listOf(
            UploadQueueItem(
                id = "upload-new",
                label = label,
                progress = 0.12f,
            ),
        ) + uploads.value
    }
}
