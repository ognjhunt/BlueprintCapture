package app.blueprint.capture.ui.screens

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class ScanLocationPermissionTest {

    @Test
    fun `loadLastKnownLocationSafely returns null and skips providers when permission is denied`() {
        var networkCalled = false
        var gpsCalled = false

        val location = loadLastKnownLocationSafely(
            hasStartupPermission = false,
            networkProvider = {
                networkCalled = true
                null
            },
            gpsProvider = {
                gpsCalled = true
                null
            },
        )

        assertThat(location).isNull()
        assertThat(networkCalled).isFalse()
        assertThat(gpsCalled).isFalse()
    }
}
