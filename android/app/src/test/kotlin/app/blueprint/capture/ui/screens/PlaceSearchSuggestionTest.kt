package app.blueprint.capture.ui.screens

import app.blueprint.capture.data.places.PlaceDetails
import app.blueprint.capture.data.places.PlacePrediction
import com.google.common.truth.Truth.assertThat
import org.junit.Test

class PlaceSearchSuggestionTest {
    @Test
    fun `maps backend prediction without marking it as an active capture job`() {
        val suggestion = PlacePrediction(
            placeId = "places/abc",
            primaryText = "Durham Food Hall",
            secondaryText = "Durham, NC",
            fullText = "Durham Food Hall, Durham, NC",
        ).toSearchLocationSuggestion()

        assertThat(suggestion.id).isEqualTo("places/abc")
        assertThat(suggestion.title).isEqualTo("Durham Food Hall")
        assertThat(suggestion.resultAddress).isEqualTo("Durham, NC")
        assertThat(suggestion.reviewAddress).isEqualTo("Durham Food Hall, Durham, NC")
        assertThat(suggestion.isRecent).isFalse()
    }

    @Test
    fun `maps place details into open capture launch metadata without site submission id`() {
        val launch = PlaceSearchSuggestion(
            id = "places/abc",
            title = "Durham Food Hall",
            resultAddress = "Durham, NC",
            reviewAddress = "Durham Food Hall, Durham, NC",
        ).toOpenCaptureLaunch(
            context = "Public-facing food hall with repeatable service paths.",
            details = PlaceDetails(
                placeId = "places/abc",
                name = "Durham Food Hall",
                addressFull = "530 Foster St, Durham, NC",
                lat = 35.997,
                lng = -78.901,
            ),
        )

        assertThat(launch.label).isEqualTo("Durham Food Hall")
        assertThat(launch.siteSubmissionId).isNull()
        assertThat(launch.placeId).isEqualTo("places/abc")
        assertThat(launch.siteIdSource).isEqualTo("open_capture")
        assertThat(launch.latitude).isEqualTo(35.997)
        assertThat(launch.longitude).isEqualTo(-78.901)
        assertThat(launch.addressText).isEqualTo("530 Foster St, Durham, NC")
    }
}
