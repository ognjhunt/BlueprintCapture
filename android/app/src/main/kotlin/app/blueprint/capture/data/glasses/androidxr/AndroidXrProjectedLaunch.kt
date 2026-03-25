package app.blueprint.capture.data.glasses.androidxr

import android.content.Context
import android.content.Intent
import app.blueprint.capture.GlassesProjectedActivity
import app.blueprint.capture.data.model.CaptureLaunch

object AndroidXrProjectedLaunch {
    private const val EXTRA_LABEL = "xr_capture_label"
    private const val EXTRA_CATEGORY = "xr_capture_category"
    private const val EXTRA_ADDRESS = "xr_capture_address"
    private const val EXTRA_WORKFLOW = "xr_capture_workflow"
    private const val EXTRA_TARGET_ID = "xr_capture_target_id"
    private const val EXTRA_JOB_ID = "xr_capture_job_id"
    private const val EXTRA_SITE_SUBMISSION_ID = "xr_capture_site_submission_id"
    private const val EXTRA_ZONE = "xr_capture_zone"
    private const val EXTRA_OWNER = "xr_capture_owner"
    private const val EXTRA_RIGHTS_PROFILE = "xr_capture_rights_profile"
    private const val EXTRA_QUOTED_PAYOUT_CENTS = "xr_capture_quoted_payout_cents"
    private const val EXTRA_REQUESTED_OUTPUTS = "xr_capture_requested_outputs"
    private const val EXTRA_WORKFLOW_STEPS = "xr_capture_workflow_steps"

    fun intent(context: Context, captureLaunch: CaptureLaunch?): Intent {
        val intent = Intent(context, GlassesProjectedActivity::class.java)
        captureLaunch ?: return intent
        return intent.apply {
            putExtra(EXTRA_LABEL, captureLaunch.label)
            putExtra(EXTRA_CATEGORY, captureLaunch.categoryLabel)
            putExtra(EXTRA_ADDRESS, captureLaunch.addressText)
            putExtra(EXTRA_WORKFLOW, captureLaunch.workflowName)
            putExtra(EXTRA_TARGET_ID, captureLaunch.targetId)
            putExtra(EXTRA_JOB_ID, captureLaunch.jobId)
            putExtra(EXTRA_SITE_SUBMISSION_ID, captureLaunch.siteSubmissionId)
            putExtra(EXTRA_ZONE, captureLaunch.zone)
            putExtra(EXTRA_OWNER, captureLaunch.owner)
            putExtra(EXTRA_RIGHTS_PROFILE, captureLaunch.rightsProfile)
            putExtra(EXTRA_QUOTED_PAYOUT_CENTS, captureLaunch.quotedPayoutCents ?: -1)
            putStringArrayListExtra(EXTRA_REQUESTED_OUTPUTS, ArrayList(captureLaunch.requestedOutputs))
            putStringArrayListExtra(EXTRA_WORKFLOW_STEPS, ArrayList(captureLaunch.workflowSteps))
        }
    }

    fun parse(intent: Intent): CaptureLaunch? {
        val label = intent.getStringExtra(EXTRA_LABEL) ?: return null
        return CaptureLaunch(
            label = label,
            categoryLabel = intent.getStringExtra(EXTRA_CATEGORY),
            addressText = intent.getStringExtra(EXTRA_ADDRESS),
            targetId = intent.getStringExtra(EXTRA_TARGET_ID),
            jobId = intent.getStringExtra(EXTRA_JOB_ID),
            siteSubmissionId = intent.getStringExtra(EXTRA_SITE_SUBMISSION_ID),
            workflowName = intent.getStringExtra(EXTRA_WORKFLOW),
            workflowSteps = intent.getStringArrayListExtra(EXTRA_WORKFLOW_STEPS).orEmpty(),
            zone = intent.getStringExtra(EXTRA_ZONE),
            owner = intent.getStringExtra(EXTRA_OWNER),
            requestedOutputs = intent.getStringArrayListExtra(EXTRA_REQUESTED_OUTPUTS).orEmpty()
                .ifEmpty { listOf("qualification", "review_intake") },
            quotedPayoutCents = intent.getIntExtra(EXTRA_QUOTED_PAYOUT_CENTS, -1).takeIf { it >= 0 },
            rightsProfile = intent.getStringExtra(EXTRA_RIGHTS_PROFILE),
        )
    }
}
