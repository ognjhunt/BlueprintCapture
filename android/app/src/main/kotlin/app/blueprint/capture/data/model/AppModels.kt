package app.blueprint.capture.data.model

import kotlinx.serialization.Serializable

enum class RootStage {
    Onboarding,
    Auth,
    InviteCode,
    Permissions,
    Walkthrough,
    ConnectGlasses,
    App,
}

enum class MainTab {
    Scan,
    Wallet,
    Profile,
}

data class CaptureLaunch(
    val label: String,
    val categoryLabel: String? = null,
    val addressText: String? = null,
    val payoutText: String? = null,
    val distanceText: String? = null,
    val estimatedMinutes: Int? = null,
    val permissionTone: CapturePermissionTone = CapturePermissionTone.Review,
    val imageUrl: String? = null,
    val detailChecklist: List<String> = emptyList(),
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
    val autoStartRecorder: Boolean = false,
)

enum class CapturePermissionTone {
    Approved,
    Review,
    Permission,
    Blocked,
}

enum class TargetAvailabilityStatus {
    Available,
    Reserved,
    InProgress,
    Completed;

    val firestoreValue: String
        get() = when (this) {
            Available -> "available"
            Reserved -> "reserved"
            InProgress -> "in_progress"
            Completed -> "completed"
        }

    companion object {
        fun fromFirestoreValue(value: String): TargetAvailabilityStatus? = when (value) {
            "available" -> Available
            "reserved" -> Reserved
            "in_progress" -> InProgress
            "completed" -> Completed
            else -> null
        }
    }
}

enum class VenuePermission {
    Documented,   // Explicit written permission on file
    PolicyOnly,   // Public area, policy permits capture
    Unknown,      // Not assessed
    Blocked,      // Explicitly prohibited
}

data class ScanTarget(
    val id: String,
    val title: String,
    val subtitle: String,
    val payoutText: String,
    val distanceText: String,
    val readyNow: Boolean,
    val addressText: String = subtitle,
    val categoryLabel: String? = null,
    val estimatedMinutes: Int? = null,
    val permissionTone: CapturePermissionTone = if (readyNow) CapturePermissionTone.Approved else CapturePermissionTone.Review,
    val imageUrl: String? = null,
    val detailChecklist: List<String> = emptyList(),
    val workflowName: String? = null,
    val workflowSteps: List<String> = emptyList(),
    val zone: String? = null,
    val owner: String? = null,
    val siteSubmissionId: String? = null,
    val quotedPayoutCents: Int? = null,
    val requestedOutputs: List<String> = listOf("qualification", "review_intake"),
    val rightsProfile: String? = null,
    // Phase 2 location + ranking fields
    val lat: Double? = null,
    val lng: Double? = null,
    val priorityWeight: Double = 0.0,
    val checkinRadiusM: Int = 150,
    // Target reservation/availability state (fetched from target_state collection)
    val targetAvailability: TargetAvailabilityStatus = TargetAvailabilityStatus.Available,
    // Venue permission classification
    val venuePermission: VenuePermission = VenuePermission.Unknown,
    // Demand-intelligence metadata
    val siteType: String? = null,
    val demandScore: Double? = null,
    val opportunityScore: Double? = null,
    val demandSummary: String? = null,
    val rankingExplanation: String? = null,
    val demandSourceKinds: List<String> = emptyList(),
    val suggestedWorkflows: List<String> = emptyList(),
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
    // Capture-source and sensor metadata forwarded to the Firestore submission doc
    val captureSource: String = "android",   // "android" | "glasses"
    val motionSampleCount: Int = 0,
    val priorityWeight: Double = 0.0,
    val reservationId: String? = null,
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
            title = "Chapel Hill Street Garage",
            subtitle = "E Chapel Hill St · Durham",
            payoutText = "$30",
            distanceText = "2.5 mi",
            readyNow = false,
            addressText = "E Chapel Hill St · Durham",
            categoryLabel = "PARKING",
            estimatedMinutes = 20,
            permissionTone = CapturePermissionTone.Review,
            detailChecklist = listOf(
                "Stay in common or approved areas only.",
                "Keep faces, screens, and paperwork out of frame.",
                "Call out restricted zones before you begin.",
                "Complete all floors before submitting.",
            ),
            quotedPayoutCents = 3000,
            imageUrl = "https://images.unsplash.com/photo-1486406146926-c627a92ad1ab?auto=format&fit=crop&w=1200&q=80",
        ),
        ScanTarget(
            id = "2",
            title = "Durham County Library",
            subtitle = "N Roxboro St · Durham",
            payoutText = "$35",
            distanceText = "1.9 mi",
            readyNow = false,
            addressText = "N Roxboro St · Durham",
            categoryLabel = "LIBRARY",
            estimatedMinutes = 18,
            permissionTone = CapturePermissionTone.Review,
            detailChecklist = listOf(
                "Capture public entry and circulation paths first.",
                "Avoid library patrons, staff screens, and check-out desks.",
                "Note any wings or reading rooms that are off-limits.",
                "Finish each accessible floor before submitting.",
            ),
            quotedPayoutCents = 3500,
            imageUrl = "https://images.unsplash.com/photo-1511818966892-d7d671e672a2?auto=format&fit=crop&w=1200&q=80",
        ),
        ScanTarget(
            id = "3",
            title = "Market Hall Grocery",
            subtitle = "Broad St · Durham",
            payoutText = "$42",
            distanceText = "0.8 mi",
            readyNow = true,
            addressText = "Broad St · Durham",
            categoryLabel = "MARKET",
            estimatedMinutes = 16,
            permissionTone = CapturePermissionTone.Approved,
            detailChecklist = listOf(
                "Start with the main entrance and front-of-house aisles.",
                "Keep checkout screens, staff stations, and paperwork out of frame.",
                "Call out any employee-only sections before moving on.",
                "Cover each aisle group before ending the capture.",
            ),
            quotedPayoutCents = 4200,
            imageUrl = "https://images.unsplash.com/photo-1488459716781-31db52582fe9?auto=format&fit=crop&w=1200&q=80",
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
