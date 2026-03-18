package app.blueprint.capture.ui.screens

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.blueprint.capture.data.auth.AuthRepository
import app.blueprint.capture.data.capture.CaptureHistoryEntry
import app.blueprint.capture.data.capture.CaptureHistoryRepository
import app.blueprint.capture.data.capture.CaptureSubmissionStage
import app.blueprint.capture.data.config.LocalConfigProvider
import app.blueprint.capture.data.model.ContributorProfile
import app.blueprint.capture.data.profile.ContributorProfileRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlin.math.max

data class WalletUiState(
    val profile: ContributorProfile? = null,
    val hasBackend: Boolean = false,
    val hasStripe: Boolean = false,
    val payoutBannerTitle: String = "Payout setup unavailable",
    val payoutBannerBody: String = "Payout setup is not enabled for this alpha build.",
    val showPayoutBanner: Boolean = true,
    val payoutBannerActionLabel: String? = null,
    val isRefreshing: Boolean = false,
    val payoutEntries: List<CaptureHistoryEntry> = emptyList(),
    val historyEntries: List<CaptureHistoryEntry> = emptyList(),
    val isLedgerLoading: Boolean = false,
) {
    val totalEarningsLabel: String = centsToCurrency(profile?.stats?.totalEarningsCents ?: 0)
    val availableBalanceLabel: String = centsToCurrency(profile?.stats?.availableBalanceCents ?: 0)
    val referralPendingLabel: String = centsToCurrency(
        (profile?.stats?.referralEarningsCents ?: 0) + (profile?.stats?.referralBonusCents ?: 0),
    )
    val totalCaptures: Int = profile?.stats?.totalCaptures ?: 0
    val approvedCaptures: Int = profile?.stats?.approvedCaptures ?: 0
    val approvalRateLabel: String = "${profile?.stats?.approvalRatePercent ?: 0}%"
    val pendingReviewCount: Int = max(totalCaptures - approvedCaptures, 0)
    val cashoutEnabled: Boolean = hasBackend && hasStripe
}

@HiltViewModel
@OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
class WalletViewModel @Inject constructor(
    authRepository: AuthRepository,
    contributorProfileRepository: ContributorProfileRepository,
    private val historyRepository: CaptureHistoryRepository,
    localConfigProvider: LocalConfigProvider,
) : ViewModel() {
    private val config = localConfigProvider.current()
    private val isRefreshing = MutableStateFlow(false)

    private val profileFlow = authRepository.authState.flatMapLatest { user ->
        contributorProfileRepository.observeProfile(user?.uid)
    }

    private val _history = MutableStateFlow<List<CaptureHistoryEntry>>(emptyList())
    private val _historyLoading = MutableStateFlow(false)

    val uiState: StateFlow<WalletUiState> = combine(
        profileFlow, isRefreshing, _history, _historyLoading,
    ) { profile, refreshing, history, historyLoading ->
        WalletUiState(
            profile = profile,
            hasBackend = config.hasBackend,
            hasStripe = config.hasStripe,
            payoutBannerTitle = when {
                !config.hasBackend -> "Payout setup unavailable"
                !config.hasStripe -> "Connect payout method"
                else -> "Wallet is live"
            },
            payoutBannerBody = when {
                !config.hasBackend -> "Payout setup is not enabled for this alpha build."
                !config.hasStripe -> "Connect a payout method to receive earnings."
                else -> "Your Wallet is connected and synced to the signed-in contributor profile."
            },
            showPayoutBanner = !config.hasBackend || !config.hasStripe,
            payoutBannerActionLabel = if (config.hasBackend && !config.hasStripe) "Connect" else null,
            isRefreshing = refreshing,
            payoutEntries = history.filter { it.stage == CaptureSubmissionStage.Paid },
            historyEntries = history,
            isLedgerLoading = historyLoading,
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = WalletUiState(
            hasBackend = config.hasBackend,
            hasStripe = config.hasStripe,
            isLedgerLoading = true,
        ),
    )

    init {
        viewModelScope.launch {
            _historyLoading.value = true
            _history.value = historyRepository.fetchHistory()
            _historyLoading.value = false
        }
    }

    fun refresh() {
        if (isRefreshing.value) return
        viewModelScope.launch {
            isRefreshing.value = true
            _historyLoading.value = true
            _history.value = historyRepository.fetchHistory()
            _historyLoading.value = false
            isRefreshing.value = false
        }
    }
}

private fun centsToCurrency(cents: Int): String = "$" + String.format("%.2f", cents / 100.0)
