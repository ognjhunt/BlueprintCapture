package app.blueprint.capture.ui.screens

import android.annotation.SuppressLint
import android.content.Context
import android.location.Geocoder
import android.location.Location
import android.location.LocationManager
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.blueprint.capture.data.auth.AuthRepository
import app.blueprint.capture.data.capture.CaptureHistoryRepository
import app.blueprint.capture.data.capture.SubmissionSummary
import app.blueprint.capture.data.config.LocalConfigProvider
import app.blueprint.capture.data.model.CapturePermissionTone
import app.blueprint.capture.data.model.DemoData
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
import java.util.Locale
import javax.inject.Inject
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

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

    // Reverse-geocoded street address for the alpha current-location card.
    // Defaults to "Your current location" until geocoding resolves.
    private val _alphaAddress = MutableStateFlow("Your current location")

    val uiState: StateFlow<ScanUiState> = combine(
        authRepository.registeredAuthState.flatMapLatest { user ->
            contributorProfileRepository.observeProfile(user?.uid)
        },
        _userLocation.flatMapLatest { loc ->
            scanTargetsRepository.observeActiveTargets(userLocation = loc)
        },
        _submissionSummary,
        _alphaAddress,
    ) { profile, rawTargets, summary, alphaAddr ->
        // Always pin the alpha current-location card first, then live Firestore
        // targets, then the demo/POI cards — mirrors iOS Nearby Spaces carousel.
        val alphaItem = _userLocation.value?.let { loc ->
            buildAlphaCurrentLocationTarget(loc, alphaAddr)
        }
        ScanUiState(
            userName = profile?.name.orEmpty(),
            targets = listOfNotNull(alphaItem) + rawTargets + DemoData.scanTargets,
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
            if (loc != null) {
                _userLocation.value = loc
                // Reverse-geocode in background so the alpha card shows a real address.
                val addr = reverseGeocode(loc)
                if (addr != null) _alphaAddress.value = addr
            }
        }
    }

    private fun loadSubmissionHistory() {
        viewModelScope.launch {
            _submissionSummary.value = historyRepository.fetchSummary()
        }
    }

    /** Reverse-geocodes [location] to a human-readable street address, or null on failure. */
    private suspend fun reverseGeocode(location: Location): String? = withContext(Dispatchers.IO) {
        try {
            @Suppress("DEPRECATION")
            val results = Geocoder(context, Locale.getDefault())
                .getFromLocation(location.latitude, location.longitude, 1)
            val addr = results?.firstOrNull() ?: return@withContext null
            listOfNotNull(
                addr.subThoroughfare?.let { sub -> addr.thoroughfare?.let { "$sub $it" } }
                    ?: addr.thoroughfare,
                addr.locality,
            ).joinToString(", ").takeIf { it.isNotBlank() }
        } catch (_: Exception) {
            null
        }
    }

    /**
     * Builds the hardcoded alpha test [ScanTarget] pinned to the user's current GPS position.
     * Always [CapturePermissionTone.Approved] so it bypasses all permission gates and lets
     * the full non-GPU pipeline run against a live device capture for internal testing.
     */
    private fun buildAlphaCurrentLocationTarget(location: Location, address: String): ScanTarget =
        ScanTarget(
            id = ALPHA_CURRENT_LOCATION_ID,
            title = "Current Location",
            subtitle = address,
            addressText = address,
            payoutText = "$45",
            distanceText = "Here now",
            readyNow = true,
            categoryLabel = "ALPHA",
            estimatedMinutes = 20,
            permissionTone = CapturePermissionTone.Approved,
            lat = location.latitude,
            lng = location.longitude,
            checkinRadiusM = 999_999,
            priorityWeight = 100.0,
            quotedPayoutCents = 4500,
            requestedOutputs = listOf("qualification", "preview_simulation", "deeper_evaluation"),
            workflowName = "Alpha Internal Test Capture",
            workflowSteps = listOf(
                "Capture the full space you are currently in.",
                "Walk through every accessible room or area.",
                "Pause 2-3 seconds at each major transition point.",
                "Capture from multiple heights where possible.",
            ),
            detailChecklist = listOf(
                "Capture the full space you are currently in.",
                "Walk through every accessible room or area.",
                "Pause 2-3 seconds at each major transition point.",
                "Capture from multiple heights where possible.",
            ),
        )

    override fun onCleared() {
        super.onCleared()
        geofenceManager.clearAll()
    }

    companion object {
        const val ALPHA_CURRENT_LOCATION_ID = "alpha-current-location"
    }
}
