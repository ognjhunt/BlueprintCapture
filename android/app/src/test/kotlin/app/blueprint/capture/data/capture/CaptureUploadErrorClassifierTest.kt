package app.blueprint.capture.data.capture

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class CaptureUploadErrorClassifierTest {

    @Test
    fun `classifier matches already finalized message`() {
        val error = IllegalStateException("Upload has already been finalized.")

        assertThat(CaptureUploadErrorClassifier.isAlreadyFinalized(error)).isTrue()
    }

    @Test
    fun `classifier matches underlying cause message`() {
        val error = IllegalStateException(
            "Upload failed",
            IllegalStateException("Upload has already been finalized."),
        )

        assertThat(CaptureUploadErrorClassifier.isAlreadyFinalized(error)).isTrue()
    }

    @Test
    fun `classifier ignores unrelated messages`() {
        val error = IllegalStateException("Missing or insufficient permissions.")

        assertThat(CaptureUploadErrorClassifier.isAlreadyFinalized(error)).isFalse()
    }
}
