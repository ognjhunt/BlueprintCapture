package app.blueprint.capture.ui.screens

import android.annotation.SuppressLint
import android.content.Context
import android.location.Location
import android.location.LocationManager
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.blueprint.capture.data.auth.AuthRepository
import app.blueprint.capture.data.capture.CaptureHistoryRepository
import app.blueprint.capture.data.capture.SubmissionSummary
import app.blueprint.capture.data.config.LocalConfigProvider
import app.blueprint.capture.data.model.ScanTarget
import app.blueprint.capture.data.model.TargetAvailabilityStatus
import app.blueprint.capture.data.notification.GeofenceJobTarget
import app.blueprint.capture.data.notification.GeofenceManager
import app.blueprint.capture.data.profile.ContributorProfileRepository
import app.blueprint.capture.data.targets.ScanTargetsRepository
import app.blueprint.capture.data.targets.TargetStateRepository
import com.google.firebase.auth.FirebaseAuth
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

data class ScanUiState(
    val userName: String = "",
    val targets: List<ScanTarget> = emptyList(),
    val showGlassesBanner: Boolean = true,
    val showPayoutBanner: Boolean = true,
    val payoutBannerTitle: String = "Payout setup unavailable",
    val payoutBannerBody: String = "Payout setup is not enabled for this alpha build.",
    val submissionSummary: SubmissionSummary = SubmissionSummary(),
)

@HiltViewModel
@OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
class ScanViewModel @Inject constructor(
    @ApplicationContext private val context: Context,
    authRepository: AuthRepository,
    contributorProfileRepository: ContributorProfileRepository,
    private val scanTargetsRepository: ScanTargetsRepository,
    private val targetStateRepository: TargetStateRepository,
    private val historyRepository: CaptureHistoryRepository,
    private val geofenceManager: GeofenceManager,
    localConfigProvider: LocalConfigProvider,
) : ViewModel() {

    private val config = localConfigProvider.current()
    private val _userLocation = MutableStateFlow<Location?>(null)
    private val _submissionSummary = MutableStateFlow(SubmissionSummary())

    val uiState: StateFlow<ScanUiState> = combine(
        authRepository.authState.flatMapLatest { user ->
            contributorProfileRepository.observeProfile(user?.uid)
        },
        _userLocation.flatMapLatest { loc ->
            scanTargetsRepository.observeActiveTargets(userLocation = loc)
        },
        _submissionSummary,
    ) { profile, rawTargets, summary ->
        ScanUiState(
            userName = profile?.name.orEmpty(),
            targets = rawTargets,
            payoutBannerTitle = if (config.hasStripe) "Connect payout method"
            else "Payout setup unavailable",
            payoutBannerBody = if (config.hasStripe)
                "Connect a payout method to receive capture earnings."
            else
                "Payout setup is not enabled for this alpha build.",
            submissionSummary = summary,
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = ScanUiState(),
    )

    init {
        refreshLocation()
        loadSubmissionHistory()
    }

    /** Called from the UI when the scan feed becomes visible or on pull-to-refresh. */
    fun onFeedVisible() {
        refreshLocation()
        loadSubmissionHistory()
        applyTargetStatesAndGeofences()
    }

    /**
     * Batch-fetches reservation/availability state from Firestore `target_state` collection,
     * filters out jobs completed or reserved by other users (iOS TargetStateService parity),
     * and schedules geofence proximity alerts for the remaining active jobs.
     */
    fun applyTargetStatesAndGeofences() {
        viewModelScope.launch {
            val targets = uiState.value.targets
            if (targets.isEmpty()) return@launch

            val currentUserId = FirebaseAuth.getInstance().currentUser?.uid ?: return@launch
            val stateMap = targetStateRepository.batchFetchStates(targets.map { it.id })

            // Determine visibility per target — mirrors iOS filterVisibleItems()
            val visible = targets.mapNotNull { target ->
                val state = stateMap[target.id] ?: return@mapNotNull target
                when (state.status) {
                    TargetAvailabilityStatus.Completed -> null
                    TargetAvailabilityStatus.Reserved, TargetAvailabilityStatus.InProgress -> {
                        val owner = state.checkedInBy ?: state.reservedBy
                        if (owner != null && owner != currentUserId) null
                        else target.copy(targetAvailability = state.status)
                    }
                    TargetAvailabilityStatus.Available ->
                        target.copy(targetAvailability = TargetAvailabilityStatus.Available)
                }
            }

            // Schedule up to 10 geofence regions for visible jobs with coordinates
            // Reserved jobs are prioritised, matching iOS NearbyAlertsManager
            val geofenceTargets = visible
                .filter { it.lat != null && it.lng != null }
                .map { t ->
                    GeofenceJobTarget(
                        jobId = t.id,
                        title = t.title,
                        lat = t.lat!!,
                        lng = t.lng!!,
                        payoutDollars = (t.quotedPayoutCents ?: 0) / 100,
                        isReserved = t.targetAvailability == TargetAvailabilityStatus.Reserved,
                    )
                }
            geofenceManager.scheduleNearbyAlerts(geofenceTargets, maxRegions = 10)
        }
    }

    /** Best-effort pull of last known device location for feed ranking + distance labels. */
    @SuppressLint("MissingPermission")
    fun refreshLocation() {
        viewModelScope.launch {
            val lm = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
                ?: return@launch
            val loc = lm.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
                ?: lm.getLastKnownLocation(LocationManager.GPS_PROVIDER)
            if (loc != null) _userLocation.value = loc
        }
    }

    private fun loadSubmissionHistory() {
        viewModelScope.launch {
            _submissionSummary.value = historyRepository.fetchSummary()
        }
    }

    override fun onCleared() {
        super.onCleared()
        geofenceManager.clearAll()
    }
}
