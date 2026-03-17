package app.blueprint.capture.data.model

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

data class ScanTarget(
    val id: String,
    val title: String,
    val subtitle: String,
    val payoutText: String,
    val distanceText: String,
    val readyNow: Boolean,
)

data class UploadQueueItem(
    val id: String,
    val label: String,
    val progress: Float,
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

    val uploadQueue = listOf(
        UploadQueueItem(
            id = "upload-1",
            label = "North Beach Grocery",
            progress = 0.58f,
        )
    )

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
