package app.blueprint.capture.data.capture

import com.google.common.truth.Truth.assertThat
import java.io.File
import kotlin.io.path.createTempDirectory
import org.junit.Test

class CaptureUploadContractTest {
    @Test
    fun `buildRemotePrefix uses canonical scene capture prefix`() {
        val remotePrefix = CaptureUploadContract.buildRemotePrefix(
            sceneId = "Scene 123",
            captureId = "Capture 456",
        )

        assertThat(remotePrefix).isEqualTo("scenes/scene-123/captures/capture-456/")
        assertThat(CaptureUploadContract.registrationRawPrefix(remotePrefix))
            .isEqualTo("scenes/scene-123/captures/capture-456/raw/")
    }

    @Test
    fun `planBundleFiles uploads completion marker last`() {
        val bundleRoot = createTempDirectory("android-upload-contract").toFile()
        val rawDir = File(bundleRoot, "raw").apply { mkdirs() }
        val nestedDir = File(rawDir, "glasses").apply { mkdirs() }
        val manifest = File(rawDir, "manifest.json").apply { writeText("{}") }
        val video = File(rawDir, "walkthrough.mp4").apply { writeBytes(byteArrayOf(1)) }
        val streamMetadata = File(nestedDir, "stream_metadata.json").apply { writeText("{}") }
        val completion = File(rawDir, "capture_upload_complete.json").apply { writeText("{}") }

        val plan = CaptureUploadContract.planBundleFiles(bundleRoot)

        assertThat(plan.payloadFiles).containsExactly(streamMetadata, manifest, video).inOrder()
        assertThat(plan.completionMarker).isEqualTo(completion)
        assertThat(plan.uploadOrder.last()).isEqualTo(completion)
        assertThat(plan.uploadOrder.map { it.relativeTo(bundleRoot).invariantSeparatorsPath })
            .containsExactly(
                "raw/glasses/stream_metadata.json",
                "raw/manifest.json",
                "raw/walkthrough.mp4",
                "raw/capture_upload_complete.json",
            )
            .inOrder()
    }
}
