package app.blueprint.capture.data.auth

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class FirebaseAuthErrorFormatterTest {

    @Test
    fun `operation not allowed explains anonymous auth is disabled`() {
        assertThat(
            FirebaseAuthErrorFormatter.describeAnonymousSignInFailure(
                errorCode = "ERROR_OPERATION_NOT_ALLOWED",
                fallbackMessage = "Operation is not allowed",
            ),
        )
            .isEqualTo("Firebase Anonymous Auth is disabled for this project.")
    }

    @Test
    fun `network errors mention Firebase reachability`() {
        assertThat(
            FirebaseAuthErrorFormatter.describeAnonymousSignInFailure(
                errorCode = null,
                isNetworkError = true,
                fallbackMessage = "Network unavailable",
            ),
        )
            .isEqualTo("Firebase anonymous sign-in failed because the device could not reach Firebase.")
    }
}
