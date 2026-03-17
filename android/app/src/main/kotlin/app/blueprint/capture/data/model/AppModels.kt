package app.blueprint.capture.data.model

import kotlinx.serialization.Serializable

enum class RootStage {
    Onboarding,
    Auth,
    App,
}

enum class MainTab {
    Scan,
    Wallet,
    Profile,
}

data class CaptureLaunch(
    val label: String,
    val targetId: String? = null,
    val jobId: String? = null,
    val siteSubmissionId: String? = null,
    val workflowName: String? = null,
    val workflowSteps: List<String> = emptyList(),
    val zone: String? = null,
    val owner: String? = null,
    val requestedOutputs: List<String> = listOf("qualification", "review_intake"),
    val quotedPayoutCents: Int? = null,
    val rightsProfile: String? = null,
)

data class ScanTarget(
    val id: String,
    val title: String,
    val subtitle: String,
    val payoutText: String,
    val distanceText: String,
    val readyNow: Boolean,
    val workflowName: String? = null,
    val workflowSteps: List<String> = emptyList(),
    val zone: String? = null,
    val owner: String? = null,
    val siteSubmissionId: String? = null,
    val quotedPayoutCents: Int? = null,
    val requestedOutputs: List<String> = listOf("qualification", "review_intake"),
    val rightsProfile: String? = null,
)

@Serializable
enum class UploadQueueStatus {
    Saved,
    Queued,
    Preparing,
    Uploading,
    Registering,
    Completed,
    Failed,
}

@Serializable
data class UploadQueueItem(
    val id: String,
    val sceneId: String = "",
    val captureId: String = "",
    val label: String,
    val progress: Float,
    val status: UploadQueueStatus = UploadQueueStatus.Queued,
    val detail: String = "",
    val localBundlePath: String? = null,
    val remotePrefix: String? = null,
    val creatorId: String? = null,
    val captureJobId: String? = null,
    val siteSubmissionId: String? = null,
    val captureStartEpochMs: Long = System.currentTimeMillis(),
    val captureDurationMs: Long? = null,
    val quotedPayoutCents: Int? = null,
    val requestedOutputs: List<String> = emptyList(),
    val uploadCompletedAtEpochMs: Long? = null,
    val submittedAtEpochMs: Long? = null,
    val submissionDocumentPath: String? = null,
    val lastAttemptEpochMs: Long? = null,
    val cancelRequestedAtEpochMs: Long? = null,
    val createdAtEpochMs: Long = System.currentTimeMillis(),
)

data class ContributorStats(
    val totalCaptures: Int,
    val approvedCaptures: Int,
    val averageQuality: Int,
    val totalEarningsCents: Int,
    val availableBalanceCents: Int,
    val referralEarningsCents: Int,
    val referralBonusCents: Int,
) {
    val approvalRatePercent: Int =
        if (totalCaptures == 0) 0 else ((approvedCaptures.toFloat() / totalCaptures.toFloat()) * 100).toInt()
}

data class ContributorProfile(
    val uid: String,
    val name: String,
    val email: String,
    val phoneNumber: String,
    val company: String,
    val role: String,
    val stats: ContributorStats,
)

object DemoData {
    val scanTargets = listOf(
        ScanTarget(
            id = "1",
            title = "North Beach Grocery",
            subtitle = "Capture aisle walkthrough and entry flow",
            payoutText = "$42",
            distanceText = "0.8 mi",
            readyNow = true,
        ),
        ScanTarget(
            id = "2",
            title = "Dockside Fulfillment",
            subtitle = "Inbound walk with dock turns and staging area",
            payoutText = "$58",
            distanceText = "4.1 mi",
            readyNow = true,
        ),
        ScanTarget(
            id = "3",
            title = "Market Hall",
            subtitle = "Collect preview-safe evidence for review",
            payoutText = "$31",
            distanceText = "1.9 mi",
            readyNow = false,
        ),
    )

    val uploadQueue = emptyList<UploadQueueItem>()

    val contributorProfile = ContributorProfile(
        uid = "demo-user",
        name = "Jordan Smith",
        email = "jordan@example.com",
        phoneNumber = "",
        company = "Blueprint Capture",
        role = "capturer",
        stats = ContributorStats(
            totalCaptures = 12,
            approvedCaptures = 10,
            averageQuality = 87,
            totalEarningsCents = 58200,
            availableBalanceCents = 14800,
            referralEarningsCents = 2400,
            referralBonusCents = 1000,
        ),
    )
}
