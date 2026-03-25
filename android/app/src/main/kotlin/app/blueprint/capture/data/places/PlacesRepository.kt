package app.blueprint.capture.data.places

import android.location.Location
import app.blueprint.capture.data.capture.SiteGeoPoint
import app.blueprint.capture.data.capture.SiteIdentity
import app.blueprint.capture.data.config.LocalConfig
import app.blueprint.capture.data.config.LocalConfigProvider
import app.blueprint.capture.data.config.NearbyDiscoveryProvider
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.decodeFromString
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

data class PlacePrediction(
    val placeId: String,
    val primaryText: String,
    val secondaryText: String,
    val fullText: String,
)

data class PlaceDetails(
    val placeId: String,
    val name: String?,
    val addressFull: String?,
    val lat: Double?,
    val lng: Double?,
)

data class NearbyPlace(
    val placeId: String,
    val name: String,
    val address: String,
    val lat: Double,
    val lng: Double,
    val types: List<String>,
)

@Singleton
class PlacesRepository @Inject constructor(
    private val localConfigProvider: LocalConfigProvider,
) {
    private val httpClient = OkHttpClient()
    private val json = Json { ignoreUnknownKeys = true }

    fun initialize(apiKey: String) {
        // Nearby/provider calls are proxied through the backend; mobile API keys are ignored.
    }

    suspend fun searchNearby(
        location: Location,
        radiusMeters: Int = 4_000,
        maxResultCount: Int = 8,
    ): List<NearbyPlace> = withContext(Dispatchers.IO) {
        val config = localConfigProvider.current()
        if (!config.hasDemandBackend) return@withContext emptyList()

        val response = postJson<NearbyDiscoveryRequest, NearbyDiscoveryResponse>(
            config = config,
            path = "v1/nearby/discovery",
            payload = NearbyDiscoveryRequest(
                lat = location.latitude,
                lng = location.longitude,
                radiusMeters = radiusMeters,
                limit = maxResultCount,
                includedTypes = listOf(
                    "store",
                    "shopping_mall",
                    "department_store",
                    "supermarket",
                    "warehouse_store",
                    "hardware_store",
                    "home_improvement_store",
                    "home_goods_store",
                    "furniture_store",
                    "hotel",
                    "lodging",
                    "parking",
                    "gym",
                    "museum",
                    "stadium",
                    "transit_station",
                    "library",
                    "movie_theater",
                    "university",
                ),
                providerHint = config.nearbyDiscoveryProvider.rawValue,
                allowFallback = config.enableGeminiMapsGroundingFallback,
            ),
        ) ?: return@withContext emptyList()

        response.places.map { place ->
            NearbyPlace(
                placeId = place.placeId,
                name = place.displayName,
                address = place.formattedAddress.orEmpty(),
                lat = place.lat,
                lng = place.lng,
                types = place.placeTypes,
            )
        }
    }

    suspend fun autocomplete(query: String): List<PlacePrediction> = withContext(Dispatchers.IO) {
        if (query.isBlank()) return@withContext emptyList()
        val config = localConfigProvider.current()
        if (!config.hasDemandBackend) return@withContext emptyList()

        val response = postJson<PlacesAutocompleteRequest, PlacesAutocompleteResponse>(
            config = config,
            path = "v1/places/autocomplete",
            payload = PlacesAutocompleteRequest(
                query = query,
                providerHint = NearbyDiscoveryProvider.PlacesNearby.rawValue,
                allowFallback = false,
            ),
        ) ?: return@withContext emptyList()

        response.suggestions.map { suggestion ->
            val fullText = listOf(suggestion.primaryText, suggestion.secondaryText)
                .filter { it.isNotBlank() }
                .joinToString(", ")
            PlacePrediction(
                placeId = suggestion.placeId,
                primaryText = suggestion.primaryText,
                secondaryText = suggestion.secondaryText,
                fullText = fullText,
            )
        }
    }

    suspend fun fetchDetails(placeId: String): PlaceDetails? = withContext(Dispatchers.IO) {
        val config = localConfigProvider.current()
        if (!config.hasDemandBackend || placeId.isBlank()) return@withContext null

        val response = postJson<PlacesDetailsRequest, PlacesDetailsResponse>(
            config = config,
            path = "v1/places/details",
            payload = PlacesDetailsRequest(
                placeIds = listOf(placeId),
                providerHint = NearbyDiscoveryProvider.PlacesNearby.rawValue,
                allowFallback = false,
            ),
        ) ?: return@withContext null

        response.places.firstOrNull()?.let { place ->
            PlaceDetails(
                placeId = place.placeId,
                name = place.displayName,
                addressFull = place.formattedAddress,
                lat = place.lat,
                lng = place.lng,
            )
        }
    }

    fun toSiteIdentity(details: PlaceDetails): SiteIdentity = SiteIdentity(
        siteId = details.placeId,
        siteIdSource = "open_capture",
        placeId = details.placeId,
        siteName = details.name,
        addressFull = details.addressFull,
        geo = if (details.lat != null && details.lng != null) {
            SiteGeoPoint(latitude = details.lat, longitude = details.lng)
        } else {
            null
        },
    )

    private inline fun <reified RequestBody : Any, reified ResponseBody : Any> postJson(
        config: LocalConfig,
        path: String,
        payload: RequestBody,
    ): ResponseBody? {
        val baseUrl = config.demandBackendBaseUrl.ifBlank { config.backendBaseUrl }.trim()
        if (baseUrl.isBlank()) return null

        val request = Request.Builder()
            .url(baseUrl.trimEnd('/') + "/" + path.trimStart('/'))
            .addHeader("Content-Type", "application/json")
            .post(json.encodeToString(payload).toRequestBody(JSON_MEDIA_TYPE))
            .build()

        return runCatching {
            httpClient.newCall(request).execute().use { response ->
                if (!response.isSuccessful) return@use null
                val raw = response.body?.string().orEmpty()
                if (raw.isBlank()) return@use null
                json.decodeFromString<ResponseBody>(raw)
            }
        }.getOrNull()
    }

    @Serializable
    private data class NearbyDiscoveryRequest(
        val lat: Double,
        val lng: Double,
        @SerialName("radius_m") val radiusMeters: Int,
        val limit: Int,
        @SerialName("included_types") val includedTypes: List<String>,
        @SerialName("provider_hint") val providerHint: String,
        @SerialName("allow_fallback") val allowFallback: Boolean,
    )

    @Serializable
    private data class PlacesAutocompleteRequest(
        val query: String,
        @SerialName("provider_hint") val providerHint: String,
        @SerialName("allow_fallback") val allowFallback: Boolean,
    )

    @Serializable
    private data class PlacesDetailsRequest(
        @SerialName("place_ids") val placeIds: List<String>,
        @SerialName("provider_hint") val providerHint: String,
        @SerialName("allow_fallback") val allowFallback: Boolean,
    )

    @Serializable
    private data class NearbyDiscoveryResponse(
        @SerialName("provider_used") val providerUsed: String,
        @SerialName("fallback_used") val fallbackUsed: Boolean,
        val places: List<ProxyPlace>,
    )

    @Serializable
    private data class PlacesAutocompleteResponse(
        @SerialName("provider_used") val providerUsed: String,
        @SerialName("fallback_used") val fallbackUsed: Boolean,
        val suggestions: List<ProxySuggestion>,
    )

    @Serializable
    private data class PlacesDetailsResponse(
        @SerialName("provider_used") val providerUsed: String,
        @SerialName("fallback_used") val fallbackUsed: Boolean,
        val places: List<ProxyPlace>,
    )

    @Serializable
    private data class ProxyPlace(
        @SerialName("place_id") val placeId: String,
        @SerialName("display_name") val displayName: String,
        @SerialName("formatted_address") val formattedAddress: String? = null,
        val lat: Double,
        val lng: Double,
        @SerialName("place_types") val placeTypes: List<String> = emptyList(),
    )

    @Serializable
    private data class ProxySuggestion(
        @SerialName("place_id") val placeId: String,
        @SerialName("primary_text") val primaryText: String,
        @SerialName("secondary_text") val secondaryText: String = "",
        @SerialName("place_types") val placeTypes: List<String> = emptyList(),
    )

    private companion object {
        val JSON_MEDIA_TYPE = "application/json".toMediaType()
    }
}
