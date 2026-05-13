package app.blueprint.capture.ui.screens

import app.blueprint.capture.data.model.CaptureLaunch
import app.blueprint.capture.data.model.CapturePermissionTone
import app.blueprint.capture.data.model.ScanTarget

internal data class CapturePayoutDisplay(
    val metricText: String,
    val bannerTitle: String,
    val bannerBody: String,
    val hasQuotedPayout: Boolean,
)

internal fun capturePayoutDisplay(
    quotedPayoutCents: Int?,
    permissionTone: CapturePermissionTone,
): CapturePayoutDisplay {
    val explicitPayout = quotedPayoutCents
        ?.takeIf { it > 0 }
        ?.let(::formatCompactQuotedPayout)

    if (explicitPayout != null) {
        return CapturePayoutDisplay(
            metricText = explicitPayout,
            bannerTitle = "Quoted payout: $explicitPayout",
            bannerBody = "Shown because this capture has explicit payout data. Review still checks quality, rights, and scope before payout eligibility is finalized.",
            hasQuotedPayout = true,
        )
    }

    val title = when (permissionTone) {
        CapturePermissionTone.Approved -> "Review before payout"
        CapturePermissionTone.Review -> "Review-gated capture"
        CapturePermissionTone.Permission -> "Access check required"
        CapturePermissionTone.Blocked -> "Capture blocked"
    }
    val body = when (permissionTone) {
        CapturePermissionTone.Blocked ->
            "This location is restricted. Do not record or submit capture content here."
        CapturePermissionTone.Permission ->
            "No payout is quoted. Confirm lawful access first, then Blueprint reviews quality, rights, and scope before any downstream use."
        else ->
            "No payout is quoted. Blueprint reviews quality, rights, and capture scope before any downstream use or payout decision."
    }
    val metric = when (permissionTone) {
        CapturePermissionTone.Permission -> "Access check"
        CapturePermissionTone.Blocked -> "Blocked"
        else -> "Review gated"
    }

    return CapturePayoutDisplay(
        metricText = metric,
        bannerTitle = title,
        bannerBody = body,
        hasQuotedPayout = false,
    )
}

internal val CaptureLaunch.payoutDisplay: CapturePayoutDisplay
    get() = capturePayoutDisplay(quotedPayoutCents, permissionTone)

internal val ScanTarget.payoutDisplay: CapturePayoutDisplay
    get() = capturePayoutDisplay(quotedPayoutCents, permissionTone)

private fun formatCompactQuotedPayout(cents: Int): String {
    val dollars = cents / 100
    val remainder = cents % 100
    return if (remainder == 0) {
        "$$dollars"
    } else {
        "$$dollars.${remainder.toString().padStart(2, '0')}"
    }
}
