package app.blueprint.capture.data.model

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class CaptureRequestedOutputsTest {

    @Test
    fun `normalizes legacy evaluation outputs into robot eval request outputs`() {
        val outputs = CaptureRequestedOutputs.normalize(
            listOf("qualification", "preview_simulation", "deeper_evaluation"),
        )

        assertThat(outputs).containsExactly(
            "qualification",
            "preview_simulation",
            "deeper_evaluation",
            "robot_eval_dataset",
            "task_evaluation_run",
        ).inOrder()
    }

    @Test
    fun `leaves review intake outputs review gated`() {
        val outputs = CaptureRequestedOutputs.normalize(CaptureRequestedOutputs.ReviewIntake)

        assertThat(outputs).containsExactly("qualification", "review_intake").inOrder()
    }
}
