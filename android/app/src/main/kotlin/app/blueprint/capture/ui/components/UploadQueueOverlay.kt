package app.blueprint.capture.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.TextButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.blueprint.capture.data.model.UploadQueueItem
import app.blueprint.capture.data.model.UploadQueueStatus
import app.blueprint.capture.ui.theme.BlueprintBorder
import app.blueprint.capture.ui.theme.BlueprintSurfaceRaised
import app.blueprint.capture.ui.theme.BlueprintTextMuted

@Composable
fun UploadQueueOverlay(
    items: List<UploadQueueItem>,
    onRetry: (String) -> Unit,
) {
    if (items.isEmpty()) return

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(BlueprintSurfaceRaised, RoundedCornerShape(18.dp))
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text("Upload queue")
        items.take(2).forEach { item ->
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text(item.label, color = BlueprintTextMuted)
                    if (item.status == UploadQueueStatus.Failed) {
                        TextButton(onClick = { onRetry(item.id) }) {
                            Text("Retry")
                        }
                    }
                }
                Text(item.detail.ifBlank { item.status.name }, color = BlueprintTextMuted)
                LinearProgressIndicator(
                    progress = { item.progress },
                    modifier = Modifier.fillMaxWidth(),
                    trackColor = BlueprintBorder,
                )
            }
        }
    }
}
