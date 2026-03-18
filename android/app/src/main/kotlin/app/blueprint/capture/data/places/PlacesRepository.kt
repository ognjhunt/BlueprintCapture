package app.blueprint.capture.data.places

import android.content.Context
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
import kotlin.coroutines.resumeWithException
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

    fun initialize(apiKey: String) {
        if (apiKey.isBlank()) return
        if (!Places.isInitialized()) {
            Places.initializeWithNewPlacesApiEnabled(context, apiKey)
        }
        client = Places.createClient(context)
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
}
