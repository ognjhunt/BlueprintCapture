package app.blueprint.capture.data.glasses

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class AndroidXrUxStateTest {
    @Test
    fun `disconnected state names audio and display glasses without implying hardware readiness`() {
        val state = AndroidXrUxState.from(
            isProjectedDeviceConnected = false,
            capabilities = AndroidXrProjectedPlatform.capabilities,
            hasCaptureTarget = false,
        )

        assertThat(state.mode).isEqualTo(AndroidXrUxMode.WaitingForDevice)
        assertThat(state.title).isEqualTo("Waiting for Android XR glasses")
        assertThat(state.body).contains("Pair audio glasses or display glasses")
        assertThat(state.capabilitySummary).containsExactly(
            "Display state unknown",
            "Projected camera unverified",
            "Projected mic unverified",
            "World tracking unverified",
        ).inOrder()
        assertThat(state.primaryAction).isEqualTo("Open Android XR readiness mode")
    }

    @Test
    fun `audio-only state names voice-led capture and lack of visual display`() {
        val state = AndroidXrUxState.from(
            isProjectedDeviceConnected = true,
            capabilities = GlassesCapabilities(
                hasDisplay = false,
                supportsProjectedCamera = true,
                supportsProjectedMic = true,
                supportsDevicePose = false,
                supportsGeospatial = false,
            ),
            hasCaptureTarget = true,
        )

        assertThat(state.mode).isEqualTo(AndroidXrUxMode.AudioOnlyGlasses)
        assertThat(state.title).isEqualTo("Audio-only Android XR glasses")
        assertThat(state.body).contains("voice-led")
        assertThat(state.body).contains("no projected visual UI")
        assertThat(state.capabilitySummary).containsExactly(
            "No visual display",
            "Projected camera",
            "Projected mic",
            "World tracking unverified",
        ).inOrder()
        assertThat(state.primaryAction).isEqualTo("Launch audio-guided XR capture")
    }

    @Test
    fun `display-glasses state names visual projected UI and display constraints`() {
        val state = AndroidXrUxState.from(
            isProjectedDeviceConnected = true,
            capabilities = GlassesCapabilities(
                hasDisplay = true,
                supportsProjectedCamera = true,
                supportsProjectedMic = true,
                supportsDevicePose = false,
                supportsGeospatial = false,
            ),
            hasCaptureTarget = true,
        )

        assertThat(state.mode).isEqualTo(AndroidXrUxMode.DisplayGlasses)
        assertThat(state.title).isEqualTo("Display-glasses Android XR")
        assertThat(state.body).contains("Visual projected UI")
        assertThat(state.body).contains("additive or transparent displays")
        assertThat(state.capabilitySummary).containsExactly(
            "Display UI available",
            "Projected camera",
            "Projected mic",
            "World tracking unverified",
        ).inOrder()
        assertThat(state.primaryAction).isEqualTo("Launch display XR capture")
    }

    @Test
    fun `projected capability bits do not become world tracking authority`() {
        val state = AndroidXrUxState.from(
            isProjectedDeviceConnected = true,
            capabilities = GlassesCapabilities(
                hasDisplay = true,
                supportsProjectedCamera = true,
                supportsProjectedMic = true,
                supportsDevicePose = true,
                supportsGeospatial = true,
            ),
            hasCaptureTarget = true,
        )

        assertThat(state.capabilitySummary).contains("World tracking unverified")
        assertThat(state.capabilitySummary).doesNotContain("World tracking available")
        assertThat(state.body).contains("do not prove world tracking")
    }
}
