package app.blueprint.capture.ui.screens

import app.blueprint.capture.data.model.CapturePermissionTone
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CapturePayoutDisplayTest {

    @Test
    fun nilPayoutShowsReviewFirstCopyWithoutAmountOrTiming() {
        val display = capturePayoutDisplay(
            quotedPayoutCents = null,
            permissionTone = CapturePermissionTone.Review,
        )
        val copy = display.copyText()

        assertFalse(display.hasQuotedPayout)
        assertEquals("Review gated", display.metricText)
        assertFalse(copy.contains("$"))
        assertFalse(copy.contains("earn", ignoreCase = true))
        assertFalse(copy.contains("usually", ignoreCase = true))
        assertFalse(copy.contains("day", ignoreCase = true))
    }

    @Test
    fun quotedPayoutDisplaysAmountWithoutTimingClaim() {
        val display = capturePayoutDisplay(
            quotedPayoutCents = 4_200,
            permissionTone = CapturePermissionTone.Approved,
        )
        val copy = display.copyText()

        assertTrue(display.hasQuotedPayout)
        assertEquals("$42", display.metricText)
        assertTrue(copy.contains("$42"))
        assertFalse(copy.contains("usually", ignoreCase = true))
        assertFalse(copy.contains("3-5", ignoreCase = true))
        assertFalse(copy.contains("48"))
    }

    @Test
    fun reviewGatedOpenCaptureDoesNotImplyEarningOrReadiness() {
        val display = capturePayoutDisplay(
            quotedPayoutCents = 0,
            permissionTone = CapturePermissionTone.Review,
        )
        val copy = display.copyText()

        assertFalse(display.hasQuotedPayout)
        assertEquals("Review-gated capture", display.bannerTitle)
        assertFalse(copy.contains("$"))
        assertFalse(copy.contains("earn", ignoreCase = true))
        assertFalse(copy.contains("ready", ignoreCase = true))
    }
}

private fun CapturePayoutDisplay.copyText(): String =
    listOf(metricText, bannerTitle, bannerBody).joinToString(" ")
