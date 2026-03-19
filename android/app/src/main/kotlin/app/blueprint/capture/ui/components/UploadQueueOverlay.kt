package app.blueprint.capture.ui.components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.CloudUpload
import androidx.compose.material.icons.rounded.ExpandLess
import androidx.compose.material.icons.rounded.ExpandMore
import androidx.compose.material.icons.rounded.HourglassTop
import androidx.compose.material.icons.rounded.ReportProblem
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.TextButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import app.blueprint.capture.data.model.UploadQueueItem
import app.blueprint.capture.data.model.UploadQueueStatus
import app.blueprint.capture.ui.theme.BlueprintBorder
import app.blueprint.capture.ui.theme.BlueprintError
import app.blueprint.capture.ui.theme.BlueprintSurfaceRaised
import app.blueprint.capture.ui.theme.BlueprintSuccess
import app.blueprint.capture.ui.theme.BlueprintTextMuted
import app.blueprint.capture.ui.theme.BlueprintWarning
import kotlinx.coroutines.delay
import kotlin.math.roundToInt

@Composable
fun UploadQueueOverlay(
    items: List<UploadQueueItem>,
    onStartUpload: (String) -> Unit,
    onRetry: (String) -> Unit,
    onDismiss: (String) -> Unit,
    onCancel: (String) -> Unit,
) {
    if (items.isEmpty()) return
    val nowEpochMs = rememberNowEpochMs()

    val sortedItems = remember(items) {
        items.sortedWith(
            compareBy<UploadQueueItem> { priority(it.status) }
                .thenByDescending { it.createdAtEpochMs },
        )
    }
    val primaryItem = sortedItems.firstOrNull() ?: return
    val historyItems = sortedItems.drop(1).take(3)
    var expanded by rememberSaveable(primaryItem.id, sortedItems.size) { mutableStateOf(false) }

    Box(
        modifier = Modifier.fillMaxWidth(),
        contentAlignment = Alignment.BottomCenter,
    ) {
        AnimatedVisibility(
            visible = !expanded,
            enter = slideInVertically(animationSpec = spring(stiffness = 500f)) { it / 2 } + fadeIn(),
            exit = slideOutVertically { it / 2 } + fadeOut(),
        ) {
            CompactUploadPill(
                item = primaryItem,
                nowEpochMs = nowEpochMs,
                onExpand = { expanded = true },
            )
        }

        AnimatedVisibility(
            visible = expanded,
            enter = slideInVertically(animationSpec = spring(stiffness = 500f)) { it / 2 } + fadeIn(),
            exit = slideOutVertically { it / 2 } + fadeOut(),
        ) {
            ExpandedUploadCard(
                    primaryItem = primaryItem,
                    nowEpochMs = nowEpochMs,
                    historyItems = historyItems,
                onStartUpload = onStartUpload,
                onRetry = onRetry,
                onDismiss = {
                    onDismiss(it)
                    expanded = it == primaryItem.id && historyItems.isNotEmpty()
                },
                onCancel = onCancel,
                onCollapse = { expanded = false },
            )
        }
    }
}

@Composable
private fun CompactUploadPill(
    item: UploadQueueItem,
    nowEpochMs: Long,
    onExpand: () -> Unit,
) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onExpand),
        color = BlueprintSurfaceRaised,
        shape = RoundedCornerShape(999.dp),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 14.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            StatusIcon(item.status)
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                Text(statusTitle(item), color = Color.White)
                Text(statusSubtitle(item, nowEpochMs), color = BlueprintTextMuted)
            }
            if (item.status == UploadQueueStatus.Uploading) {
                Text("${(item.progress * 100f).roundToInt()}%", color = Color.White)
            }
            Icon(
                imageVector = Icons.Rounded.ExpandLess,
                contentDescription = "Expand upload queue",
                tint = BlueprintTextMuted,
            )
        }
    }
}

@Composable
private fun ExpandedUploadCard(
    primaryItem: UploadQueueItem,
    nowEpochMs: Long,
    historyItems: List<UploadQueueItem>,
    onStartUpload: (String) -> Unit,
    onRetry: (String) -> Unit,
    onDismiss: (String) -> Unit,
    onCancel: (String) -> Unit,
    onCollapse: () -> Unit,
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        color = BlueprintSurfaceRaised,
        shape = RoundedCornerShape(24.dp),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(headerTitle(primaryItem), color = Color.White)
                    Text(primaryItem.label, color = BlueprintTextMuted)
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Surface(
                        modifier = Modifier.clickable(onClick = onCollapse),
                        color = BlueprintBorder,
                        shape = CircleShape,
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.ExpandMore,
                            contentDescription = "Collapse upload queue",
                            tint = Color.White,
                            modifier = Modifier.padding(6.dp),
                        )
                    }
                    if (isDismissible(primaryItem.status)) {
                        Surface(
                            modifier = Modifier.clickable { onDismiss(primaryItem.id) },
                            color = BlueprintBorder,
                            shape = CircleShape,
                        ) {
                            Icon(
                                imageVector = Icons.Rounded.Close,
                                contentDescription = "Dismiss upload",
                                tint = Color.White,
                                modifier = Modifier.padding(6.dp),
                            )
                        }
                    }
                }
            }

            PrimaryStatusContent(primaryItem, nowEpochMs)

            ActionRow(
                item = primaryItem,
                onStartUpload = onStartUpload,
                onRetry = onRetry,
                onDismiss = onDismiss,
                onCancel = onCancel,
                onCollapse = onCollapse,
            )

            if (historyItems.isNotEmpty()) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("Recent uploads", color = Color.White)
                historyItems.forEach { item ->
                    HistoryRow(
                        item = item,
                        nowEpochMs = nowEpochMs,
                        onStartUpload = onStartUpload,
                            onRetry = onRetry,
                            onDismiss = onDismiss,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun PrimaryStatusContent(item: UploadQueueItem, nowEpochMs: Long) {
    when (item.status) {
        UploadQueueStatus.Saved -> StatusPanel(
            accent = Color.White.copy(alpha = 0.05f),
            title = "Saved for later",
            body = item.detail.ifBlank { "The capture bundle is on this device and ready whenever you want to upload it." },
            payout = item.quotedPayoutCents,
        )

        UploadQueueStatus.Queued,
        UploadQueueStatus.Preparing,
        -> StatusPanel(
            accent = BlueprintWarning.copy(alpha = 0.18f),
            title = "Preparing your capture for upload",
            body = item.detail.ifBlank { "Assembling the bundle and lining up the transfer." },
            progress = item.progress.takeIf { it > 0f },
        )

        UploadQueueStatus.Uploading -> StatusPanel(
            accent = Color.White.copy(alpha = 0.05f),
            title = "Uploading your capture",
            body = uploadEtaText(item, nowEpochMs)
                ?: "Keep the app open for the fastest upload. You can still move between tabs while this finishes.",
            progress = item.progress,
            progressLabel = "${(item.progress * 100f).roundToInt()}%",
        )

        UploadQueueStatus.Registering -> StatusPanel(
            accent = Color.White.copy(alpha = 0.05f),
            title = "Submitting for review",
            body = "The bundle is uploaded. Blueprint is now registering the capture and review payload.",
            progress = item.progress,
        )

        UploadQueueStatus.Completed -> StatusPanel(
            accent = BlueprintSuccess.copy(alpha = 0.16f),
            title = "Capture delivered",
            body = "Nice work. Your walkthrough is uploaded and queued for review.",
            payout = item.quotedPayoutCents,
        )

        UploadQueueStatus.Failed -> StatusPanel(
            accent = BlueprintError.copy(alpha = 0.16f),
            title = "Upload failed",
            body = item.detail.ifBlank { "Upload failed. Please try again." },
        )
    }
}

@Composable
private fun StatusPanel(
    accent: Color,
    title: String,
    body: String,
    progress: Float? = null,
    progressLabel: String? = null,
    payout: Int? = null,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(accent, RoundedCornerShape(18.dp))
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(title, color = Color.White)
        Text(body, color = BlueprintTextMuted)
        if (progress != null) {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                if (progressLabel != null) {
                    Text(progressLabel, color = Color.White)
                }
                LinearProgressIndicator(
                    progress = { progress.coerceIn(0f, 1f) },
                    modifier = Modifier.fillMaxWidth(),
                    trackColor = BlueprintBorder,
                )
            }
        }
        if (payout != null) {
            Text("Estimated payout ${formatPayout(payout)}", color = Color.White)
        }
    }
}

@Composable
private fun ActionRow(
    item: UploadQueueItem,
    onStartUpload: (String) -> Unit,
    onRetry: (String) -> Unit,
    onDismiss: (String) -> Unit,
    onCancel: (String) -> Unit,
    onCollapse: () -> Unit,
) {
    when (item.status) {
        UploadQueueStatus.Saved -> {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Button(
                    onClick = { onStartUpload(item.id) },
                    modifier = Modifier.weight(1f),
                ) {
                    Text("Upload now")
                }
                OutlinedButton(
                    onClick = { onDismiss(item.id) },
                    modifier = Modifier.weight(1f),
                ) {
                    Text("Dismiss")
                }
            }
        }

        UploadQueueStatus.Completed -> {
            Button(
                onClick = { onDismiss(item.id) },
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(
                    containerColor = BlueprintSuccess,
                    contentColor = Color.Black,
                ),
            ) {
                Text("Done")
            }
        }

        UploadQueueStatus.Failed -> {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Button(
                    onClick = { onRetry(item.id) },
                    modifier = Modifier.weight(1f),
                ) {
                    Text("Retry")
                }
                OutlinedButton(
                    onClick = { onDismiss(item.id) },
                    modifier = Modifier.weight(1f),
                ) {
                    Text("Dismiss")
                }
            }
        }

        else -> {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                OutlinedButton(
                    onClick = onCollapse,
                    modifier = Modifier.weight(1f),
                ) {
                    Text("Hide")
                }
                TextButton(
                    onClick = { onCancel(item.id) },
                    modifier = Modifier.weight(1f),
                ) {
                    Text("Cancel upload")
                }
            }
        }
    }
}

@Composable
private fun HistoryRow(
    item: UploadQueueItem,
    nowEpochMs: Long,
    onStartUpload: (String) -> Unit,
    onRetry: (String) -> Unit,
    onDismiss: (String) -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(BlueprintBorder, RoundedCornerShape(18.dp))
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Text(item.label, color = Color.White)
                Text(statusSubtitle(item, nowEpochMs), color = BlueprintTextMuted)
            }
            StatusIcon(item.status)
        }
        if (
            item.status == UploadQueueStatus.Saved ||
            item.status == UploadQueueStatus.Failed ||
            item.status == UploadQueueStatus.Completed
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                if (item.status == UploadQueueStatus.Saved) {
                    TextButton(onClick = { onStartUpload(item.id) }) {
                        Text("Upload")
                    }
                }
                if (item.status == UploadQueueStatus.Failed) {
                    TextButton(onClick = { onRetry(item.id) }) {
                        Text("Retry")
                    }
                }
                TextButton(onClick = { onDismiss(item.id) }) {
                    Text("Dismiss")
                }
            }
        }
    }
}

@Composable
private fun StatusIcon(status: UploadQueueStatus) {
    val imageVector = when (status) {
        UploadQueueStatus.Saved -> Icons.Rounded.CloudUpload
        UploadQueueStatus.Queued,
        UploadQueueStatus.Preparing,
        UploadQueueStatus.Registering,
        -> Icons.Rounded.HourglassTop
        UploadQueueStatus.Uploading -> Icons.Rounded.CloudUpload
        UploadQueueStatus.Completed -> Icons.Rounded.CheckCircle
        UploadQueueStatus.Failed -> Icons.Rounded.ReportProblem
    }
    val tint = when (status) {
        UploadQueueStatus.Completed -> BlueprintSuccess
        UploadQueueStatus.Failed -> BlueprintError
        UploadQueueStatus.Saved -> Color.White
        UploadQueueStatus.Queued,
        UploadQueueStatus.Preparing,
        UploadQueueStatus.Registering,
        -> BlueprintWarning
        UploadQueueStatus.Uploading -> Color.White
    }
    Surface(
        color = tint.copy(alpha = 0.18f),
        shape = CircleShape,
    ) {
        Icon(
            imageVector = imageVector,
            contentDescription = null,
            tint = tint,
            modifier = Modifier.padding(10.dp),
        )
    }
}

private fun statusTitle(item: UploadQueueItem): String {
    return when (item.status) {
        UploadQueueStatus.Saved -> "Saved for later"
        UploadQueueStatus.Queued,
        UploadQueueStatus.Preparing,
        -> "Preparing upload"
        UploadQueueStatus.Uploading -> "Uploading capture"
        UploadQueueStatus.Registering -> "Submitting capture"
        UploadQueueStatus.Completed -> "Submitted for review"
        UploadQueueStatus.Failed -> "Upload failed"
    }
}

private fun headerTitle(item: UploadQueueItem): String {
    return when (item.status) {
        UploadQueueStatus.Saved -> "Saved Capture"
        UploadQueueStatus.Queued,
        UploadQueueStatus.Preparing,
        -> "Preparing Upload"
        UploadQueueStatus.Uploading -> "Uploading Capture"
        UploadQueueStatus.Registering -> "Registering Capture"
        UploadQueueStatus.Completed -> "Capture Delivered"
        UploadQueueStatus.Failed -> "Upload Failed"
    }
}

private fun statusSubtitle(item: UploadQueueItem, nowEpochMs: Long): String {
    return when (item.status) {
        UploadQueueStatus.Saved -> item.detail.ifBlank { "Saved on this device" }
        UploadQueueStatus.Uploading -> {
            val percent = "${(item.progress * 100f).roundToInt()}% complete"
            uploadEtaText(item, nowEpochMs)?.let { "$percent • $it" } ?: percent
        }
        UploadQueueStatus.Completed -> item.detail.ifBlank { "Uploaded and ready for review" }
        else -> item.detail.ifBlank { item.status.name }
    }
}

@Composable
private fun rememberNowEpochMs(): Long {
    val now = remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(1_000)
            now.longValue = System.currentTimeMillis()
        }
    }
    return now.longValue
}

private fun uploadEtaText(item: UploadQueueItem, nowEpochMs: Long): String? {
    if (item.status != UploadQueueStatus.Uploading) return null
    val startedAt = item.lastAttemptEpochMs ?: return null
    val progress = item.progress
    if (progress <= 0.02f || progress >= 0.995f) return null
    val elapsedMs = nowEpochMs - startedAt
    if (elapsedMs <= 2_000L) return null
    val totalMs = (elapsedMs / progress).toLong()
    val remainingMs = totalMs - elapsedMs
    if (remainingMs <= 2_000L) return null
    return "About ${formatDuration(remainingMs)} left"
}

private fun formatDuration(durationMs: Long): String {
    val totalSeconds = (durationMs / 1000L).coerceAtLeast(1L)
    if (totalSeconds < 60L) {
        return "${totalSeconds}s"
    }
    val minutes = totalSeconds / 60L
    val seconds = totalSeconds % 60L
    return if (minutes < 10L && seconds != 0L) {
        "${minutes}m ${seconds}s"
    } else {
        "${minutes}m"
    }
}

private fun priority(status: UploadQueueStatus): Int {
    return when (status) {
        UploadQueueStatus.Uploading -> 0
        UploadQueueStatus.Registering -> 1
        UploadQueueStatus.Preparing -> 2
        UploadQueueStatus.Failed -> 3
        UploadQueueStatus.Saved -> 4
        UploadQueueStatus.Completed -> 5
        UploadQueueStatus.Queued -> 6
    }
}

private fun isDismissible(status: UploadQueueStatus): Boolean {
    return status == UploadQueueStatus.Saved ||
        status == UploadQueueStatus.Completed ||
        status == UploadQueueStatus.Failed
}

private fun formatPayout(cents: Int): String {
    val dollars = cents / 100
    val remainder = cents % 100
    return "$$dollars.${remainder.toString().padStart(2, '0')}"
}
