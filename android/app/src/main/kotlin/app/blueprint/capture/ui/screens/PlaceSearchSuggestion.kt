package app.blueprint.capture.ui.screens

import app.blueprint.capture.data.capture.SiteGeoPoint
import app.blueprint.capture.data.model.CaptureLaunch
import app.blueprint.capture.data.model.CapturePermissionTone
import app.blueprint.capture.data.places.PlaceDetails
import app.blueprint.capture.data.places.PlacePrediction
import java.util.Locale

data class PlaceSearchSuggestion(
    val id: String,
    val title: String,
    val resultAddress: String,
    val reviewAddress: String,
    val isRecent: Boolean = false,
    val isManualEntry: Boolean = false,
)

fun PlacePrediction.toSearchLocationSuggestion(): PlaceSearchSuggestion =
    PlaceSearchSuggestion(
        id = placeId,
        title = primaryText.ifBlank { fullText },
        resultAddress = secondaryText.ifBlank { fullText },
        reviewAddress = fullText.ifBlank {
            listOf(primaryText, secondaryText)
                .filter(String::isNotBlank)
                .joinToString(", ")
        },
    )

fun manualSearchLocationSuggestion(query: String): PlaceSearchSuggestion? {
    val cleaned = query.trim()
    if (cleaned.length < 4) return null
    return PlaceSearchSuggestion(
        id = "manual-" + cleaned.lowercase(Locale.US)
            .replace(Regex("[^a-z0-9]+"), "-")
            .trim('-')
            .ifBlank { "space" },
        title = cleaned,
        resultAddress = "User-entered location",
        reviewAddress = cleaned,
        isManualEntry = true,
    )
}

fun PlaceSearchSuggestion.toOpenCaptureLaunch(
    context: String,
    details: PlaceDetails?,
): CaptureLaunch {
    val workflowContext = context.trim().ifBlank {
        "Capture the public-facing approach, main circulation path, and repeated high-value zones."
    }
    val resolvedName = details?.name?.takeIf(String::isNotBlank) ?: title
    val resolvedAddress = details?.addressFull?.takeIf(String::isNotBlank) ?: reviewAddress
    val siteId = details?.placeId?.takeIf(String::isNotBlank)
        ?: id.takeUnless { isManualEntry }

    return CaptureLaunch(
        label = resolvedName,
        categoryLabel = "SPACE REVIEW",
        addressText = resolvedAddress,
        permissionTone = CapturePermissionTone.Review,
        workflowName = "Space review",
        workflowSteps = listOf(workflowContext),
        detailChecklist = defaultSubmissionChecklist,
        requestedOutputs = listOf("qualification", "review_intake"),
        placeId = siteId,
        siteIdSource = "open_capture",
        latitude = details?.lat,
        longitude = details?.lng,
    )
}

fun PlaceDetails.toSiteGeoPoint(): SiteGeoPoint? =
    if (lat != null && lng != null) SiteGeoPoint(latitude = lat, longitude = lng) else null
