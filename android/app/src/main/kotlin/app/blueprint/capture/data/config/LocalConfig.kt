package app.blueprint.capture.data.config

import app.blueprint.capture.BuildConfig
import javax.inject.Inject
import javax.inject.Singleton

enum class NearbyDiscoveryProvider {
    PlacesNearby,
    GeminiMapsGrounding;

    val rawValue: String
        get() = when (this) {
            PlacesNearby -> "places_nearby"
            GeminiMapsGrounding -> "gemini_maps_grounding"
        }

    companion object {
        fun fromRaw(raw: String?): NearbyDiscoveryProvider = when (raw?.trim()?.lowercase()) {
            "gemini_maps_grounding" -> GeminiMapsGrounding
            else -> PlacesNearby
        }
    }
}

data class LocalConfig(
    val backendBaseUrl: String,
    val demandBackendBaseUrl: String,
    val allowMockJobsFallback: Boolean,
    val enableOpenCaptureHere: Boolean,
    val stripePublishableKey: String,
    val nearbyDiscoveryProvider: NearbyDiscoveryProvider,
    val enableGeminiMapsGroundingFallback: Boolean,
) {
    val hasBackend: Boolean = backendBaseUrl.isNotBlank()
    val hasDemandBackend: Boolean = demandBackendBaseUrl.isNotBlank() || hasBackend
    val hasNearbyDiscovery: Boolean = hasDemandBackend
    val hasStripe: Boolean = stripePublishableKey.isNotBlank()
}

@Singleton
class LocalConfigProvider @Inject constructor() {
    fun current(): LocalConfig = LocalConfig(
        backendBaseUrl = BuildConfig.BACKEND_BASE_URL,
        demandBackendBaseUrl = BuildConfig.DEMAND_BACKEND_BASE_URL,
        allowMockJobsFallback = BuildConfig.ALLOW_MOCK_JOBS_FALLBACK,
        enableOpenCaptureHere = BuildConfig.ENABLE_OPEN_CAPTURE_HERE,
        stripePublishableKey = BuildConfig.STRIPE_PUBLISHABLE_KEY,
        nearbyDiscoveryProvider = NearbyDiscoveryProvider.fromRaw(BuildConfig.NEARBY_DISCOVERY_PROVIDER),
        enableGeminiMapsGroundingFallback = BuildConfig.ENABLE_GEMINI_MAPS_GROUNDING_FALLBACK,
    )
}
