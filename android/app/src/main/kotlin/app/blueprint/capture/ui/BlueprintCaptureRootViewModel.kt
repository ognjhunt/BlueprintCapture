package app.blueprint.capture.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.blueprint.capture.data.auth.AuthRepository
import app.blueprint.capture.data.capture.CaptureUploadRepository
import app.blueprint.capture.data.model.CaptureLaunch
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
    val activeCapture: CaptureLaunch? = null,
    val uploads: List<UploadQueueItem> = DemoData.uploadQueue,
)

@HiltViewModel
class BlueprintCaptureRootViewModel @Inject constructor(
    private val sessionPreferences: SessionPreferences,
    private val authRepository: AuthRepository,
    private val captureUploadRepository: CaptureUploadRepository,
) : ViewModel() {
    private val selectedTab = MutableStateFlow(MainTab.Scan)
    private val activeCapture = MutableStateFlow<CaptureLaunch?>(null)

    val uiState: StateFlow<BlueprintCaptureRootUiState> = combine(
        sessionPreferences.onboardingCompleted,
        authRepository.authState,
        selectedTab,
        activeCapture,
        captureUploadRepository.queue,
    ) { onboardingComplete, user, tab, capture, uploadQueue ->
        BlueprintCaptureRootUiState(
            stage = when {
                !onboardingComplete -> RootStage.Onboarding
                user == null -> RootStage.Auth
                else -> RootStage.App
            },
            selectedTab = tab,
            activeCapture = capture,
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

    fun startCaptureSession(capture: CaptureLaunch) {
        activeCapture.value = capture
    }

    fun dismissCaptureSession() {
        activeCapture.value = null
    }

    fun retryUpload(id: String) {
        captureUploadRepository.retryUpload(id)
    }

    fun startUpload(id: String) {
        captureUploadRepository.startUpload(id)
    }

    fun dismissUpload(id: String) {
        captureUploadRepository.dismissUpload(id)
    }

    fun cancelUpload(id: String) {
        captureUploadRepository.cancelUpload(id)
    }
}
