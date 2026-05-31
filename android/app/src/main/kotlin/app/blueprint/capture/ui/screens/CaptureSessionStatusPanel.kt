package app.blueprint.capture.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.blueprint.capture.ui.theme.BlueprintBorder
import app.blueprint.capture.ui.theme.BlueprintTextMuted
import java.util.Locale

@Composable
internal fun CaptureSessionStatusPanel(
    permissionsGranted: Boolean,
    isRecording: Boolean,
    elapsedSeconds: Long,
    uiState: CaptureSessionUiState,
    runtimeStatus: String,
) {
    CaptureSessionSurfaceCard {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                val statusTitle = when {
                    uiState.reviewDraft != null -> "Capture finished"
                    isRecording -> "Recording live"
                    else -> "Capture ready"
                }
                Text(statusTitle)
                Text(formatCaptureElapsed(elapsedSeconds), color = BlueprintTextMuted)
            }
            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(if (permissionsGranted) "Permissions ready" else "Permissions missing")
                Text(runtimeStatus, color = BlueprintTextMuted)
            }
        }

        Text(captureSessionStatusLabel(uiState), color = BlueprintTextMuted)

        if (uiState.actionState != FinishedCaptureActionState.Idle) {
            LinearProgressIndicator(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 12.dp),
                trackColor = BlueprintBorder,
            )
        }
    }
}


private fun formatCaptureElapsed(seconds: Long): String {
    val minutes = seconds / 60
    val remainingSeconds = seconds % 60
    return String.format(Locale.US, "%02d:%02d", minutes, remainingSeconds)
}

private fun captureSessionStatusLabel(uiState: CaptureSessionUiState): String {
    return when (uiState.actionState) {
        FinishedCaptureActionState.Idle -> {
            when {
                uiState.reviewDraft != null -> "Ready for intake, export, or submission"
                else -> "Review and queueing happens after recording"
            }
        }

        FinishedCaptureActionState.GeneratingIntake -> "Generating intake"
        FinishedCaptureActionState.QueueingUpload -> "Queueing upload"
        FinishedCaptureActionState.SavingForLater -> "Saving bundle locally"
        FinishedCaptureActionState.Exporting -> "Preparing export bundle"
    }
}
