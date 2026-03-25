package app.blueprint.capture.data.glasses

import com.google.common.truth.Truth.assertThat
import java.io.File
import kotlin.io.path.createTempDirectory
import org.junit.Test

class GlassesCaptureManagerTest {
    @Test
    fun `canonical glasses evidence writes required sidecars and explicit unavailable signals`() {
        val tempDir = createTempDirectory("glasses-evidence").toFile()

        val directories = GlassesCaptureManager.writeCanonicalEvidence(
            outputDir = tempDir,
            captureStartMs = 1_700_000_000_000,
            framePresentationTimesUs = listOf(1_000_000L, 1_033_333L),
            streamWidth = 1280,
            streamHeight = 720,
            streamFps = 30.0,
        )

        assertThat(directories.glassesDirectory.exists()).isTrue()
        assertThat(directories.companionPhoneDirectory).isNull()

        val frameTimestampLines = File(directories.glassesDirectory, "frame_timestamps.jsonl").readLines()
        assertThat(frameTimestampLines).hasSize(2)
        assertThat(frameTimestampLines.first()).contains("\"frame_id\":\"000001\"")
        assertThat(frameTimestampLines.last()).contains("\"t_capture_sec\":0.033333")

        val deviceState = File(directories.glassesDirectory, "device_state.jsonl").readText()
        val healthEvents = File(directories.glassesDirectory, "health_events.jsonl").readText()
        assertThat(deviceState).contains("unavailable_in_public_sdk")
        assertThat(healthEvents).contains("public_sdk_not_exposed")

        val streamMetadata = File(directories.glassesDirectory, "stream_metadata.json").readText()
        assertThat(streamMetadata).contains("\"first_party_geometry_available\": false")
        assertThat(streamMetadata).contains("\"companion_phone_pose_available\": false")
        assertThat(streamMetadata).contains("\"stream_frame_rate\": 30")
    }
}
