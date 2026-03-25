package app.blueprint.capture.ui.screens

import app.blueprint.capture.data.model.CapturePermissionTone
import app.blueprint.capture.data.model.ScanTarget
import org.junit.Assert.assertEquals
import org.junit.Test

class ScanOpenCaptureParityTest {

    @Test
    fun mergeTargetsWithOpenCapturePrependsOpenCaptureItem() {
        val openCapture = target(ScanViewModel.ALPHA_CURRENT_LOCATION_ID)
        val marketplace = listOf(target("job-1"), target("job-2"))

        val merged = mergeTargetsWithOpenCapture(
            rawTargets = marketplace,
            openCaptureTarget = openCapture,
        )

        assertEquals(
            listOf(ScanViewModel.ALPHA_CURRENT_LOCATION_ID, "job-1", "job-2"),
            merged.map { it.id },
        )
    }

    @Test
    fun mergeTargetsWithOpenCaptureLeavesMarketplaceFeedUntouchedWhenDisabled() {
        val marketplace = listOf(target("job-1"), target("job-2"))

        val merged = mergeTargetsWithOpenCapture(
            rawTargets = marketplace,
            openCaptureTarget = null,
        )

        assertEquals(listOf("job-1", "job-2"), merged.map { it.id })
    }

    private fun target(id: String): ScanTarget = ScanTarget(
        id = id,
        title = id,
        subtitle = "123 Main St",
        payoutText = "$10",
        distanceText = "Here now",
        readyNow = true,
        addressText = "123 Main St",
        categoryLabel = "TEST",
        estimatedMinutes = 10,
        permissionTone = CapturePermissionTone.Review,
        detailChecklist = emptyList(),
        requestedOutputs = listOf("qualification"),
    )
}
