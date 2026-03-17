package app.blueprint.capture.ui.screens

import android.Manifest
import android.content.Context
import android.content.Intent
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
import androidx.core.content.FileProvider
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
    val isBusy = uiState.actionState != FinishedCaptureActionState.Idle

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
        if (!isRecording && !isBusy) {
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

    LaunchedEffect(uiState.exportSharePath) {
        val exportSharePath = uiState.exportSharePath ?: return@LaunchedEffect
        shareExportArtifact(context, File(exportSharePath))
        viewModel.consumeExportShare()
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
                    if (!isRecording && !isBusy) {
                        OutlinedButton(onClick = ::closeSession) {
                            Text(
                                when {
                                    uiState.exportMessage != null -> "Done"
                                    reviewDraft != null -> "Discard"
                                    else -> "Close"
                                },
                            )
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
                                "Review the finished capture, run intake resolution, then decide whether to export, upload now, or save for later."
                            }

                            else -> {
                                "Record the walkthrough first. Android now holds the finished capture in-session instead of dropping straight into queueing."
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

                uiState.exportMessage?.let { message ->
                    SurfaceCard {
                        Text("Export ready")
                        Text(message, color = BlueprintTextMuted)
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
                            actionState = uiState.actionState,
                            exportMessage = uiState.exportMessage,
                            onWorkflowNameChanged = viewModel::updateWorkflowName,
                            onTaskStepsChanged = viewModel::updateTaskSteps,
                            onZoneChanged = viewModel::updateZone,
                            onOwnerChanged = viewModel::updateOwner,
                            onNotesChanged = viewModel::updateReviewNotes,
                            onUploadNow = viewModel::queueUploadNow,
                            onSaveForLater = viewModel::saveForLater,
                            onExportForTesting = viewModel::exportForTesting,
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
                            enabled = videoCapture != null && !isBusy,
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
                            enabled = !isBusy,
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
                Text(statusLabel(uiState), color = BlueprintTextMuted)
            }
        }

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

@Composable
private fun ReviewPanel(
    draft: CaptureReviewDraft,
    actionState: FinishedCaptureActionState,
    exportMessage: String?,
    onWorkflowNameChanged: (String) -> Unit,
    onTaskStepsChanged: (String) -> Unit,
    onZoneChanged: (String) -> Unit,
    onOwnerChanged: (String) -> Unit,
    onNotesChanged: (String) -> Unit,
    onUploadNow: () -> Unit,
    onSaveForLater: () -> Unit,
    onExportForTesting: () -> Unit,
) {
    val isBusy = actionState != FinishedCaptureActionState.Idle

    SurfaceCard {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Text(draft.reviewTitle)
            Text(draft.helperText, color = BlueprintTextMuted)

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
            draft.intakeMetadata?.let { metadata ->
                DetailRow("Intake source", metadata.source.name.lowercase(Locale.US).replace('_', ' '))
                metadata.confidence?.let { confidence ->
                    DetailRow("Inference confidence", "${(confidence * 100).roundToInt()}%")
                }
            }

            OutlinedTextField(
                value = draft.workflowName,
                onValueChange = onWorkflowNameChanged,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Workflow name") },
                singleLine = true,
                enabled = !isBusy,
            )
            OutlinedTextField(
                value = draft.taskStepsText,
                onValueChange = onTaskStepsChanged,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Task steps") },
                minLines = 3,
                enabled = !isBusy,
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
                    enabled = !isBusy,
                )
                OutlinedTextField(
                    value = draft.owner,
                    onValueChange = onOwnerChanged,
                    modifier = Modifier.weight(1f),
                    label = { Text("Owner") },
                    singleLine = true,
                    enabled = !isBusy,
                )
            }
            OutlinedTextField(
                value = draft.notes,
                onValueChange = onNotesChanged,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Capture notes") },
                minLines = 3,
                enabled = !isBusy,
            )

            Text(
                when {
                    exportMessage != null -> exportMessage
                    draft.isStructuredIntakeComplete -> "Structured intake is ready. You can export this bundle for testing or send it into the Android upload queue."
                    else -> "If intake is incomplete, Android will try to infer it from capture context and ask you to confirm anything uncertain."
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
                    enabled = !isBusy,
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
                    enabled = !isBusy,
                ) {
                    Text("Upload later")
                }
            }
            OutlinedButton(
                onClick = onExportForTesting,
                modifier = Modifier.fillMaxWidth(),
                enabled = !isBusy,
            ) {
                Text("Export for testing")
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

private fun statusLabel(uiState: CaptureSessionUiState): String {
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

private fun shareExportArtifact(
    context: Context,
    artifact: File,
) {
    if (!artifact.exists()) return
    val uri = FileProvider.getUriForFile(
        context,
        "${context.packageName}.fileprovider",
        artifact,
    )
    val intent = Intent(Intent.ACTION_SEND).apply {
        type = "application/zip"
        putExtra(Intent.EXTRA_STREAM, uri)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    context.startActivity(
        Intent.createChooser(intent, "Share capture export").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
    )
}

private val REQUIRED_CAPTURE_PERMISSIONS = arrayOf(
    Manifest.permission.CAMERA,
    Manifest.permission.RECORD_AUDIO,
)
