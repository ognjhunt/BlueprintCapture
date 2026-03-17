package app.blueprint.capture.ui.screens

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.blueprint.capture.data.auth.AuthRepository
import app.blueprint.capture.data.config.LocalConfigProvider
import app.blueprint.capture.data.model.ContributorProfile
import app.blueprint.capture.data.profile.ContributorProfileRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn

data class WalletUiState(
    val profile: ContributorProfile? = null,
    val hasBackend: Boolean = false,
    val hasStripe: Boolean = false,
    val payoutReadinessMessage: String = "Backend URL is still empty, so payout actions remain blocked in this build.",
) {
    val totalEarningsLabel: String = centsToCurrency(profile?.stats?.totalEarningsCents ?: 0)
    val availableBalanceLabel: String = centsToCurrency(profile?.stats?.availableBalanceCents ?: 0)
    val referralPendingLabel: String = centsToCurrency(
        (profile?.stats?.referralEarningsCents ?: 0) + (profile?.stats?.referralBonusCents ?: 0),
    )
}

@HiltViewModel
@OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
class WalletViewModel @Inject constructor(
    authRepository: AuthRepository,
    contributorProfileRepository: ContributorProfileRepository,
    localConfigProvider: LocalConfigProvider,
) : ViewModel() {
    private val config = localConfigProvider.current()

    val uiState: StateFlow<WalletUiState> = authRepository.authState.flatMapLatest { user ->
        contributorProfileRepository.observeProfile(user?.uid)
    }.map { profile ->
        WalletUiState(
            profile = profile,
            hasBackend = config.hasBackend,
            hasStripe = config.hasStripe,
            payoutReadinessMessage = when {
                !config.hasBackend -> "Backend URL is still empty, so payout actions remain blocked in this build."
                !config.hasStripe -> "Backend is configured, but Stripe is still missing from local config for payout onboarding."
                else -> "Backend and Stripe keys are configured. Wallet data is now live from the signed-in Firestore profile."
            },
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = WalletUiState(
            hasBackend = config.hasBackend,
            hasStripe = config.hasStripe,
        ),
    )
}

private fun centsToCurrency(cents: Int): String = "$" + String.format("%.2f", cents / 100.0)
