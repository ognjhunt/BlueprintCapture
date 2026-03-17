package app.blueprint.capture.data.config

import app.blueprint.capture.BuildConfig
import javax.inject.Inject
import javax.inject.Singleton

data class LocalConfig(
    val backendBaseUrl: String,
    val stripePublishableKey: String,
    val googlePlacesApiKey: String,
    val geminiApiKey: String,
) {
    val hasBackend: Boolean = backendBaseUrl.isNotBlank()
    val hasPlaces: Boolean = googlePlacesApiKey.isNotBlank()
    val hasStripe: Boolean = stripePublishableKey.isNotBlank()
}

@Singleton
class LocalConfigProvider @Inject constructor() {
    fun current(): LocalConfig = LocalConfig(
        backendBaseUrl = BuildConfig.BACKEND_BASE_URL,
        stripePublishableKey = BuildConfig.STRIPE_PUBLISHABLE_KEY,
        googlePlacesApiKey = BuildConfig.GOOGLE_PLACES_API_KEY,
        geminiApiKey = BuildConfig.GEMINI_API_KEY,
    )
}
