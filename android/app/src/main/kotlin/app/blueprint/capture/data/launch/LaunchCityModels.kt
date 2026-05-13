package app.blueprint.capture.data.launch

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

data class ResolvedLaunchCity(
    val city: String,
    val stateCode: String?,
    val countryCode: String?,
) {
    val displayName: String
        get() = listOf(city, stateCode ?: countryCode)
            .filter { !it.isNullOrBlank() }
            .joinToString(", ")
}

@Serializable
data class SupportedLaunchCity(
    val city: String,
    @SerialName("stateCode") val stateCode: String,
    @SerialName("displayName") val displayName: String,
    @SerialName("citySlug") val citySlug: String,
)

@Serializable
data class CurrentLaunchCity(
    val city: String,
    @SerialName("stateCode") val stateCode: String? = null,
    @SerialName("displayName") val displayName: String,
    @SerialName("citySlug") val citySlug: String? = null,
    @SerialName("isSupported") val isSupported: Boolean,
)

@Serializable
data class CreatorLaunchStatusResponse(
    @SerialName("supportedCities") val supportedCities: List<SupportedLaunchCity> = emptyList(),
    @SerialName("currentCity") val currentCity: CurrentLaunchCity? = null,
)

object LaunchCityMatcher {
    fun supportedCity(
        city: ResolvedLaunchCity,
        supportedCities: List<SupportedLaunchCity>,
    ): SupportedLaunchCity? {
        val normalizedCity = normalizeToken(city.city)
        val normalizedState = normalizeStateToken(city.stateCode)
        return supportedCities.firstOrNull { supported ->
            normalizeToken(supported.city) == normalizedCity &&
                normalizeStateToken(supported.stateCode) == normalizedState
        }
    }

    private fun normalizeToken(value: String?): String =
        value.orEmpty()
            .trim()
            .lowercase()
            .replace(Regex("[^a-z0-9]+"), " ")
            .trim()

    private fun normalizeStateToken(value: String?): String = when (normalizeToken(value)) {
        "california" -> "ca"
        "north carolina" -> "nc"
        "texas" -> "tx"
        else -> normalizeToken(value)
    }
}
