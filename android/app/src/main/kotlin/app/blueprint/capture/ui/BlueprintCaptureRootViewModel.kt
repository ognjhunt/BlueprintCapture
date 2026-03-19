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
        combine(
            sessionPreferences.onboardingCompleted,
            sessionPreferences.authSkipped,
            sessionPreferences.inviteCodeCompleted,
            sessionPreferences.permissionsCompleted,
            sessionPreferences.glassesSetupCompleted,
        ) { onboarding, authSkip, invite, perms, glasses -> listOf(onboarding, authSkip, invite, perms, glasses) },
        combine(authRepository.registeredAuthState, selectedTab, activeCapture, captureUploadRepository.queue) { u, t, c, q -> listOf(u, t, c, q) },
    ) { flags, rest ->
        val onboardingComplete = flags[0] as Boolean
        val authSkipped = flags[1] as Boolean
        val inviteCodeComplete = flags[2] as Boolean
        val permissionsComplete = flags[3] as Boolean
        val glassesSetupComplete = flags[4] as Boolean
        @Suppress("UNCHECKED_CAST")
        val user = rest[0]
        val tab = rest[1] as MainTab
        @Suppress("UNCHECKED_CAST")
        val capture = rest[2] as? CaptureLaunch
        @Suppress("UNCHECKED_CAST")
        val uploadQueue = rest[3] as List<UploadQueueItem>
        BlueprintCaptureRootUiState(
            stage = when {
                !onboardingComplete -> RootStage.Onboarding
                user == null && !authSkipped -> RootStage.Auth
                !inviteCodeComplete -> RootStage.InviteCode
                !permissionsComplete -> RootStage.Permissions
                !glassesSetupComplete -> RootStage.ConnectGlasses
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

    fun skipAuth() {
        sessionPreferences.setAuthSkipped(true)
    }

    fun completeInviteCode() {
        sessionPreferences.setInviteCodeCompleted(true)
    }

    fun completePermissions() {
        sessionPreferences.setPermissionsCompleted(true)
    }

    fun completeGlassesSetup() {
        sessionPreferences.setGlassesSetupCompleted(true)
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
