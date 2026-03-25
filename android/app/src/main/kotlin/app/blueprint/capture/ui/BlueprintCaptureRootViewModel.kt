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
import app.blueprint.capture.data.permissions.StartupPermissionChecker
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

private data class IntroFlags(
    val onboardingComplete: Boolean,
    val authSkipped: Boolean,
    val inviteCodeComplete: Boolean,
)

private data class CaptureFlags(
    val permissionsComplete: Boolean,
    val walkthroughComplete: Boolean,
    val glassesSetupComplete: Boolean,
)

private data class StageFlags(
    val onboardingComplete: Boolean,
    val authSkipped: Boolean,
    val inviteCodeComplete: Boolean,
    val permissionsComplete: Boolean,
    val walkthroughComplete: Boolean,
    val glassesSetupComplete: Boolean,
)

@HiltViewModel
class BlueprintCaptureRootViewModel @Inject constructor(
    private val sessionPreferences: SessionPreferences,
    private val authRepository: AuthRepository,
    private val captureUploadRepository: CaptureUploadRepository,
    private val startupPermissionChecker: StartupPermissionChecker,
) : ViewModel() {
    private val selectedTab = MutableStateFlow(MainTab.Scan)
    private val activeCapture = MutableStateFlow<CaptureLaunch?>(null)

    private val introFlags = combine(
        sessionPreferences.onboardingCompleted,
        sessionPreferences.authSkipped,
        sessionPreferences.inviteCodeCompleted,
    ) { onboarding: Boolean, authSkip: Boolean, invite: Boolean ->
        IntroFlags(
            onboardingComplete = onboarding,
            authSkipped = authSkip,
            inviteCodeComplete = invite,
        )
    }

    private val captureFlags = combine(
        sessionPreferences.permissionsCompleted,
        sessionPreferences.walkthroughCompleted,
        sessionPreferences.glassesSetupCompleted,
    ) { permissions: Boolean, walkthrough: Boolean, glasses: Boolean ->
        CaptureFlags(
            permissionsComplete = permissions,
            walkthroughComplete = walkthrough,
            glassesSetupComplete = glasses,
        )
    }

    private val stageFlags = combine(
        introFlags,
        captureFlags,
    ) { intro, capture ->
        StageFlags(
            onboardingComplete = intro.onboardingComplete,
            authSkipped = intro.authSkipped,
            inviteCodeComplete = intro.inviteCodeComplete,
            permissionsComplete = capture.permissionsComplete,
            walkthroughComplete = capture.walkthroughComplete,
            glassesSetupComplete = capture.glassesSetupComplete,
        )
    }

    private val sessionState = combine(
        authRepository.registeredAuthState,
        selectedTab,
        activeCapture,
        captureUploadRepository.queue,
    ) { user, tab, capture, queue ->
        listOf(user, tab, capture, queue)
    }

    val uiState: StateFlow<BlueprintCaptureRootUiState> = combine(stageFlags, sessionState) { flags, rest ->
        @Suppress("UNCHECKED_CAST")
        val user = rest[0]
        val tab = rest[1] as MainTab
        @Suppress("UNCHECKED_CAST")
        val capture = rest[2] as? CaptureLaunch
        @Suppress("UNCHECKED_CAST")
        val uploadQueue = rest[3] as List<UploadQueueItem>
        BlueprintCaptureRootUiState(
            stage = resolveRootStage(
                onboardingComplete = flags.onboardingComplete,
                hasRegisteredUser = user != null,
                authSkipped = flags.authSkipped,
                inviteCodeComplete = flags.inviteCodeComplete,
                permissionsComplete = flags.permissionsComplete,
                hasStartupPermissions = startupPermissionChecker.hasRequiredStartupPermission(),
                walkthroughComplete = flags.walkthroughComplete,
                glassesSetupComplete = flags.glassesSetupComplete,
            ),
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

    fun completeWalkthrough() {
        sessionPreferences.setWalkthroughCompleted(true)
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

internal fun resolveRootStage(
    onboardingComplete: Boolean,
    hasRegisteredUser: Boolean,
    authSkipped: Boolean,
    inviteCodeComplete: Boolean,
    permissionsComplete: Boolean,
    hasStartupPermissions: Boolean,
    walkthroughComplete: Boolean,
    glassesSetupComplete: Boolean,
): RootStage = when {
    !onboardingComplete -> RootStage.Onboarding
    !hasRegisteredUser && !authSkipped -> RootStage.Auth
    !inviteCodeComplete -> RootStage.InviteCode
    !permissionsComplete || !hasStartupPermissions -> RootStage.Permissions
    !walkthroughComplete -> RootStage.Walkthrough
    !glassesSetupComplete -> RootStage.ConnectGlasses
    else -> RootStage.App
}
