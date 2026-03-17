package app.blueprint.capture.data.model

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
}
