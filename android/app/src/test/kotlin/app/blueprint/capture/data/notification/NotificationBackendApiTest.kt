package app.blueprint.capture.data.notification

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class NotificationBackendApiTest {

    @Test
    fun `missing base url explains build config problem`() {
        assertThat(NotificationBackendApi.ApiError.MissingBaseUrl.message)
            .isEqualTo("BLUEPRINT_BACKEND_BASE_URL is not configured for this build.")
    }

    @Test
    fun `invalid response explains concrete status code`() {
        assertThat(NotificationBackendApi.ApiError.InvalidResponse(503).message)
            .isEqualTo("The backend returned HTTP 503.")
    }

    @Test
    fun `non http response explains invalid response`() {
        assertThat(NotificationBackendApi.ApiError.InvalidResponse(-1).message)
            .isEqualTo("The backend returned an invalid non-HTTP response.")
    }
}
