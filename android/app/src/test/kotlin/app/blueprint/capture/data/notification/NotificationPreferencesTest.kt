package app.blueprint.capture.data.notification

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class NotificationPreferencesTest {

    @Test
    fun `with toggles only the requested preference`() {
        val preferences = NotificationPreferences()

        val updated = preferences.with(NotificationPreferenceKey.Payouts, enabled = false)

        assertThat(updated.payouts).isFalse()
        assertThat(updated.nearbyJobs).isTrue()
        assertThat(updated.reservations).isTrue()
        assertThat(updated.captureStatus).isTrue()
        assertThat(updated.account).isTrue()
    }
}
