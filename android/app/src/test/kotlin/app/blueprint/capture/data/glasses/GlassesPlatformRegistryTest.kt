package app.blueprint.capture.data.glasses

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class GlassesPlatformRegistryTest {
    @Test
    fun `registry exposes android xr and meta providers`() {
        assertThat(GlassesPlatformRegistry.all.map { it.id }).containsExactly(
            GlassesPlatformId.AndroidXrProjected,
            GlassesPlatformId.MetaDat,
        ).inOrder()
    }

    @Test
    fun `android xr platform advertises projected camera and mic without world-tracking claims`() {
        val platform = GlassesPlatformRegistry.get(GlassesPlatformId.AndroidXrProjected)
        assertThat(platform.capabilities.supportsProjectedCamera).isTrue()
        assertThat(platform.capabilities.supportsProjectedMic).isTrue()
        assertThat(platform.capabilities.supportsDevicePose).isFalse()
        assertThat(platform.capabilities.supportsGeospatial).isFalse()
    }
}
