package app.blueprint.capture.data.capture

import com.google.common.truth.Truth.assertThat
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.junit.Test

class AndroidCaptureSourceSerializationTest {
    @Test
    fun `serializes android xr glasses capture source`() {
        val request = AndroidCaptureBundleRequest(
            sceneId = "scene-1",
            captureId = "capture-1",
            creatorId = "creator-1",
            deviceModel = "Android XR projected glasses",
            osVersion = "Android 16",
            fpsSource = 15.0,
            width = 1280,
            height = 720,
            captureStartEpochMs = 1_700_000_000_000,
            captureSource = AndroidCaptureSource.AndroidXrGlasses,
        )

        val encoded = Json.encodeToString(request)

        assertThat(encoded).contains("\"capture_source\":\"android_xr_glasses\"")
    }
}
