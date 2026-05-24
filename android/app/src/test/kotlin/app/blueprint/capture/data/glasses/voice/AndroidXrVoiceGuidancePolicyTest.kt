package app.blueprint.capture.data.glasses.voice

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class AndroidXrVoiceGuidancePolicyTest {
    @Test
    fun `android xr voice guidance keeps gemini live disabled until a real live connector exists`() {
        val policy = AndroidXrVoiceGuidancePolicy.default()

        assertThat(policy.preferGeminiLive).isFalse()
        assertThat(policy.geminiLiveConnector).isInstanceOf(UnavailableGeminiLiveConnector::class.java)
        assertThat(policy.statusMessage).contains("Gemini Live")
        assertThat(policy.statusMessage).contains("on-device speech")
    }
}
