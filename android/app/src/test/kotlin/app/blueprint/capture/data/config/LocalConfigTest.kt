package app.blueprint.capture.data.config

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class LocalConfigTest {
    @Test
    fun backendAndStripeKeyDoNotMakePayoutProviderReady() {
        val config = LocalConfig(
            backendBaseUrl = "https://alpha.example.com",
            demandBackendBaseUrl = "https://alpha.example.com",
            allowMockJobsFallback = false,
            enableOpenCaptureHere = true,
            stripePublishableKey = "pk_test_contract",
            payoutProvider = "stripe",
            payoutProviderReady = false,
            nearbyDiscoveryProvider = NearbyDiscoveryProvider.PlacesNearby,
            enableGeminiMapsGroundingFallback = false,
        )

        assertThat(config.hasBackend).isTrue()
        assertThat(config.hasStripe).isTrue()
        assertThat(config.hasPayoutProviderReady).isFalse()
    }

    @Test
    fun payoutProviderReadyRequiresBackendAndExplicitProviderProofFlag() {
        val config = LocalConfig(
            backendBaseUrl = "https://alpha.example.com",
            demandBackendBaseUrl = "",
            allowMockJobsFallback = false,
            enableOpenCaptureHere = true,
            stripePublishableKey = "",
            payoutProvider = "stripe",
            payoutProviderReady = true,
            nearbyDiscoveryProvider = NearbyDiscoveryProvider.PlacesNearby,
            enableGeminiMapsGroundingFallback = false,
        )

        assertThat(config.hasPayoutProviderReady).isTrue()
    }
}
