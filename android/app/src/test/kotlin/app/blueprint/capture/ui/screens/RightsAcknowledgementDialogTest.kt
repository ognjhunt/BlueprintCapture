package app.blueprint.capture.ui.screens

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RightsAcknowledgementDialogTest {

    @Test
    fun copyPreservesAdvisoryReviewGate() {
        val copy = RightsAcknowledgementDialogCopy
        val combined = listOf(copy.title, copy.body, copy.confirmButton, copy.dismissButton)
            .joinToString(" ")

        assertEquals("Review capture rights", copy.title)
        assertEquals("I Confirm", copy.confirmButton)
        assertEquals("Cancel", copy.dismissButton)
        assertTrue(combined.contains("permission to capture this space"))
        assertTrue(combined.contains("qualification, privacy, and rights checks may still block downstream use"))
    }

    @Test
    fun copyDoesNotImplyPayoutProviderOrReadiness() {
        val combined = listOf(
            RightsAcknowledgementDialogCopy.title,
            RightsAcknowledgementDialogCopy.body,
            RightsAcknowledgementDialogCopy.confirmButton,
            RightsAcknowledgementDialogCopy.dismissButton,
        ).joinToString(" ")

        assertFalse(combined.contains("payout", ignoreCase = true))
        assertFalse(combined.contains("provider", ignoreCase = true))
        assertFalse(combined.contains("ready", ignoreCase = true))
        assertFalse(combined.contains("approved", ignoreCase = true))
    }
}
