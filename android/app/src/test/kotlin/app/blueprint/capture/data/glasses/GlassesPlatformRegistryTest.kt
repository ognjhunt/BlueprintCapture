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
    fun `android xr platform advertises projected capabilities`() {
        val platform = GlassesPlatformRegistry.get(GlassesPlatformId.AndroidXrProjected)
        assertThat(platform.capabilities.supportsProjectedCamera).isTrue()
        assertThat(platform.capabilities.supportsProjectedMic).isTrue()
        assertThat(platform.capabilities.supportsDevicePose).isTrue()
        assertThat(platform.capabilities.supportsGeospatial).isTrue()
    }
}
