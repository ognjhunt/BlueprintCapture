package app.blueprint.capture.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ArrowUpward
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.blueprint.capture.ui.theme.BlueprintAccent
import app.blueprint.capture.ui.theme.BlueprintBlack
import app.blueprint.capture.ui.theme.BlueprintBorder
import app.blueprint.capture.ui.theme.BlueprintSuccess
import app.blueprint.capture.ui.theme.BlueprintTeal
import app.blueprint.capture.ui.theme.BlueprintTextMuted
import app.blueprint.capture.ui.theme.BlueprintTextPrimary
import java.util.Locale

@Composable
internal fun PostCaptureReviewSurface(
    uiState: CaptureSessionUiState,
    draft: CaptureReviewDraft,
    onClose: () -> Unit,
    onContinueWorkflow: () -> Unit,
    onWorkflowNameChanged: (String) -> Unit,
    onTaskStepsChanged: (String) -> Unit,
    onZoneChanged: (String) -> Unit,
    onOwnerChanged: (String) -> Unit,
    onNotesChanged: (String) -> Unit,
    onUploadNow: () -> Unit,
    onSaveForLater: () -> Unit,
    onExportForTesting: () -> Unit,
) {
    val isBusy = uiState.actionState != FinishedCaptureActionState.Idle
    // Alpha: suppress manual intake form — always skip regardless of AI intake result
    @Suppress("UNUSED_VARIABLE")
    val needsManualEntry = false

    val spaceTitle = draft.capture.label.ifBlank { "Capture complete" }
    val spaceAddress = draft.capture.addressText?.ifBlank { null }
    val workflowReview = draft.siteWorldReview

    // Duration + size for the summary card
    val durationSec = draft.captureDurationMs / 1_000L
    val estimatedMB = run {
        val pixels = draft.width.toLong() * draft.height.toLong()
        val mbPerMin = when {
            pixels >= 8_294_400L -> 280.0
            pixels >= 2_073_600L -> 85.0
            else -> 42.0
        }
        (durationSec / 60.0 * mbPerMin).toLong().coerceAtLeast(1L)
    }
    val sizeLabel = if (estimatedMB >= 1024) "%.1f GB".format(estimatedMB / 1024.0) else "$estimatedMB MB"

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black),
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .verticalScroll(rememberScrollState())
                .padding(bottom = 160.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            // ── Close button (top-left) ────────────────────────────────
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp, vertical = 16.dp),
            ) {
                Box(
                    modifier = Modifier
                        .size(36.dp)
                        .clip(CircleShape)
                        .background(Color(0xFF1A1A1A))
                        .clickable(onClick = onClose, enabled = !isBusy),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        imageVector = Icons.Rounded.Close,
                        contentDescription = "Close",
                        tint = if (isBusy) Color(0xFF444444) else Color.White,
                        modifier = Modifier.size(18.dp),
                    )
                }
            }

            // ── Hero: checkmark + space name ──────────────────────────
            Spacer(modifier = Modifier.height(16.dp))

            if (isBusy) {
                CircularProgressIndicator(
                    modifier = Modifier.size(52.dp),
                    color = BlueprintTeal,
                    strokeWidth = 3.dp,
                    trackColor = Color(0xFF1A1A1A),
                )
            } else {
                Icon(
                    imageVector = Icons.Rounded.Check,
                    contentDescription = null,
                    tint = BlueprintSuccess,
                    modifier = Modifier
                        .size(52.dp)
                        .clip(CircleShape)
                        .background(BlueprintSuccess.copy(alpha = 0.15f))
                        .padding(12.dp),
                )
            }

            Spacer(modifier = Modifier.height(20.dp))

            Text(
                text = when (uiState.actionState) {
                    FinishedCaptureActionState.GeneratingIntake -> "Preparing…"
                    FinishedCaptureActionState.QueueingUpload -> "Uploading…"
                    FinishedCaptureActionState.SavingForLater -> "Saving…"
                    FinishedCaptureActionState.Exporting -> "Exporting…"
                    FinishedCaptureActionState.Idle -> spaceTitle
                },
                color = Color.White,
                fontSize = 26.sp,
                fontWeight = FontWeight.Bold,
                letterSpacing = (-0.5).sp,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                modifier = Modifier.padding(horizontal = 28.dp),
            )

            if (spaceAddress != null && !isBusy) {
                Spacer(modifier = Modifier.height(6.dp))
                Text(
                    text = spaceAddress,
                    color = Color(0xFF666666),
                    fontSize = 15.sp,
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                    modifier = Modifier.padding(horizontal = 28.dp),
                )
            }

            Spacer(modifier = Modifier.height(36.dp))

            // ── Summary card: Duration + Size ─────────────────────────
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp)
                    .clip(RoundedCornerShape(14.dp))
                    .background(Color(0xFF111111)),
            ) {
                ReviewSummaryRow("Duration", formatCaptureDurationMs(draft.captureDurationMs))
                HorizontalDivider(color = Color(0xFF222222), thickness = 1.dp)
                ReviewSummaryRow("Size", sizeLabel)
            }

            workflowReview?.let { review ->
                Spacer(modifier = Modifier.height(12.dp))
                SiteWorldReviewCard(review = review)
            }

            // ── Manual intake (only when AI couldn't resolve) ─────────
            if (needsManualEntry) {
                Spacer(modifier = Modifier.height(12.dp))
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 20.dp)
                        .clip(RoundedCornerShape(14.dp))
                        .background(Color(0xFF111111))
                        .padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Text("Add capture context", color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                    OutlinedTextField(
                        value = draft.workflowName,
                        onValueChange = onWorkflowNameChanged,
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("Workflow name") },
                        singleLine = true,
                        enabled = !isBusy,
                        shape = RoundedCornerShape(10.dp),
                        colors = androidx.compose.material3.OutlinedTextFieldDefaults.colors(
                            focusedTextColor = Color.White,
                            unfocusedTextColor = Color.White,
                            focusedContainerColor = Color(0xFF1A1A1A),
                            unfocusedContainerColor = Color(0xFF1A1A1A),
                            focusedBorderColor = BlueprintTeal.copy(alpha = 0.5f),
                            unfocusedBorderColor = Color(0xFF333333),
                            cursorColor = BlueprintTeal,
                            focusedLabelColor = Color(0xFF666666),
                            unfocusedLabelColor = Color(0xFF666666),
                        ),
                    )
                    OutlinedTextField(
                        value = draft.taskStepsText,
                        onValueChange = onTaskStepsChanged,
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("Task steps (one per line)") },
                        minLines = 3,
                        enabled = !isBusy,
                        shape = RoundedCornerShape(10.dp),
                        colors = androidx.compose.material3.OutlinedTextFieldDefaults.colors(
                            focusedTextColor = Color.White,
                            unfocusedTextColor = Color.White,
                            focusedContainerColor = Color(0xFF1A1A1A),
                            unfocusedContainerColor = Color(0xFF1A1A1A),
                            focusedBorderColor = BlueprintTeal.copy(alpha = 0.5f),
                            unfocusedBorderColor = Color(0xFF333333),
                            cursorColor = BlueprintTeal,
                            focusedLabelColor = Color(0xFF666666),
                            unfocusedLabelColor = Color(0xFF666666),
                        ),
                    )
                }
            }

            // ── Notes ─────────────────────────────────────────────────
            Spacer(modifier = Modifier.height(12.dp))
            OutlinedTextField(
                value = draft.notes,
                onValueChange = onNotesChanged,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp),
                placeholder = { Text("Add a note (optional)", color = Color(0xFF444444)) },
                minLines = 2,
                enabled = !isBusy,
                shape = RoundedCornerShape(14.dp),
                colors = androidx.compose.material3.OutlinedTextFieldDefaults.colors(
                    focusedTextColor = Color.White,
                    unfocusedTextColor = Color.White,
                    focusedContainerColor = Color(0xFF111111),
                    unfocusedContainerColor = Color(0xFF111111),
                    focusedBorderColor = BlueprintTeal.copy(alpha = 0.5f),
                    unfocusedBorderColor = Color(0xFF222222),
                    cursorColor = BlueprintTeal,
                ),
            )
        }

        // ── Pinned CTAs ───────────────────────────────────────────────
        Column(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .background(
                    Brush.verticalGradient(
                        colors = listOf(Color.Transparent, Color.Black.copy(alpha = 0.97f), Color.Black),
                    ),
                )
                .navigationBarsPadding()
                .padding(horizontal = 20.dp)
                .padding(top = 24.dp, bottom = 20.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            if (workflowReview?.nextActionLabel != null) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(14.dp))
                        .background(BlueprintTeal)
                        .clickable(enabled = !isBusy, onClick = onContinueWorkflow)
                        .padding(vertical = 17.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        workflowReview.nextActionLabel,
                        color = BlueprintBlack,
                        fontSize = 17.sp,
                        fontWeight = FontWeight.SemiBold,
                    )
                }
            }

            // Primary — Upload
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(14.dp))
                    .background(if (isBusy) Color.White.copy(alpha = 0.3f) else Color.White)
                    .clickable(enabled = !isBusy, onClick = onUploadNow)
                    .padding(vertical = 17.dp),
                contentAlignment = Alignment.Center,
            ) {
                if (isBusy) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(22.dp),
                        color = Color.Black.copy(alpha = 0.4f),
                        strokeWidth = 2.5.dp,
                        trackColor = Color.Transparent,
                    )
                } else {
                    Text("Upload", color = Color.Black, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                }
            }

            // Secondary — Export
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(14.dp))
                    .background(Color(0xFF111111))
                    .border(1.dp, Color(0xFF2A2A2A), RoundedCornerShape(14.dp))
                    .clickable(enabled = !isBusy, onClick = onExportForTesting)
                    .padding(vertical = 16.dp),
                contentAlignment = Alignment.Center,
            ) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        imageVector = Icons.Rounded.ArrowUpward,
                        contentDescription = null,
                        tint = Color.White,
                        modifier = Modifier.size(16.dp),
                    )
                    Text("Export bundle", color = Color.White, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                }
            }

            // Tertiary — save for later
            androidx.compose.material3.TextButton(
                onClick = onSaveForLater,
                enabled = !isBusy,
            ) {
                Text("Save for later", color = if (isBusy) Color(0xFF333333) else Color(0xFF555555), fontSize = 14.sp)
            }
        }
    }
}

@Composable
private fun ReviewSummaryRow(label: String, value: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 14.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, color = Color(0xFF666666), fontSize = 15.sp)
        Text(value, color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
    }
}


private fun formatCaptureElapsed(seconds: Long): String {
    val minutes = seconds / 60
    val remainingSeconds = seconds % 60
    return String.format(Locale.US, "%02d:%02d", minutes, remainingSeconds)
}

private fun formatCaptureDurationMs(durationMs: Long): String {
    return formatCaptureElapsed(durationMs / 1_000L)
}

@Composable
private fun PostCaptureStatCard(label: String, value: String, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier
            .clip(RoundedCornerShape(16.dp))
            .background(Color(0xFF171719))
            .border(1.dp, BlueprintBorder, RoundedCornerShape(16.dp))
            .padding(vertical = 14.dp, horizontal = 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(value, color = BlueprintTextPrimary, fontSize = 22.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.3).sp)
        Text(label, color = BlueprintTextMuted, fontSize = 12.sp, fontWeight = FontWeight.Medium)
    }
}

private enum class PostCaptureReviewTone { Good, Warning, Neutral }

@Composable
private fun PostCaptureReviewReadinessRow(label: String, value: String, tone: PostCaptureReviewTone) {
    val valueColor = when (tone) {
        PostCaptureReviewTone.Good -> BlueprintSuccess
        PostCaptureReviewTone.Warning -> BlueprintAccent
        PostCaptureReviewTone.Neutral -> BlueprintTextPrimary
    }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 11.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, color = BlueprintTextMuted, fontSize = 14.sp)
        Text(value, color = valueColor, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun PostCaptureReviewReadinessDivider() {
    Box(modifier = Modifier.fillMaxWidth().height(1.dp).background(BlueprintBorder))
}
