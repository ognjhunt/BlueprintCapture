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
import app.blueprint.capture.data.places.NearbyPlace
import app.blueprint.capture.data.places.PlacesRepository
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
import kotlin.math.abs

data class ScanUiState(
    val userName: String = "",
    val targets: List<ScanTarget> = emptyList(),
    val nearbyPlaceTargets: List<ScanTarget> = emptyList(),
    val isRefreshing: Boolean = false,
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
    private val placesRepository: PlacesRepository,
    localConfigProvider: LocalConfigProvider,
) : ViewModel() {

    private val config = localConfigProvider.current()
    private val _userLocation = MutableStateFlow<Location?>(null)
    private val _feedRefreshToken = MutableStateFlow(0)
    private val _submissionSummary = MutableStateFlow(SubmissionSummary())
    private val _nearbyPlaces = MutableStateFlow<List<NearbyPlace>>(emptyList())
    private val _isRefreshing = MutableStateFlow(false)

    // Reverse-geocoded street address for the alpha current-location card.
    // Defaults to "Your current location" until geocoding resolves.
    private val _alphaAddress = MutableStateFlow("Your current location")
    private var lastNearbyDiscoveryLocation: Location? = null

    private val baseUiState = combine(
        authRepository.registeredAuthState.flatMapLatest { user ->
            contributorProfileRepository.observeProfile(user?.uid)
        },
        combine(_userLocation, _feedRefreshToken) { loc, _ -> loc }.flatMapLatest { loc ->
            scanTargetsRepository.observeActiveTargets(userLocation = loc)
        },
        _submissionSummary,
        _alphaAddress,
        _nearbyPlaces,
    ) { profile, rawTargets, summary, alphaAddr, nearbyPlaces ->
        // Always pin the alpha current-location card first. Nearby POIs are a separate
        // supplemental rail source, matching iOS where dynamic local places are appended
        // after the live jobs instead of replacing the approved alpha card.
        val alphaItem = _userLocation.value?.let { loc ->
            buildAlphaCurrentLocationTarget(loc, alphaAddr)
        }
        val primaryTargets = listOfNotNull(alphaItem) + rawTargets
        val discoveredNearbyTargets = nearbyPlaces
            .mapNotNull { place -> _userLocation.value?.let { location -> place.toNearbyScanTarget(location) } }
            .filterNot { supplemental ->
                primaryTargets.any { existing -> existing.isSamePhysicalPlaceAs(supplemental) }
            }
            .take(5)
        val fallbackNearbyTargets = if (discoveredNearbyTargets.isEmpty()) {
            DemoData.scanTargets.take(5)
        } else {
            emptyList()
        }
        ScanUiState(
            userName = profile?.name.orEmpty(),
            targets = primaryTargets,
            nearbyPlaceTargets = discoveredNearbyTargets.ifEmpty { fallbackNearbyTargets },
            payoutBannerTitle = if (config.hasStripe) "Connect payout method"
            else "Payout setup unavailable",
            payoutBannerBody = if (config.hasStripe)
                "Connect a payout method to receive capture earnings."
            else
                "Payout setup is not enabled for this alpha build.",
            submissionSummary = summary,
        )
    }

    val uiState: StateFlow<ScanUiState> = combine(baseUiState, _isRefreshing) { state, isRefreshing ->
        state.copy(isRefreshing = isRefreshing)
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
        refreshFeed(forceNearbyPlaces = false)
    }

    fun refreshFeed(forceNearbyPlaces: Boolean = true) {
        _isRefreshing.value = true
        if (forceNearbyPlaces) {
            lastNearbyDiscoveryLocation = null
        }
        _feedRefreshToken.value += 1
        refreshLocation(forceNearbyPlaces = forceNearbyPlaces)
        loadSubmissionHistory()
        applyTargetStatesAndGeofences()
        viewModelScope.launch {
            kotlinx.coroutines.delay(900)
            _isRefreshing.value = false
        }
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
    fun refreshLocation(forceNearbyPlaces: Boolean = false) {
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
                refreshNearbyPlaces(loc, force = forceNearbyPlaces)
            }
        }
    }

    private fun refreshNearbyPlaces(location: Location, force: Boolean = false) {
        if (!config.hasPlaces) {
            _nearbyPlaces.value = emptyList()
            return
        }
        if (!force && lastNearbyDiscoveryLocation?.isWithinMeters(location, 250f) == true && _nearbyPlaces.value.isNotEmpty()) {
            return
        }
        lastNearbyDiscoveryLocation = location
        viewModelScope.launch {
            _nearbyPlaces.value = placesRepository.searchNearby(location)
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

private fun NearbyPlace.toNearbyScanTarget(userLocation: Location): ScanTarget {
    val targetLocation = Location("nearby-place").apply {
        latitude = lat
        longitude = lng
    }
    val distanceMeters = userLocation.distanceTo(targetLocation).toDouble()
    val metadata = nearbyMetadata(types)
    return ScanTarget(
        id = "poi-$placeId",
        title = name,
        subtitle = condensedAddress(address).ifBlank { name },
        payoutText = metadata.payoutText,
        distanceText = ScanTargetsRepository.formatDistanceMiles(distanceMeters),
        readyNow = false,
        addressText = condensedAddress(address).ifBlank { name },
        categoryLabel = metadata.categoryLabel,
        estimatedMinutes = metadata.estimatedMinutes,
        permissionTone = CapturePermissionTone.Review,
        detailChecklist = listOf(
            "Capture only common areas and accessible circulation paths.",
            "Avoid faces, screens, paperwork, and restricted zones.",
            "If staff objects or signage restricts access, stop and submit for review instead.",
        ),
        workflowName = "Nearby space review",
        workflowSteps = listOf(
            "Start at the public entry or main approach.",
            "Walk the accessible common areas in one continuous pass.",
            "Pause at major transitions and call out blocked or restricted areas.",
        ),
        requestedOutputs = listOf("qualification", "review_intake"),
        quotedPayoutCents = metadata.payoutCents,
        lat = lat,
        lng = lng,
    )
}

private data class NearbyPresentation(
    val categoryLabel: String,
    val payoutText: String,
    val payoutCents: Int,
    val estimatedMinutes: Int,
)

private fun nearbyMetadata(types: List<String>): NearbyPresentation {
    val normalized = types.map { it.lowercase(Locale.US) }.toSet()
    return when {
        normalized.any { it in setOf("store", "shopping_mall", "department_store", "supermarket") } ->
            NearbyPresentation("RETAIL", "$40", 4_000, 25)
        normalized.any { it in setOf("hotel", "lodging") } ->
            NearbyPresentation("HOSPITALITY", "$80", 8_000, 40)
        normalized.contains("parking") ->
            NearbyPresentation("PARKING", "$30", 3_000, 20)
        normalized.contains("gym") ->
            NearbyPresentation("FITNESS", "$45", 4_500, 30)
        normalized.contains("museum") ->
            NearbyPresentation("CULTURAL", "$65", 6_500, 40)
        normalized.contains("stadium") ->
            NearbyPresentation("VENUE", "$120", 12_000, 60)
        normalized.any { it in setOf("transit_station", "train_station", "subway_station", "bus_station") } ->
            NearbyPresentation("TRANSIT", "$50", 5_000, 30)
        normalized.contains("library") ->
            NearbyPresentation("LIBRARY", "$35", 3_500, 25)
        normalized.any { it in setOf("movie_theater", "performing_arts_theater") } ->
            NearbyPresentation("THEATER", "$90", 9_000, 50)
        normalized.any { it in setOf("university", "school") } ->
            NearbyPresentation("CAMPUS", "$55", 5_500, 35)
        else -> NearbyPresentation("COMMERCIAL", "$45", 4_500, 30)
    }
}

private fun condensedAddress(address: String): String {
    if (address.isBlank()) return ""
    val parts = address.split(",").map { it.trim() }.filter { it.isNotBlank() }
    return when {
        parts.size >= 2 -> "${parts[0]} · ${parts[1]}"
        else -> address
    }
}

private fun ScanTarget.isSamePhysicalPlaceAs(other: ScanTarget): Boolean {
    if (lat != null && lng != null && other.lat != null && other.lng != null) {
        return abs(lat - other.lat) < 0.0008 && abs(lng - other.lng) < 0.0008
    }
    return title.equals(other.title, ignoreCase = true) &&
        addressText.equals(other.addressText, ignoreCase = true)
}

private fun Location.isWithinMeters(other: Location, thresholdMeters: Float): Boolean =
    distanceTo(other) <= thresholdMeters
