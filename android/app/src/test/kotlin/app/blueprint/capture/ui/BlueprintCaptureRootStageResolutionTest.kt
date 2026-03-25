package app.blueprint.capture.ui

import app.blueprint.capture.data.model.RootStage
import com.google.common.truth.Truth.assertThat
import org.junit.Test

class BlueprintCaptureRootStageResolutionTest {

    @Test
    fun `resolveRootStage returns permissions when persisted flag is true but location is denied`() {
        val stage = resolveRootStage(
            onboardingComplete = true,
            hasRegisteredUser = true,
            authSkipped = false,
            inviteCodeComplete = true,
            permissionsComplete = true,
            hasStartupPermissions = false,
            walkthroughComplete = false,
            glassesSetupComplete = false,
        )

        assertThat(stage).isEqualTo(RootStage.Permissions)
    }
}
