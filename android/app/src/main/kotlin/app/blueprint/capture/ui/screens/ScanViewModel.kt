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
    val showGlassesBanner: Boolean = true,
    val showPayoutBanner: Boolean = true,
    val payoutBannerTitle: String = "Payout setup unavailable",
    val payoutBannerBody: String = "Payout setup is not enabled for this alpha build.",
)

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
            payoutBannerTitle = if (config.hasStripe) {
                "Connect payout method"
            } else {
                "Payout setup unavailable"
            },
            payoutBannerBody = if (config.hasStripe) {
                "Connect a payout method to receive capture earnings."
            } else {
                "Payout setup is not enabled for this alpha build."
            },
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = ScanUiState(),
    )
}
