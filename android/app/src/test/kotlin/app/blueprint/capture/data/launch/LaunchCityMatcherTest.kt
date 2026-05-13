package app.blueprint.capture.data.launch

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class LaunchCityMatcherTest {
    @Test
    fun `matches supported city with normalized state aliases`() {
        val supported = listOf(
            SupportedLaunchCity(
                city = "Durham",
                stateCode = "NC",
                displayName = "Durham, NC",
                citySlug = "durham-nc",
            ),
        )

        val match = LaunchCityMatcher.supportedCity(
            city = ResolvedLaunchCity(city = "durham", stateCode = "North Carolina", countryCode = "US"),
            supportedCities = supported,
        )

        assertThat(match?.citySlug).isEqualTo("durham-nc")
    }

    @Test
    fun `does not match city name without state match`() {
        val supported = listOf(
            SupportedLaunchCity(
                city = "Springfield",
                stateCode = "IL",
                displayName = "Springfield, IL",
                citySlug = "springfield-il",
            ),
        )

        val match = LaunchCityMatcher.supportedCity(
            city = ResolvedLaunchCity(city = "Springfield", stateCode = "MO", countryCode = "US"),
            supportedCities = supported,
        )

        assertThat(match).isNull()
    }
}
