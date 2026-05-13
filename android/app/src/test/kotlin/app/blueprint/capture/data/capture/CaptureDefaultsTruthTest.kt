package app.blueprint.capture.data.capture

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class CaptureDefaultsTruthTest {
    @Test
    fun `default capture capability objects do not claim motion or downstream geometry`() {
        val capabilities = CaptureCapabilities()
        val evidence = CaptureEvidence()
        val sceneMemory = SceneMemoryCapture()

        assertThat(capabilities.motion).isFalse()
        assertThat(capabilities.motionAuthoritative).isFalse()
        assertThat(capabilities.motionAuthority).isEqualTo(CaptureAuthority.NotAvailable)
        assertThat(capabilities.geometryExpectedDownstream).isFalse()

        assertThat(evidence.motionSamples).isEqualTo(0)
        assertThat(evidence.motionAuthority).isEqualTo(CaptureAuthority.NotAvailable)
        assertThat(evidence.geometryExpectedDownstream).isFalse()

        assertThat(sceneMemory.sensorAvailability.motion).isFalse()
        assertThat(sceneMemory.geometryExpectedDownstream).isFalse()
    }
}
