package app.blueprint.capture.data.support

import android.net.Uri
import app.blueprint.capture.BuildConfig

object SupportLinks {
    val mainWebsiteUri: Uri = Uri.parse(BuildConfig.MAIN_WEBSITE_URL)
    val helpCenterUri: Uri = Uri.parse(BuildConfig.HELP_CENTER_URL)
    val bugReportUri: Uri = Uri.parse(BuildConfig.BUG_REPORT_URL)
    val termsOfServiceUri: Uri = Uri.parse(BuildConfig.TERMS_OF_SERVICE_URL)
    val privacyPolicyUri: Uri = Uri.parse(BuildConfig.PRIVACY_POLICY_URL)
    val capturePolicyUri: Uri = Uri.parse(BuildConfig.CAPTURE_POLICY_URL)
    val accountDeletionUri: Uri = Uri.parse(BuildConfig.ACCOUNT_DELETION_URL)
    val supportEmailAddress: String = BuildConfig.SUPPORT_EMAIL_ADDRESS

    fun supportMailToUri(subject: String): Uri = Uri.Builder()
        .scheme("mailto")
        .opaquePart(supportEmailAddress)
        .appendQueryParameter("subject", subject)
        .build()
}
