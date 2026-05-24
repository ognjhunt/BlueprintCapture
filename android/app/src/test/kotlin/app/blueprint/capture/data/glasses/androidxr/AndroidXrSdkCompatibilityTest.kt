package app.blueprint.capture.data.glasses.androidxr

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class AndroidXrSdkCompatibilityTest {
    @Test
    fun `runtime and arcore dp4 artifacts are safe for current compile floor`() {
        val artifacts = AndroidXrSdkCompatibility.safeDp4Artifacts(
            compileSdk = 36,
            agpVersion = "8.9.1",
        )

        assertThat(artifacts.map { it.coordinate }).containsExactly(
            "androidx.xr.runtime:runtime:1.0.0-alpha14",
            "androidx.xr.arcore:arcore:1.0.0-alpha14",
        )
    }

    @Test
    fun `projected test rule is blocked by current compile sdk and agp floor`() {
        val readiness = AndroidXrSdkCompatibility.projectedTestRuleReadiness(
            compileSdk = 36,
            agpVersion = "8.9.1",
        )

        assertThat(readiness.usable).isFalse()
        assertThat(readiness.coordinate).isEqualTo("androidx.xr.projected:projected-testing:1.0.0-alpha08")
        assertThat(readiness.blocker).contains("compileSdk 37")
        assertThat(readiness.blocker).contains("AGP 9.2.0")
    }

    @Test
    fun `projected test rule becomes usable after the documented tooling floor`() {
        val readiness = AndroidXrSdkCompatibility.projectedTestRuleReadiness(
            compileSdk = 37,
            agpVersion = "9.2.0",
        )

        assertThat(readiness.usable).isTrue()
        assertThat(readiness.blocker).isNull()
    }
}
