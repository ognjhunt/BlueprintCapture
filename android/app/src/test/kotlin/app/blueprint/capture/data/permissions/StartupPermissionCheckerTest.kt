package app.blueprint.capture.data.permissions

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class StartupPermissionCheckerTest {

    @Test
    fun `hasRequiredStartupPermission returns true when location is granted`() {
        val checker = StartupPermissionChecker { permission ->
            permission == REQUIRED_STARTUP_PERMISSION
        }

        assertThat(checker.hasRequiredStartupPermission()).isTrue()
    }

    @Test
    fun `hasRequiredStartupPermission returns false when location is denied`() {
        val checker = StartupPermissionChecker { false }

        assertThat(checker.hasRequiredStartupPermission()).isFalse()
    }
}
