package app.blueprint.capture.ui.screens

import android.annotation.SuppressLint
import android.content.Context
import android.location.Geocoder
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.CancellationSignal
import android.os.Looper
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.LocationOn
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.blueprint.capture.data.launch.LaunchCityMatcher
import app.blueprint.capture.data.launch.LaunchCityRepository
import app.blueprint.capture.data.launch.ResolvedLaunchCity
import app.blueprint.capture.data.launch.SupportedLaunchCity
import app.blueprint.capture.data.permissions.StartupPermissionChecker
import app.blueprint.capture.ui.theme.BlueprintBlack
import app.blueprint.capture.ui.theme.BlueprintBorder
import app.blueprint.capture.ui.theme.BlueprintSurface
import app.blueprint.capture.ui.theme.BlueprintSurfaceCard
import app.blueprint.capture.ui.theme.BlueprintSurfaceRaised
import app.blueprint.capture.ui.theme.BlueprintTeal
import app.blueprint.capture.ui.theme.BlueprintTextMuted
import app.blueprint.capture.ui.theme.BlueprintTextPrimary
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import java.util.Locale
import javax.inject.Inject
import kotlin.coroutines.resume
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

enum class LaunchCityGateStatus {
    Checking,
    LocationPermissionRequired,
    Supported,
    Unsupported,
    Failed,
}

data class LaunchCityGateUiState(
    val status: LaunchCityGateStatus = LaunchCityGateStatus.Checking,
    val detectedCity: ResolvedLaunchCity? = null,
    val supportedCities: List<SupportedLaunchCity> = emptyList(),
    val message: String = "Checking launch access.",
)

@HiltViewModel
class LaunchCityGateViewModel @Inject constructor(
    @ApplicationContext private val context: Context,
    private val startupPermissionChecker: StartupPermissionChecker,
    private val launchCityRepository: LaunchCityRepository,
) : ViewModel() {
    private val _uiState = MutableStateFlow(LaunchCityGateUiState())
    val uiState: StateFlow<LaunchCityGateUiState> = _uiState.asStateFlow()
    private var hasStarted = false

    fun start() {
        if (hasStarted) return
        hasStarted = true
        refresh()
    }

    @SuppressLint("MissingPermission")
    fun refresh() {
        viewModelScope.launch {
            if (!startupPermissionChecker.hasRequiredStartupPermission()) {
                _uiState.value = LaunchCityGateUiState(
                    status = LaunchCityGateStatus.LocationPermissionRequired,
                    message = "Location permission is required before Blueprint can verify launch-city access.",
                )
                return@launch
            }

            _uiState.value = _uiState.value.copy(
                status = LaunchCityGateStatus.Checking,
                message = "Checking launch access.",
            )

            val location = currentLocation()
            if (location == null) {
                _uiState.value = LaunchCityGateUiState(
                    status = LaunchCityGateStatus.Failed,
                    message = "Blueprint could not get a location fix. Make sure location services are on, then check again — a first fix can take a moment outdoors.",
                )
                return@launch
            }

            val resolvedCity = resolveCity(location)
            val status = launchCityRepository.fetchLaunchStatus(
                city = resolvedCity?.city,
                stateCode = resolvedCity?.stateCode,
            ).getOrElse { error ->
                android.util.Log.w("LaunchCityGate", "Launch access check failed", error)
                _uiState.value = LaunchCityGateUiState(
                    status = LaunchCityGateStatus.Failed,
                    detectedCity = resolvedCity,
                    message = if (resolvedCity != null) {
                        "Blueprint found ${resolvedCity.displayName}, but couldn't verify launch access. Check your connection and try again."
                    } else {
                        "Blueprint couldn't verify launch access. Check your connection and try again."
                    },
                )
                return@launch
            }

            val matchedCity = resolvedCity?.let {
                LaunchCityMatcher.supportedCity(it, status.supportedCities)
            }
            val isSupported = status.currentCity?.isSupported ?: (matchedCity != null)
            _uiState.value = LaunchCityGateUiState(
                status = if (isSupported) LaunchCityGateStatus.Supported else LaunchCityGateStatus.Unsupported,
                detectedCity = resolvedCity,
                supportedCities = status.supportedCities,
                message = if (isSupported) {
                    "Launch access verified."
                } else {
                    "Blueprint is only live in supported launch cities right now."
                },
            )
        }
    }

    /**
     * Last-known fix when available, otherwise an active one-shot location
     * request. Fresh installs and new devices commonly have NO cached fix, so
     * relying on `getLastKnownLocation` alone dead-ends first-run users at the
     * gate with no way forward.
     */
    @SuppressLint("MissingPermission")
    private suspend fun currentLocation(): Location? {
        lastKnownLocation()?.let { return it }

        val manager = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager ?: return null
        val provider = listOf(LocationManager.NETWORK_PROVIDER, LocationManager.GPS_PROVIDER)
            .firstOrNull { runCatching { manager.isProviderEnabled(it) }.getOrDefault(false) }
            ?: return null

        return withTimeoutOrNull(FRESH_LOCATION_TIMEOUT_MS) {
            suspendCancellableCoroutine { continuation ->
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    val cancellationSignal = CancellationSignal()
                    continuation.invokeOnCancellation { cancellationSignal.cancel() }
                    runCatching {
                        manager.getCurrentLocation(provider, cancellationSignal, context.mainExecutor) { location ->
                            if (continuation.isActive) continuation.resume(location)
                        }
                    }.onFailure {
                        if (continuation.isActive) continuation.resume(null)
                    }
                } else {
                    // Explicit object (not a SAM lambda): on API 29 the platform
                    // interface still has abstract status/provider callbacks.
                    val listener = object : LocationListener {
                        override fun onLocationChanged(location: Location) {
                            if (continuation.isActive) continuation.resume(location)
                        }

                        @Deprecated("Deprecated in Java")
                        override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) = Unit

                        override fun onProviderEnabled(provider: String) = Unit

                        override fun onProviderDisabled(provider: String) = Unit
                    }
                    continuation.invokeOnCancellation { manager.removeUpdates(listener) }
                    runCatching {
                        @Suppress("DEPRECATION")
                        manager.requestSingleUpdate(provider, listener, Looper.getMainLooper())
                    }.onFailure {
                        if (continuation.isActive) continuation.resume(null)
                    }
                }
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun lastKnownLocation(): Location? {
        val manager = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager ?: return null
        return runCatching {
            manager.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
                ?: manager.getLastKnownLocation(LocationManager.GPS_PROVIDER)
        }.getOrNull()
    }

    private companion object {
        const val FRESH_LOCATION_TIMEOUT_MS = 15_000L
    }

    private suspend fun resolveCity(location: Location): ResolvedLaunchCity? = withContext(Dispatchers.IO) {
        runCatching {
            @Suppress("DEPRECATION")
            val placemark = Geocoder(context, Locale.getDefault())
                .getFromLocation(location.latitude, location.longitude, 1)
                ?.firstOrNull()
                ?: return@withContext null
            val city = placemark.locality
                ?: placemark.subAdminArea
                ?: placemark.featureName
            city?.takeIf(String::isNotBlank)?.let {
                ResolvedLaunchCity(
                    city = it,
                    stateCode = placemark.adminArea,
                    countryCode = placemark.countryCode,
                )
            }
        }.getOrNull()
    }
}

@Composable
fun LaunchCityGateContainer(
    viewModel: LaunchCityGateViewModel = hiltViewModel(),
    content: @Composable () -> Unit,
) {
    val state by viewModel.uiState.collectAsState()
    LaunchedEffect(Unit) {
        viewModel.start()
    }

    if (state.status == LaunchCityGateStatus.Supported) {
        content()
    } else {
        LaunchCityGateScreen(state = state, onRefresh = viewModel::refresh)
    }
}

@Composable
private fun LaunchCityGateScreen(
    state: LaunchCityGateUiState,
    onRefresh: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(BlueprintBlack)
            .statusBarsPadding()
            .navigationBarsPadding()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 22.dp, vertical = 24.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        Text(
            text = "Blueprint city launch",
            style = TextStyle(
                color = BlueprintTextMuted,
                fontSize = 12.sp,
                lineHeight = 16.sp,
                fontWeight = FontWeight.Bold,
                letterSpacing = 2.0.sp,
            ),
        )
        Text(
            text = "We are only live in a few cities right now.",
            style = TextStyle(
                color = BlueprintTextPrimary,
                fontSize = 42.sp,
                lineHeight = 44.sp,
                fontWeight = FontWeight.ExtraBold,
            ),
        )
        Text(
            text = "Your location determines whether the capture network unlocks. Launch availability follows Blueprint's active city program.",
            style = TextStyle(
                color = BlueprintTextMuted,
                fontSize = 16.sp,
                lineHeight = 23.sp,
                fontWeight = FontWeight.Medium,
            ),
        )

        StatusCard(state = state)
        SupportedCitiesCard(cities = state.supportedCities)

        Spacer(modifier = Modifier.height(8.dp))
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(58.dp)
                .clip(RoundedCornerShape(16.dp))
                .background(BlueprintSurfaceRaised)
                .border(1.dp, BlueprintBorder, RoundedCornerShape(16.dp))
                .clickable(onClick = onRefresh),
            contentAlignment = Alignment.Center,
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Rounded.Refresh, contentDescription = null, tint = BlueprintTextPrimary)
                Text(
                    text = "Check again",
                    color = BlueprintTextPrimary,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Bold,
                )
            }
        }
    }
}

@Composable
private fun StatusCard(state: LaunchCityGateUiState) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(24.dp))
            .background(BlueprintSurface)
            .border(1.dp, BlueprintBorder, RoundedCornerShape(24.dp))
            .padding(20.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        verticalAlignment = Alignment.Top,
    ) {
        if (state.status == LaunchCityGateStatus.Checking) {
            CircularProgressIndicator(color = BlueprintTeal, modifier = Modifier.padding(top = 4.dp))
        } else {
            Icon(
                imageVector = Icons.Rounded.LocationOn,
                contentDescription = null,
                tint = BlueprintTeal,
            )
        }
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
                text = when (state.status) {
                    LaunchCityGateStatus.Checking -> "Checking your launch city"
                    LaunchCityGateStatus.LocationPermissionRequired -> "Location needed"
                    LaunchCityGateStatus.Unsupported -> "Not live here yet"
                    LaunchCityGateStatus.Failed -> "Could not verify access"
                    LaunchCityGateStatus.Supported -> "Launch city verified"
                },
                color = BlueprintTextPrimary,
                fontSize = 22.sp,
                lineHeight = 26.sp,
                fontWeight = FontWeight.Bold,
            )
            Text(
                text = state.message,
                color = BlueprintTextMuted,
                fontSize = 14.sp,
                lineHeight = 20.sp,
            )
            state.detectedCity?.let {
                Text(
                    text = "Detected: ${it.displayName}",
                    color = BlueprintTextPrimary,
                    fontSize = 14.sp,
                    lineHeight = 18.sp,
                    fontWeight = FontWeight.SemiBold,
                )
            }
        }
    }
}

@Composable
private fun SupportedCitiesCard(cities: List<SupportedLaunchCity>) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(24.dp))
            .background(BlueprintSurfaceCard)
            .border(1.dp, BlueprintBorder, RoundedCornerShape(24.dp))
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            text = "Supported cities",
            color = BlueprintTextPrimary,
            fontSize = 16.sp,
            fontWeight = FontWeight.Bold,
        )
        Text(
            text = if (cities.isEmpty()) {
                "Supported launch cities will appear after availability syncs."
            } else {
                "Synced from Blueprint's current launch program."
            },
            color = BlueprintTextMuted,
            fontSize = 13.sp,
            lineHeight = 18.sp,
        )
        cities.forEach { city ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(14.dp))
                    .background(BlueprintBlack.copy(alpha = 0.36f))
                    .padding(horizontal = 14.dp, vertical = 12.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = city.displayName,
                    color = BlueprintTextPrimary,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                )
                Icon(Icons.Rounded.CheckCircle, contentDescription = null, tint = Color.White)
            }
        }
    }
}
