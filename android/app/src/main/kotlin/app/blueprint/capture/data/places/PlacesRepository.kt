package app.blueprint.capture.data.places

import android.content.Context
import android.location.Location
import app.blueprint.capture.BuildConfig
import app.blueprint.capture.data.capture.SiteGeoPoint
import app.blueprint.capture.data.capture.SiteIdentity
import com.google.android.libraries.places.api.Places
import com.google.android.libraries.places.api.model.AutocompleteSessionToken
import com.google.android.libraries.places.api.model.Place
import com.google.android.libraries.places.api.net.FetchPlaceRequest
import com.google.android.libraries.places.api.net.FindAutocompletePredictionsRequest
import com.google.android.libraries.places.api.net.PlacesClient
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.coroutines.resume
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import kotlinx.coroutines.suspendCancellableCoroutine

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

/**
 * Wraps the Google Places SDK for open-capture site resolution.
 * Mirrors iOS PlacesAutocompleteService + PlacesDetailsService.
 *
 * Initialize once via [initialize] (called from Application or MainActivity)
 * before calling any search methods.
 */
@Singleton
class PlacesRepository @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    private var client: PlacesClient? = null
    private var sessionToken: AutocompleteSessionToken = AutocompleteSessionToken.newInstance()
    private val httpClient = OkHttpClient()
    private val json = Json { ignoreUnknownKeys = true }

    fun initialize(apiKey: String) {
        if (apiKey.isBlank()) return
        if (!Places.isInitialized()) {
            Places.initializeWithNewPlacesApiEnabled(context, apiKey)
        }
        client = Places.createClient(context)
    }

    suspend fun searchNearby(
        location: Location,
        radiusMeters: Int = 4_000,
        maxResultCount: Int = 8,
    ): List<NearbyPlace> = withContext(Dispatchers.IO) {
        val apiKey = BuildConfig.GOOGLE_PLACES_API_KEY.takeIf { it.isNotBlank() } ?: return@withContext emptyList()
        val body = NearbySearchRequest(
            includedTypes = listOf(
                "store",
                "shopping_mall",
                "department_store",
                "supermarket",
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
            maxResultCount = maxResultCount,
            locationRestriction = LocationRestriction(
                circle = Circle(
                    center = LatLng(
                        latitude = location.latitude,
                        longitude = location.longitude,
                    ),
                    radius = radiusMeters,
                ),
            ),
            rankPreference = "DISTANCE",
        )

        val request = Request.Builder()
            .url("https://places.googleapis.com/v1/places:searchNearby")
            .addHeader(
                "X-Goog-FieldMask",
                "places.id,places.displayName,places.formattedAddress,places.location,places.types",
            )
            .addHeader("X-Goog-Api-Key", apiKey)
            .post(json.encodeToString(NearbySearchRequest.serializer(), body).toRequestBody(JSON_MEDIA_TYPE))
            .build()

        runCatching {
            httpClient.newCall(request).execute().use { response ->
                if (!response.isSuccessful) return@use emptyList()
                val raw = response.body?.string().orEmpty()
                val decoded = json.decodeFromString(NearbySearchResponse.serializer(), raw)
                decoded.places.orEmpty().mapNotNull { place ->
                    val id = place.id ?: return@mapNotNull null
                    val name = place.displayName?.text?.takeIf { it.isNotBlank() } ?: return@mapNotNull null
                    val lat = place.location?.latitude ?: return@mapNotNull null
                    val lng = place.location?.longitude ?: return@mapNotNull null
                    NearbyPlace(
                        placeId = id,
                        name = name,
                        address = place.formattedAddress.orEmpty(),
                        lat = lat,
                        lng = lng,
                        types = place.types.orEmpty(),
                    )
                }
            }
        }.getOrDefault(emptyList())
    }

    /** Returns autocomplete predictions for [query]. Reuses an in-progress session token. */
    suspend fun autocomplete(query: String): List<PlacePrediction> {
        val c = client ?: return emptyList()
        if (query.isBlank()) return emptyList()

        val request = FindAutocompletePredictionsRequest.builder()
            .setSessionToken(sessionToken)
            .setQuery(query)
            .build()

        return suspendCancellableCoroutine { cont ->
            c.findAutocompletePredictions(request)
                .addOnSuccessListener { response ->
                    val predictions = response.autocompletePredictions.map { p ->
                        PlacePrediction(
                            placeId = p.placeId,
                            primaryText = p.getPrimaryText(null).toString(),
                            secondaryText = p.getSecondaryText(null).toString(),
                            fullText = p.getFullText(null).toString(),
                        )
                    }
                    if (cont.isActive) cont.resume(predictions)
                }
                .addOnFailureListener { e ->
                    if (cont.isActive) cont.resume(emptyList())
                }
        }
    }

    /**
     * Fetches full place details for a [placeId] chosen from autocomplete.
     * Rotates the session token afterward to avoid billing the same session twice.
     */
    suspend fun fetchDetails(placeId: String): PlaceDetails? {
        val c = client ?: return null

        val fields = listOf(
            Place.Field.ID,
            Place.Field.DISPLAY_NAME,
            Place.Field.FORMATTED_ADDRESS,
            Place.Field.LOCATION,
        )
        val request = FetchPlaceRequest.newInstance(placeId, fields)

        return suspendCancellableCoroutine { cont ->
            c.fetchPlace(request)
                .addOnSuccessListener { response ->
                    val place = response.place
                    val latlng = place.location
                    if (cont.isActive) {
                        cont.resume(
                            PlaceDetails(
                                placeId = place.id ?: placeId,
                                name = place.displayName,
                                addressFull = place.formattedAddress,
                                lat = latlng?.latitude,
                                lng = latlng?.longitude,
                            )
                        )
                    }
                }
                .addOnFailureListener { _ ->
                    if (cont.isActive) cont.resume(null)
                }
            // Rotate token after place selection to close the billing session
            sessionToken = AutocompleteSessionToken.newInstance()
        }
    }

    /**
     * Converts a [PlaceDetails] into a [SiteIdentity] suitable for an open capture bundle.
     */
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

    @Serializable
    private data class NearbySearchRequest(
        val includedTypes: List<String>,
        val maxResultCount: Int,
        val locationRestriction: LocationRestriction,
        val rankPreference: String,
    )

    @Serializable
    private data class LocationRestriction(
        val circle: Circle,
    )

    @Serializable
    private data class Circle(
        val center: LatLng,
        val radius: Int,
    )

    @Serializable
    private data class LatLng(
        val latitude: Double,
        val longitude: Double,
    )

    @Serializable
    private data class NearbySearchResponse(
        val places: List<NearbySearchPlace>? = null,
    )

    @Serializable
    private data class NearbySearchPlace(
        val id: String? = null,
        val displayName: DisplayName? = null,
        val formattedAddress: String? = null,
        val location: LatLng? = null,
        val types: List<String>? = null,
    )

    @Serializable
    private data class DisplayName(
        @SerialName("text") val text: String? = null,
    )

    private companion object {
        val JSON_MEDIA_TYPE = "application/json".toMediaType()
    }
}
