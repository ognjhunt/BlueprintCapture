package app.blueprint.capture.ui.screens

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.video.FileOutputOptions
import androidx.camera.video.FallbackStrategy
import androidx.camera.video.Quality
import androidx.camera.video.QualitySelector
import androidx.camera.video.Recorder
import androidx.camera.video.Recording
import androidx.camera.video.VideoCapture
import androidx.camera.video.VideoRecordEvent
import androidx.camera.view.PreviewView
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.LocalLifecycleOwner
import app.blueprint.capture.data.model.CaptureLaunch
import app.blueprint.capture.ui.theme.BlueprintAccent
import app.blueprint.capture.ui.theme.BlueprintBlack
import app.blueprint.capture.ui.theme.BlueprintBorder
import app.blueprint.capture.ui.theme.BlueprintSurfaceRaised
import app.blueprint.capture.ui.theme.BlueprintTextMuted
import java.io.File
import java.util.Locale
import java.util.UUID
import kotlinx.coroutines.delay
import kotlin.math.roundToInt

@Composable
fun CaptureSessionScreen(
    capture: CaptureLaunch,
    onClose: () -> Unit,
    viewModel: CaptureSessionViewModel = hiltViewModel(),
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val uiState by viewModel.uiState.collectAsState()
    val reviewDraft = uiState.reviewDraft

    var permissionsGranted by remember { mutableStateOf(hasCapturePermissions(context)) }
    var cameraError by remember { mutableStateOf<String?>(null) }
    var videoCapture by remember { mutableStateOf<VideoCapture<Recorder>?>(null) }
    var recording by remember { mutableStateOf<Recording?>(null) }
    var isRecording by remember { mutableStateOf(false) }
    var elapsedSeconds by remember { mutableLongStateOf(0L) }
    var captureStartEpochMs by remember { mutableLongStateOf(0L) }
    val previewView = remember(context) {
        PreviewView(context).apply {
            implementationMode = PreviewView.ImplementationMode.COMPATIBLE
            scaleType = PreviewView.ScaleType.FILL_CENTER
        }
    }
    val mainExecutor = remember(context) { ContextCompat.getMainExecutor(context) }
    val permissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestMultiplePermissions(),
    ) {
        permissionsGranted = hasCapturePermissions(context)
    }

    fun closeSession() {
        if (reviewDraft != null) {
            viewModel.discardPendingCapture()
        }
        onClose()
    }

    BackHandler {
        if (!isRecording && !uiState.isPackaging) {
            closeSession()
        }
    }

    LaunchedEffect(Unit) {
        if (!permissionsGranted) {
            permissionLauncher.launch(REQUIRED_CAPTURE_PERMISSIONS)
        }
    }

    LaunchedEffect(isRecording, captureStartEpochMs) {
        while (isRecording) {
            elapsedSeconds = ((System.currentTimeMillis() - captureStartEpochMs) / 1_000L).coerceAtLeast(0L)
            delay(1_000L)
        }
    }

    LaunchedEffect(uiState.queuedUploadId, uiState.savedUploadId) {
        if (uiState.queuedUploadId != null || uiState.savedUploadId != null) {
            onClose()
        }
    }

    DisposableEffect(permissionsGranted, lifecycleOwner, previewView) {
        if (!permissionsGranted) {
            videoCapture = null
            onDispose { }
        } else {
            val cameraProviderFuture = ProcessCameraProvider.getInstance(context)
            val listener = Runnable {
                runCatching {
                    val preview = Preview.Builder().build().also {
                        it.surfaceProvider = previewView.surfaceProvider
                    }
                    val recorder = Recorder.Builder()
                        .setQualitySelector(
                            QualitySelector.from(
                                Quality.FHD,
                                FallbackStrategy.lowerQualityOrHigherThan(Quality.SD),
                            ),
                        )
                        .build()
                    val captureUseCase = VideoCapture.withOutput(recorder)
                    val cameraProvider = cameraProviderFuture.get()
                    cameraProvider.unbindAll()
                    cameraProvider.bindToLifecycle(
                        lifecycleOwner,
                        CameraSelector.DEFAULT_BACK_CAMERA,
                        preview,
                        captureUseCase,
                    )
                    videoCapture = captureUseCase
                    cameraError = null
                }.onFailure { error ->
                    videoCapture = null
                    cameraError = error.message ?: "Unable to bind the Android camera session."
                }
            }

            cameraProviderFuture.addListener(listener, mainExecutor)
            onDispose {
                recording?.stop()
                runCatching {
                    cameraProviderFuture.get().unbindAll()
                }
            }
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(BlueprintBlack),
    ) {
        AndroidView(
            factory = { previewView },
            modifier = Modifier.fillMaxSize(),
        )

        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .navigationBarsPadding()
                .padding(horizontal = 20.dp, vertical = 16.dp),
            verticalArrangement = Arrangement.SpaceBetween,
        ) {
            Column(
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text("Phone Capture")
                    if (!isRecording && !uiState.isPackaging) {
                        OutlinedButton(onClick = ::closeSession) {
                            Text(if (reviewDraft != null) "Discard" else "Close")
                        }
                    }
                }

                SurfaceCard {
                    Text(capture.label)
                    Text(
                        when {
                            !permissionsGranted -> {
                                "Camera and microphone access are required before Android can record the walkthrough."
                            }

                            reviewDraft != null -> {
                                "Review the finished capture, confirm structured intake, then choose whether to upload now or save the bundle for later."
                            }

                            else -> {
                                "Record the walkthrough first. Android now stops in a real post-capture review stage instead of jumping straight into queueing."
                            }
                        },
                        color = BlueprintTextMuted,
                    )
                }

                cameraError?.let { message ->
                    SurfaceCard {
                        Text("Camera issue")
                        Text(message, color = BlueprintTextMuted)
                    }
                }

                uiState.errorMessage?.let { message ->
                    SurfaceCard {
                        Text("Capture review issue")
                        Text(message, color = BlueprintTextMuted)
                        OutlinedButton(onClick = viewModel::clearError) {
                            Text("Dismiss")
                        }
                    }
                }
            }

            Column(
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                SessionStatusCard(
                    permissionsGranted = permissionsGranted,
                    isRecording = isRecording,
                    elapsedSeconds = elapsedSeconds,
                    uiState = uiState,
                )

                when {
                    !permissionsGranted -> {
                        Button(
                            onClick = { permissionLauncher.launch(REQUIRED_CAPTURE_PERMISSIONS) },
                            modifier = Modifier.fillMaxWidth(),
                            colors = ButtonDefaults.buttonColors(
                                containerColor = BlueprintAccent,
                                contentColor = BlueprintBlack,
                            ),
                        ) {
                            Text("Grant camera + microphone access")
                        }
                    }

                    reviewDraft != null -> {
                        ReviewPanel(
                            draft = reviewDraft,
                            isPackaging = uiState.isPackaging,
                            onWorkflowNameChanged = viewModel::updateWorkflowName,
                            onTaskStepsChanged = viewModel::updateTaskSteps,
                            onZoneChanged = viewModel::updateZone,
                            onOwnerChanged = viewModel::updateOwner,
                            onNotesChanged = viewModel::updateReviewNotes,
                            onUploadNow = { viewModel.packageCapture(startImmediately = true) },
                            onSaveForLater = { viewModel.packageCapture(startImmediately = false) },
                        )
                    }

                    !isRecording -> {
                        Button(
                            onClick = {
                                val captureUseCase = videoCapture ?: return@Button
                                val outputFile = createRecordingFile(context)
                                captureStartEpochMs = System.currentTimeMillis()
                                elapsedSeconds = 0L
                                cameraError = null

                                var pendingRecording = captureUseCase.output.prepareRecording(
                                    context,
                                    FileOutputOptions.Builder(outputFile).build(),
                                )
                                pendingRecording = pendingRecording.withAudioEnabled()

                                recording = pendingRecording.start(mainExecutor) { event ->
                                    when (event) {
                                        is VideoRecordEvent.Start -> {
                                            isRecording = true
                                        }

                                        is VideoRecordEvent.Status -> {
                                            elapsedSeconds = event.recordingStats.recordedDurationNanos / 1_000_000_000L
                                        }

                                        is VideoRecordEvent.Finalize -> {
                                            isRecording = false
                                            recording = null
                                            if (event.hasError()) {
                                                outputFile.delete()
                                                cameraError = event.cause?.message
                                                    ?: "Recording failed before the file finalized."
                                            } else {
                                                viewModel.prepareRecordedCapture(
                                                    capture = capture,
                                                    recordingFile = outputFile,
                                                    captureStartEpochMs = captureStartEpochMs,
                                                    captureDurationMs = event.recordingStats.recordedDurationNanos / 1_000_000L,
                                                )
                                            }
                                        }
                                    }
                                }
                            },
                            enabled = videoCapture != null && !uiState.isPackaging,
                            modifier = Modifier.fillMaxWidth(),
                            colors = ButtonDefaults.buttonColors(
                                containerColor = BlueprintAccent,
                                contentColor = BlueprintBlack,
                            ),
                        ) {
                            Text("Start walkthrough recording")
                        }
                    }

                    else -> {
                        Button(
                            onClick = { recording?.stop() },
                            enabled = !uiState.isPackaging,
                            modifier = Modifier.fillMaxWidth(),
                            colors = ButtonDefaults.buttonColors(
                                containerColor = BlueprintAccent,
                                contentColor = BlueprintBlack,
                            ),
                        ) {
                            Text("Finish capture and review")
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun SessionStatusCard(
    permissionsGranted: Boolean,
    isRecording: Boolean,
    elapsedSeconds: Long,
    uiState: CaptureSessionUiState,
) {
    SurfaceCard {
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
                Text(formatElapsed(elapsedSeconds), color = BlueprintTextMuted)
            }
            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(if (permissionsGranted) "Permissions ready" else "Permissions missing")
                Text(
                    when {
                        uiState.isPackaging -> "Packaging bundle"
                        uiState.reviewDraft != null -> "Structured intake required"
                        else -> "Review and queueing happens after recording"
                    },
                    color = BlueprintTextMuted,
                )
            }
        }

        if (uiState.isPackaging) {
            LinearProgressIndicator(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 12.dp),
                trackColor = BlueprintBorder,
            )
        }
    }
}

@Composable
private fun ReviewPanel(
    draft: CaptureReviewDraft,
    isPackaging: Boolean,
    onWorkflowNameChanged: (String) -> Unit,
    onTaskStepsChanged: (String) -> Unit,
    onZoneChanged: (String) -> Unit,
    onOwnerChanged: (String) -> Unit,
    onNotesChanged: (String) -> Unit,
    onUploadNow: () -> Unit,
    onSaveForLater: () -> Unit,
) {
    SurfaceCard {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Text("Post-Capture Review")
            Text(
                "Confirm the workflow details before Android packages this bundle. This mirrors the iOS rule that structured intake must exist before submission.",
                color = BlueprintTextMuted,
            )

            DetailRow("Duration", formatDurationMs(draft.captureDurationMs))
            DetailRow("Resolution", "${draft.width} x ${draft.height}")
            DetailRow("Frame rate", "${draft.frameRate.roundToInt()} fps")
            DetailRow(
                "Requested outputs",
                draft.capture.requestedOutputs.joinToString().ifBlank { "qualification, review_intake" },
            )
            draft.capture.quotedPayoutCents?.let { payout ->
                DetailRow("Estimated payout", formatPayout(payout))
            }
            draft.capture.rightsProfile?.takeIf(String::isNotBlank)?.let { rightsProfile ->
                DetailRow("Rights profile", rightsProfile.replace('_', ' '))
            }

            OutlinedTextField(
                value = draft.workflowName,
                onValueChange = onWorkflowNameChanged,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Workflow name") },
                singleLine = true,
                enabled = !isPackaging,
            )
            OutlinedTextField(
                value = draft.taskStepsText,
                onValueChange = onTaskStepsChanged,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Task steps") },
                minLines = 3,
                enabled = !isPackaging,
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                OutlinedTextField(
                    value = draft.zone,
                    onValueChange = onZoneChanged,
                    modifier = Modifier.weight(1f),
                    label = { Text("Zone") },
                    singleLine = true,
                    enabled = !isPackaging,
                )
                OutlinedTextField(
                    value = draft.owner,
                    onValueChange = onOwnerChanged,
                    modifier = Modifier.weight(1f),
                    label = { Text("Owner") },
                    singleLine = true,
                    enabled = !isPackaging,
                )
            }
            OutlinedTextField(
                value = draft.notes,
                onValueChange = onNotesChanged,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Capture notes") },
                minLines = 3,
                enabled = !isPackaging,
            )

            Text(
                if (draft.isStructuredIntakeComplete) {
                    "Structured intake complete. You can queue the upload now or save the bundle on-device."
                } else {
                    "Enter workflow details, at least one task step, and either a zone or owner to continue."
                },
                color = BlueprintTextMuted,
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Button(
                    onClick = onUploadNow,
                    modifier = Modifier.weight(1f),
                    enabled = draft.isStructuredIntakeComplete && !isPackaging,
                    colors = ButtonDefaults.buttonColors(
                        containerColor = BlueprintAccent,
                        contentColor = BlueprintBlack,
                    ),
                ) {
                    Text("Upload now")
                }
                OutlinedButton(
                    onClick = onSaveForLater,
                    modifier = Modifier.weight(1f),
                    enabled = draft.isStructuredIntakeComplete && !isPackaging,
                ) {
                    Text("Upload later")
                }
            }
        }
    }
}

@Composable
private fun DetailRow(
    label: String,
    value: String,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(label, color = BlueprintTextMuted)
        Text(value)
    }
}

@Composable
private fun SurfaceCard(
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(BlueprintSurfaceRaised, RoundedCornerShape(22.dp))
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
        content = content,
    )
}

private fun hasCapturePermissions(context: Context): Boolean {
    return REQUIRED_CAPTURE_PERMISSIONS.all { permission ->
        ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED
    }
}

private fun createRecordingFile(context: Context): File {
    return context.cacheDir.resolve("recordings").also { it.mkdirs() }
        .resolve("walkthrough-${UUID.randomUUID()}.mp4")
}

private fun formatElapsed(seconds: Long): String {
    val minutes = seconds / 60
    val remainingSeconds = seconds % 60
    return String.format(Locale.US, "%02d:%02d", minutes, remainingSeconds)
}

private fun formatDurationMs(durationMs: Long): String {
    return formatElapsed(durationMs / 1_000L)
}

private fun formatPayout(cents: Int): String {
    val dollars = cents / 100
    val remainder = cents % 100
    return "$$dollars.${remainder.toString().padStart(2, '0')}"
}

private val REQUIRED_CAPTURE_PERMISSIONS = arrayOf(
    Manifest.permission.CAMERA,
    Manifest.permission.RECORD_AUDIO,
)
