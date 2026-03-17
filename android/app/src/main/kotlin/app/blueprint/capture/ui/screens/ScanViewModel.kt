package app.blueprint.capture.ui.screens

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.blueprint.capture.data.auth.AuthRepository
import app.blueprint.capture.data.config.LocalConfigProvider
import app.blueprint.capture.data.model.DemoData
import app.blueprint.capture.data.model.ScanTarget
import app.blueprint.capture.data.profile.ContributorProfileRepository
import app.blueprint.capture.data.targets.ScanTargetsRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.stateIn

data class ScanUiState(
    val userName: String = "",
    val targets: List<ScanTarget> = DemoData.scanTargets,
    val configSummary: String = "Backend URL not set yet",
    val feedSummary: String = "Curated jobs are loading from Firestore.",
) {
    val hasTargets: Boolean = targets.isNotEmpty()
}

@HiltViewModel
@OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
class ScanViewModel @Inject constructor(
    authRepository: AuthRepository,
    contributorProfileRepository: ContributorProfileRepository,
    scanTargetsRepository: ScanTargetsRepository,
    localConfigProvider: LocalConfigProvider,
) : ViewModel() {
    private val config = localConfigProvider.current()

    val uiState: StateFlow<ScanUiState> = combine(
        authRepository.authState.flatMapLatest { user ->
            contributorProfileRepository.observeProfile(user?.uid)
        },
        scanTargetsRepository.observeActiveTargets(),
    ) { profile, targets ->
        ScanUiState(
            userName = profile?.name.orEmpty(),
            targets = targets,
            configSummary = config.backendBaseUrl.ifBlank { "Backend URL not set yet" },
            feedSummary = if (targets == DemoData.scanTargets) {
                "Showing local fallback jobs until Firestore returns curated capture jobs."
            } else {
                "Curated capture jobs are now flowing from Firebase, matching the iOS nearby-opportunities model."
            },
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = ScanUiState(
            configSummary = config.backendBaseUrl.ifBlank { "Backend URL not set yet" },
        ),
    )
}
