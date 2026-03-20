package app.blueprint.capture.data.capture

import com.google.common.truth.Truth.assertThat
import java.io.File
import kotlin.io.path.createTempDirectory
import kotlinx.serialization.json.Json
import org.junit.Test

class AndroidCaptureBundleBuilderTest {
    private val json = Json { ignoreUnknownKeys = true }

    @Test
    fun `bundle builder writes canonical android manifest and supplemental files`() {
        val tempDir = createTempDirectory("android-capture-bundle").toFile()
        val sourceVideo = File(tempDir, "walkthrough.mp4").apply {
            writeBytes(byteArrayOf(0x01, 0x02, 0x03))
        }
        val request = AndroidCaptureBundleRequest(
            sceneId = "scene-123",
            captureId = "capture-123",
            creatorId = "tester",
            deviceModel = "Pixel 9 Pro",
            osVersion = "Android 16",
            fpsSource = 30.0,
            width = 1920,
            height = 1080,
            captureStartEpochMs = 1_700_000_000_000,
            workflowName = "Inbound walk",
            taskSteps = listOf("Enter", "Sweep"),
            zone = "Aisle 4",
        )

        val result = AndroidCaptureBundleBuilder().writeBundle(
            outputRoot = tempDir,
            request = request,
            walkthroughSource = sourceVideo,
        )

        assertThat(result.manifestFile.exists()).isTrue()
        assertThat(result.contextFile.exists()).isTrue()
        assertThat(result.hypothesisFile.exists()).isTrue()
        assertThat(result.completionFile.exists()).isTrue()
        assertThat(result.provenanceFile.exists()).isTrue()
        assertThat(result.rightsConsentFile.exists()).isTrue()
        assertThat(result.videoTrackFile.exists()).isTrue()
        assertThat(result.hashesFile.exists()).isTrue()
        assertThat(File(result.rawDirectory, "walkthrough.mp4").exists()).isTrue()

        val manifest = json.decodeFromString<CaptureManifest>(result.manifestFile.readText())
        assertThat(manifest.schemaVersion).isEqualTo("v3")
        assertThat(manifest.captureId).isEqualTo("capture-123")
        assertThat(manifest.coordinateFrameSessionId).isEqualTo("capture-123")
        assertThat(manifest.captureSource).isEqualTo("android")
        assertThat(manifest.captureTierHint).isEqualTo("tier2_android")
        assertThat(manifest.captureModality).isEqualTo("android_video_only")
        assertThat(manifest.sceneMemoryCapture.sensorAvailability.arkitPoses).isFalse()
        assertThat(manifest.sceneMemoryCapture.sensorAvailability.motion).isTrue()

        val context = json.decodeFromString<CaptureContext>(result.contextFile.readText())
        assertThat(context.taskTextHint).isEqualTo("Inbound walk")
        assertThat(context.zone).isEqualTo("Aisle 4")

        val hypothesis = json.decodeFromString<TaskHypothesis>(result.hypothesisFile.readText())
        assertThat(hypothesis.source).isEqualTo(CaptureIntakeSource.Authoritative)
        assertThat(hypothesis.taskSteps).containsExactly("Enter", "Sweep").inOrder()

        val rightsConsent = json.decodeFromString<RightsConsentFile>(result.rightsConsentFile.readText())
        assertThat(rightsConsent.redactionRequired).isTrue()

        val hashes = json.decodeFromString<HashesFile>(result.hashesFile.readText())
        assertThat(hashes.artifacts).containsKey("manifest.json")
    }
}
