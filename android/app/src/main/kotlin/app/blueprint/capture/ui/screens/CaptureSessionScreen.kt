package app.blueprint.capture.ui.screens

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
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
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
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
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.LocationOn
import androidx.compose.material.icons.rounded.MonetizationOn
import androidx.compose.material.icons.rounded.NearMe
import androidx.compose.material.icons.rounded.Schedule
import androidx.compose.material.icons.rounded.Visibility
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.LocalLifecycleOwner
import app.blueprint.capture.data.capture.ARCoreCaptureManager
import app.blueprint.capture.data.capture.ARCoreSupportLevel
import app.blueprint.capture.data.capture.ARCoreSupport
import app.blueprint.capture.data.model.CaptureLaunch
import app.blueprint.capture.data.model.CapturePermissionTone
import app.blueprint.capture.ui.theme.BlueprintAccent
import app.blueprint.capture.ui.theme.BlueprintBlack
import app.blueprint.capture.ui.theme.BlueprintBorder
import app.blueprint.capture.ui.theme.BlueprintError
import app.blueprint.capture.ui.theme.BlueprintSectionLabel
import app.blueprint.capture.ui.theme.BlueprintSuccess
import app.blueprint.capture.ui.theme.BlueprintSurfaceRaised
import app.blueprint.capture.ui.theme.BlueprintTeal
import app.blueprint.capture.ui.theme.BlueprintTextMuted
import app.blueprint.capture.ui.theme.BlueprintTextPrimary
import app.blueprint.capture.ui.theme.BlueprintTextSecondary
import coil.compose.SubcomposeAsyncImage
import coil.compose.SubcomposeAsyncImageContent
import java.io.File
import java.util.Locale
import java.util.UUID
import kotlinx.coroutines.launch
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
    val hasDetailsSurface = capture.hasDetailsSurface
    val arcoreSupportLevel = remember(context) { ARCoreSupport.supportLevel(context) }
    val arcoreRuntimeAvailable = arcoreSupportLevel == ARCoreSupportLevel.SupportedInstalled

    var showRecorder by remember(capture.targetId, capture.jobId, capture.label) {
        mutableStateOf(!hasDetailsSurface)
    }
    var pendingRecorderLaunch by remember(capture.targetId, capture.jobId, capture.label) {
        mutableStateOf(false)
    }
    var permissionsGranted by remember { mutableStateOf(hasCapturePermissions(context)) }
    var cameraError by remember { mutableStateOf<String?>(null) }
    var videoCapture by remember { mutableStateOf<VideoCapture<Recorder>?>(null) }
    var recording by remember { mutableStateOf<Recording?>(null) }
    var usingArcoreRuntime by remember { mutableStateOf(false) }
    var isRecording by remember { mutableStateOf(false) }
    var elapsedSeconds by remember { mutableLongStateOf(0L) }
    var captureStartEpochMs by remember { mutableLongStateOf(0L) }
    val screenScope = rememberCoroutineScope()
    val arcoreManager = remember(context) { ARCoreCaptureManager(context) }
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
        if (permissionsGranted && pendingRecorderLaunch) {
            pendingRecorderLaunch = false
            showRecorder = true
        }
    }

    fun closeSession() {
        pendingRecorderLaunch = false
        if (reviewDraft != null) {
            viewModel.discardPendingCapture()
        } else {
            viewModel.resetSiteWorldWorkflowSession()
        }
        onClose()
    }

    fun openRecorderFromDetails() {
        if (capture.permissionTone == CapturePermissionTone.Blocked) return
        if (!permissionsGranted) {
            pendingRecorderLaunch = true
            permissionLauncher.launch(REQUIRED_CAPTURE_PERMISSIONS)
            return
        }
        showRecorder = true
    }

    BackHandler {
        when {
            isRecording || isBusy -> Unit
            reviewDraft != null -> closeSession()
            showRecorder && hasDetailsSurface -> {
                pendingRecorderLaunch = false
                showRecorder = false
            }

            else -> closeSession()
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
            viewModel.resetSiteWorldWorkflowSession()
            onClose()
        }
    }

    LaunchedEffect(uiState.exportSharePath) {
        val exportSharePath = uiState.exportSharePath ?: return@LaunchedEffect
        shareExportArtifact(context, File(exportSharePath))
        viewModel.consumeExportShare()
    }

    DisposableEffect(showRecorder, permissionsGranted, lifecycleOwner, previewView, usingArcoreRuntime) {
        if (!showRecorder || !permissionsGranted || usingArcoreRuntime) {
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

    DisposableEffect(arcoreManager) {
        onDispose {
            screenScope.launch {
                arcoreManager.close()
            }
        }
    }

    when {
        reviewDraft != null -> ReviewScreen(
            uiState = uiState,
            draft = reviewDraft,
            onClose = ::closeSession,
            onContinueWorkflow = viewModel::continueWorkflowFromReview,
            onWorkflowNameChanged = viewModel::updateWorkflowName,
            onTaskStepsChanged = viewModel::updateTaskSteps,
            onZoneChanged = viewModel::updateZone,
            onOwnerChanged = viewModel::updateOwner,
            onNotesChanged = viewModel::updateReviewNotes,
            onUploadNow = viewModel::queueUploadNow,
            onSaveForLater = viewModel::saveForLater,
            onExportForTesting = viewModel::exportForTesting,
        )

        showRecorder -> RecorderScreen(
            capture = capture,
            previewView = previewView,
            hasDetailsSurface = hasDetailsSurface,
            permissionsGranted = permissionsGranted,
            cameraError = cameraError,
            uiState = uiState,
            isBusy = isBusy,
            isRecording = isRecording,
            elapsedSeconds = elapsedSeconds,
            videoCapture = videoCapture,
            arcoreSupportLevel = arcoreSupportLevel,
            usingArcoreRuntime = usingArcoreRuntime,
            passBrief = viewModel.currentSiteWorldPassBrief,
            routePlan = viewModel.siteWorldRoutePlanSummary,
            requiredRules = viewModel.siteWorldRequiredRules,
            optionalRules = viewModel.siteWorldOptionalRules,
            highlightedAnchorTypes = viewModel.highlightedAnchorTypesForCurrentPass,
            onClose = {
                if (hasDetailsSurface) {
                    pendingRecorderLaunch = false
                    showRecorder = false
                } else {
                    closeSession()
                }
            },
            onRequestPermissions = {
                pendingRecorderLaunch = true
                permissionLauncher.launch(REQUIRED_CAPTURE_PERMISSIONS)
            },
            onUpdateSiteScale = viewModel::updateSiteWorldSiteScale,
            onToggleCriticalZone = viewModel::toggleCriticalZone,
            onMarkAnchor = viewModel::markSiteWorldAnchor,
            onMarkEntryLock = viewModel::markSiteWorldEntryLock,
            onMarkWeakSignal = viewModel::noteWeakSignalSegment,
            onStartRecording = {
                viewModel.beginWorkflowRecordingPass()
                captureStartEpochMs = System.currentTimeMillis()
                elapsedSeconds = 0L
                cameraError = null
                val outputDirectory = createRecordingOutputDirectory(context)
                viewModel.startIMUSampling(captureStartEpochMs)
                if (ARCoreSupport.isUsable(context)) {
                    usingArcoreRuntime = true
                    runCatching {
                        ProcessCameraProvider.getInstance(context).get().unbindAll()
                    }
                    screenScope.launch {
                        val started = arcoreManager.startCapture(
                            outputDirectory = outputDirectory,
                            captureStartEpochMs = captureStartEpochMs,
                        )
                        started.onSuccess {
                            isRecording = true
                        }.onFailure { error ->
                            usingArcoreRuntime = false
                            val (imuFile, motionSampleCount) = viewModel.stopIMUSamplingAndFlush(outputDirectory)
                            imuFile?.delete()
                            cameraError = error.message ?: "ARCore capture could not start on this device."
                        }
                    }
                    return@RecorderScreen
                }

                val captureUseCase = videoCapture
                if (captureUseCase == null) {
                    val (imuFile, _) = viewModel.stopIMUSamplingAndFlush(outputDirectory)
                    imuFile?.delete()
                    outputDirectory.deleteRecursively()
                    cameraError = "Android camera session is not ready."
                    return@RecorderScreen
                }
                val outputFile = outputDirectory.resolve("walkthrough.mp4")
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
                            val (imuSamplesFile, motionSampleCount) = viewModel.stopIMUSamplingAndFlush(outputDirectory)
                            if (event.hasError()) {
                                outputDirectory.deleteRecursively()
                                cameraError = event.cause?.message
                                    ?: "Recording failed before the file finalized."
                            } else {
                                viewModel.prepareRecordedCapture(
                                    capture = capture,
                                    recordingFile = outputFile,
                                    captureStartEpochMs = captureStartEpochMs,
                                    captureDurationMs = event.recordingStats.recordedDurationNanos / 1_000_000L,
                                    imuSamplesFile = imuSamplesFile,
                                    motionSampleCount = motionSampleCount,
                                )
                            }
                        }
                    }
                }
            },
            onStopRecording = {
                if (usingArcoreRuntime) {
                    screenScope.launch {
                        val result = arcoreManager.stopCapture()
                        usingArcoreRuntime = false
                        isRecording = false
                        result.onSuccess { artifacts ->
                            val (imuSamplesFile, motionSampleCount) =
                                viewModel.stopIMUSamplingAndFlush(artifacts.recordingFile.parentFile ?: context.cacheDir)
                            viewModel.prepareRecordedCapture(
                                capture = capture,
                                recordingFile = artifacts.recordingFile,
                                captureStartEpochMs = artifacts.captureStartEpochMs,
                                captureDurationMs = artifacts.durationMs,
                                imuSamplesFile = imuSamplesFile,
                                motionSampleCount = motionSampleCount,
                                arcoreEvidenceDirectory = artifacts.arcoreEvidenceDirectory,
                                coordinateFrameSessionId = artifacts.coordinateFrameSessionId,
                            )
                        }.onFailure { error ->
                            cameraError = error.message ?: "ARCore capture could not finish cleanly."
                        }
                    }
                } else {
                    recording?.stop()
                }
            },
        )

        else -> CaptureDetailsSurface(
            capture = capture,
            onClose = ::closeSession,
            onPrimaryAction = ::openRecorderFromDetails,
        )
    }
}

@Composable
private fun CaptureDetailsSurface(
    capture: CaptureLaunch,
    onClose: () -> Unit,
    onPrimaryAction: () -> Unit,
) {
    val checklist = capture.detailChecklist.ifEmpty {
        listOf(
            "Stay in common or approved areas only.",
            "Keep faces, screens, and paperwork out of frame.",
            "Call out restricted zones before you begin.",
            "Complete all floors before submitting.",
        )
    }
    val payoutText = capture.payoutText ?: capture.quotedPayoutCents?.let(::formatCompactPayout) ?: "$30"
    val actionEnabled = capture.permissionTone != CapturePermissionTone.Blocked
    val actionLabel = capture.detailActionLabel
    val actionTint = if (actionEnabled) BlueprintTextPrimary.copy(alpha = 0.94f) else BlueprintTextMuted.copy(alpha = 0.72f)

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(BlueprintBlack),
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState()),
        ) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(372.dp),
            ) {
                CaptureHeroImage(
                    imageUrl = capture.imageUrl,
                    categoryLabel = capture.categoryLabel ?: "CAPTURE",
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(top = 10.dp)
                        .clip(RoundedCornerShape(topStart = 36.dp, topEnd = 36.dp)),
                    accent = capture.permissionColor,
                )

                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(top = 10.dp)
                        .background(
                            brush = Brush.verticalGradient(
                                colors = listOf(
                                    Color.Transparent,
                                    Color.Transparent,
                                    BlueprintBlack.copy(alpha = 0.18f),
                                    BlueprintBlack.copy(alpha = 0.88f),
                                ),
                            ),
                        ),
                )

                Row(
                    modifier = Modifier
                        .statusBarsPadding()
                        .padding(start = 20.dp, top = 18.dp),
                ) {
                    Row(
                        modifier = Modifier
                            .clip(RoundedCornerShape(32.dp))
                            .background(Color(0xCC3A383A))
                            .clickable(onClick = onClose)
                            .padding(horizontal = 18.dp, vertical = 12.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.KeyboardArrowDown,
                            contentDescription = null,
                            tint = BlueprintTextPrimary,
                            modifier = Modifier.size(22.dp),
                        )
                        Text(
                            text = "Close",
                            style = TextStyle(
                                color = BlueprintTextPrimary,
                                fontSize = 17.sp,
                                lineHeight = 21.sp,
                                fontWeight = FontWeight.SemiBold,
                            ),
                        )
                    }
                }
            }

            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp)
                    .padding(top = 18.dp, bottom = 172.dp),
                verticalArrangement = Arrangement.spacedBy(24.dp),
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(
                        text = (capture.categoryLabel ?: "Capture").uppercase(Locale.US),
                        style = TextStyle(
                            color = BlueprintSectionLabel,
                            fontSize = 13.sp,
                            lineHeight = 16.sp,
                            fontWeight = FontWeight.ExtraBold,
                            letterSpacing = 2.4.sp,
                        ),
                    )
                    Text(
                        text = capture.label,
                        style = TextStyle(
                            color = BlueprintTextPrimary,
                            fontSize = 29.sp,
                            lineHeight = 34.sp,
                            fontWeight = FontWeight.ExtraBold,
                            letterSpacing = (-0.8).sp,
                        ),
                    )
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.LocationOn,
                            contentDescription = null,
                            tint = BlueprintTextMuted,
                            modifier = Modifier.size(15.dp),
                        )
                        Text(
                            text = capture.addressText ?: capture.label,
                            style = TextStyle(
                                color = BlueprintTextMuted,
                                fontSize = 16.sp,
                                lineHeight = 20.sp,
                                fontWeight = FontWeight.Medium,
                            ),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(18.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        DetailMetric(
                            icon = Icons.Rounded.MonetizationOn,
                            iconTint = BlueprintSuccess,
                            text = payoutText,
                        )
                        capture.distanceText?.let { distance ->
                            DetailMetric(
                                icon = Icons.Rounded.NearMe,
                                iconTint = BlueprintTextSecondary,
                                text = distance,
                            )
                        }
                        capture.estimatedMinutes?.let { minutes ->
                            DetailMetric(
                                icon = Icons.Rounded.Schedule,
                                iconTint = BlueprintTextSecondary,
                                text = "$minutes min",
                            )
                        }
                    }
                }

                PayoutBanner(payoutText = payoutText)

                Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    Text(
                        text = "CAPTURE REQUIREMENTS",
                        style = TextStyle(
                            color = BlueprintSectionLabel,
                            fontSize = 13.sp,
                            lineHeight = 16.sp,
                            fontWeight = FontWeight.ExtraBold,
                            letterSpacing = 2.7.sp,
                        ),
                    )
                    RequirementsCard(checklist = checklist)
                }
            }
        }

        Box(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .background(
                    brush = Brush.verticalGradient(
                        colors = listOf(
                            Color.Transparent,
                            BlueprintBlack.copy(alpha = 0.84f),
                            BlueprintBlack,
                        ),
                    ),
                )
                .navigationBarsPadding()
                .padding(horizontal = 20.dp, vertical = 16.dp),
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(22.dp))
                    .background(if (actionEnabled) Color(0xFF1D1D20) else Color(0xFF17181A))
                    .border(1.dp, BlueprintBorder, RoundedCornerShape(22.dp))
                    .clickable(enabled = actionEnabled, onClick = onPrimaryAction)
                    .padding(horizontal = 18.dp, vertical = 18.dp),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    imageVector = Icons.Rounded.Visibility,
                    contentDescription = null,
                    tint = actionTint,
                    modifier = Modifier.size(24.dp),
                )
                Text(
                    text = actionLabel,
                    modifier = Modifier.padding(start = 12.dp),
                    style = TextStyle(
                        color = actionTint,
                        fontSize = 18.sp,
                        lineHeight = 22.sp,
                        fontWeight = FontWeight.SemiBold,
                        letterSpacing = (-0.2).sp,
                    ),
                )
            }
        }
    }
}

@Composable
private fun CaptureHeroImage(
    imageUrl: String?,
    categoryLabel: String,
    modifier: Modifier = Modifier,
    accent: Color,
) {
    val fallbackBrush = Brush.linearGradient(
        colors = listOf(
            accent.copy(alpha = 0.32f),
            BlueprintSurfaceRaised,
            BlueprintBlack,
        ),
    )

    if (imageUrl.isNullOrBlank()) {
        HeroFallback(categoryLabel = categoryLabel, brush = fallbackBrush, modifier = modifier)
        return
    }

    SubcomposeAsyncImage(
        model = imageUrl,
        contentDescription = null,
        modifier = modifier,
        contentScale = ContentScale.Crop,
        loading = {
            HeroFallback(categoryLabel = categoryLabel, brush = fallbackBrush, modifier = Modifier.fillMaxSize())
        },
        error = {
            HeroFallback(categoryLabel = categoryLabel, brush = fallbackBrush, modifier = Modifier.fillMaxSize())
        },
        success = {
            SubcomposeAsyncImageContent()
        },
    )
}

@Composable
private fun HeroFallback(
    categoryLabel: String,
    brush: Brush,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier = modifier.background(brush),
        contentAlignment = Alignment.BottomStart,
    ) {
        Text(
            text = categoryLabel.uppercase(Locale.US),
            modifier = Modifier.padding(start = 22.dp, bottom = 20.dp),
            style = TextStyle(
                color = BlueprintTextPrimary.copy(alpha = 0.16f),
                fontSize = 42.sp,
                lineHeight = 46.sp,
                fontWeight = FontWeight.ExtraBold,
                letterSpacing = (-0.8).sp,
            ),
        )
    }
}

@Composable
private fun DetailMetric(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    iconTint: Color,
    text: String,
) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = iconTint,
            modifier = Modifier.size(20.dp),
        )
        Text(
            text = text,
            style = TextStyle(
                color = BlueprintTextPrimary.copy(alpha = 0.95f),
                fontSize = 16.sp,
                lineHeight = 20.sp,
                fontWeight = FontWeight.Bold,
            ),
        )
    }
}

@Composable
private fun PayoutBanner(
    payoutText: String,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(Color(0xFF171717))
            .border(1.dp, BlueprintSuccess.copy(alpha = 0.22f), RoundedCornerShape(18.dp)),
    ) {
        Box(
            modifier = Modifier
                .padding(vertical = 14.dp)
                .size(width = 4.dp, height = 58.dp)
                .background(BlueprintSuccess, RoundedCornerShape(3.dp)),
        )

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                modifier = Modifier
                    .size(36.dp)
                    .clip(CircleShape)
                    .background(BlueprintSuccess.copy(alpha = 0.18f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = Icons.Rounded.MonetizationOn,
                    contentDescription = null,
                    tint = BlueprintSuccess,
                    modifier = Modifier.size(22.dp),
                )
            }
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                Text(
                    text = "Completing this capture earns $payoutText",
                    style = TextStyle(
                        color = BlueprintTextPrimary,
                        fontSize = 18.sp,
                        lineHeight = 22.sp,
                        fontWeight = FontWeight.SemiBold,
                        letterSpacing = (-0.2).sp,
                    ),
                )
                Text(
                    text = "Paid after approval review · Usually 3–5 days",
                    style = TextStyle(
                        color = BlueprintTextMuted,
                        fontSize = 14.sp,
                        lineHeight = 18.sp,
                        fontWeight = FontWeight.Medium,
                    ),
                )
            }
        }
    }
}

@Composable
private fun RequirementsCard(
    checklist: List<String>,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(24.dp))
            .background(Color(0xFF171717))
            .border(1.dp, BlueprintBorder, RoundedCornerShape(24.dp)),
    ) {
        checklist.forEachIndexed { index, item ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 18.dp, vertical = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.Top,
            ) {
                Box(
                    modifier = Modifier
                        .padding(top = 6.dp)
                        .size(12.dp)
                        .clip(CircleShape)
                        .background(BlueprintTeal.copy(alpha = 0.95f)),
                )
                Text(
                    text = item,
                    modifier = Modifier.weight(1f),
                    style = TextStyle(
                        color = BlueprintTextSecondary,
                        fontSize = 16.sp,
                        lineHeight = 22.sp,
                        fontWeight = FontWeight.Medium,
                    ),
                )
            }
            if (index < checklist.lastIndex) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(start = 42.dp, end = 18.dp)
                        .height(1.dp)
                        .background(BlueprintBorder),
                )
            }
        }
    }
}

@Composable
private fun RecorderScreen(
    capture: CaptureLaunch,
    previewView: PreviewView,
    hasDetailsSurface: Boolean,
    permissionsGranted: Boolean,
    cameraError: String?,
    uiState: CaptureSessionUiState,
    isBusy: Boolean,
    isRecording: Boolean,
    elapsedSeconds: Long,
    videoCapture: VideoCapture<Recorder>?,
    arcoreSupportLevel: ARCoreSupportLevel,
    usingArcoreRuntime: Boolean,
    passBrief: SiteWorldPassBrief,
    routePlan: List<String>,
    requiredRules: List<String>,
    optionalRules: List<String>,
    highlightedAnchorTypes: Set<SiteWorldAnchorType>,
    onClose: () -> Unit,
    onRequestPermissions: () -> Unit,
    onUpdateSiteScale: (SiteWorldSiteScale) -> Unit,
    onToggleCriticalZone: (SiteWorldAnchorType) -> Unit,
    onMarkAnchor: (SiteWorldAnchorType) -> Unit,
    onMarkEntryLock: () -> Unit,
    onMarkWeakSignal: () -> Unit,
    onStartRecording: () -> Unit,
    onStopRecording: () -> Unit,
) {
    val workflowState = uiState.siteWorldRecordingState
    val livePrompt = remember(
        workflowState,
        passBrief,
        uiState.siteWorldCriticalZones,
    ) {
        when {
            !workflowState.entryLocked ->
                "Stand at the main entry point. Hold still for 3 seconds. Slowly pan left, center, right. Keep the door frame, floor edge, and nearby wall in view."
            workflowState.weakSignalEvents > 0 ->
                "Weak segment flagged. Reacquire fixed structure before moving deeper into the site."
            passBrief.role == "revisit" ->
                "Turn back and reacquire the last checkpoint from the reverse direction before leaving this zone."
            passBrief.role == "loop_closure" ->
                "Return to your start anchor. Match the original entrance view as closely as practical, then hold for 3 seconds."
            passBrief.role == "critical_zone_revisit" ->
                "Capture the static boundary, approach path, and exit path. Revisit once from the opposite direction."
            else ->
                "At the next doorway or intersection, stop at the threshold. Show left frame, center opening, right frame. Then continue."
        }
    }
    val liveSupportPrompts = remember(workflowState, uiState.siteWorldCriticalZones) {
        buildList {
            add("Prefer fixed building structure. Avoid following people, carts, pallets, or temporary clutter.")
            if (uiState.siteWorldCriticalZones.isNotEmpty()) {
                val remaining = uiState.siteWorldCriticalZones.subtract(workflowState.markedAnchors.toSet())
                if (remaining.isNotEmpty()) {
                    add("Still need critical zones: ${remaining.joinToString(", ") { it.label }}.")
                }
            }
        }.take(2)
    }
    val checkpointCount = workflowState.markedAnchors.count {
        it in setOf(
            SiteWorldAnchorType.Doorway,
            SiteWorldAnchorType.Intersection,
            SiteWorldAnchorType.DockTurn,
            SiteWorldAnchorType.HandoffPoint,
            SiteWorldAnchorType.FloorTransition,
            SiteWorldAnchorType.RestrictedBoundary,
        )
    }
    val arcoreStatusMessage = remember(arcoreSupportLevel, usingArcoreRuntime) {
        when {
            usingArcoreRuntime ->
                "ARCore recording is active. The on-screen camera preview is paused until a Camera2 SharedCamera pipeline is wired. walkthrough.mp4 and arcore/* evidence are still being recorded."
            arcoreSupportLevel == ARCoreSupportLevel.SupportedInstalled ->
                "Preview is live only during preflight. When recording starts, CameraX hands off to ARCore and the preview pauses because SharedCamera live preview is not wired yet."
            arcoreSupportLevel == ARCoreSupportLevel.SupportedNeedsInstall ->
                "This device needs the current ARCore service installed before ARCore-first capture can run."
            else -> null
        }
    }
    val canStartRecording = permissionsGranted && !isBusy && (videoCapture != null || arcoreSupportLevel == ARCoreSupportLevel.SupportedInstalled)

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(BlueprintBlack),
    ) {
        AndroidView(
            factory = { previewView },
            modifier = Modifier.fillMaxSize(),
        )

        if (usingArcoreRuntime) {
            Box(
                modifier = Modifier
                    .matchParentSize()
                    .background(BlueprintBlack.copy(alpha = 0.56f)),
                contentAlignment = Alignment.Center,
            ) {
                Column(
                    modifier = Modifier
                        .padding(horizontal = 24.dp)
                        .clip(RoundedCornerShape(24.dp))
                        .background(BlueprintSurfaceRaised.copy(alpha = 0.94f))
                        .padding(horizontal = 20.dp, vertical = 18.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Text(
                        text = "ARCore capture running",
                        style = TextStyle(
                            color = BlueprintTextPrimary,
                            fontSize = 18.sp,
                            lineHeight = 22.sp,
                            fontWeight = FontWeight.SemiBold,
                        ),
                    )
                    Text(
                        text = "Live camera preview is unavailable in this runtime until SharedCamera is integrated. Recording continues in the background.",
                        style = TextStyle(
                            color = BlueprintTextMuted,
                            fontSize = 14.sp,
                            lineHeight = 19.sp,
                            fontWeight = FontWeight.Medium,
                        ),
                    )
                }
            }
        }

        Box(
            modifier = Modifier
                .matchParentSize()
                .background(
                    brush = Brush.verticalGradient(
                        colors = listOf(
                            BlueprintBlack.copy(alpha = 0.42f),
                            Color.Transparent,
                            BlueprintBlack.copy(alpha = 0.30f),
                            BlueprintBlack.copy(alpha = 0.76f),
                        ),
                    ),
                ),
        )

        // Floating recording badges — shown when actively recording
        if (isRecording) {
            Row(
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .statusBarsPadding()
                    .padding(top = 14.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                RecordingIndicatorBadge()
                TimerBadge(elapsedSeconds = elapsedSeconds)
            }
        }

        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .navigationBarsPadding()
                .padding(horizontal = 20.dp, vertical = 16.dp),
            verticalArrangement = Arrangement.SpaceBetween,
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        text = if (hasDetailsSurface) capture.label else "Phone Capture",
                        style = TextStyle(
                            color = BlueprintTextPrimary,
                            fontSize = 20.sp,
                            lineHeight = 24.sp,
                            fontWeight = FontWeight.SemiBold,
                            letterSpacing = (-0.2).sp,
                        ),
                    )
                    if (!isRecording && !isBusy) {
                        OutlinedButton(onClick = onClose) {
                            Text(if (hasDetailsSurface) "Back" else "Close")
                        }
                    }
                }

                SurfaceCard {
                    Text(capture.label)
                    Text(
                        when {
                            !permissionsGranted -> "Camera and microphone access are required before Android can record the walkthrough."
                            usingArcoreRuntime -> "ARCore recording is running. Keep walking the planned pass even though the preview is paused."
                            isRecording -> livePrompt
                            else -> "Plan the route, then start the next pass when you are ready."
                        },
                        color = BlueprintTextMuted,
                    )
                }

                arcoreStatusMessage?.let { message ->
                    SurfaceCard {
                        Text("ARCore runtime")
                        Text(message, color = BlueprintTextMuted)
                    }
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
                    }
                }

                uiState.exportMessage?.let { message ->
                    SurfaceCard {
                        Text("Export ready")
                        Text(message, color = BlueprintTextMuted)
                    }
                }

                if (!isRecording) {
                    SiteWorldPreflightCard(
                        siteScale = uiState.siteWorldSiteScale,
                        criticalZoneOptions = listOf(
                            SiteWorldAnchorType.DockTurn,
                            SiteWorldAnchorType.HandoffPoint,
                            SiteWorldAnchorType.ControlPanel,
                            SiteWorldAnchorType.FloorTransition,
                            SiteWorldAnchorType.RestrictedBoundary,
                        ),
                        selectedCriticalZones = uiState.siteWorldCriticalZones,
                        routePlan = routePlan,
                        requiredRules = requiredRules,
                        optionalRules = optionalRules,
                        passBrief = passBrief,
                        onUpdateSiteScale = onUpdateSiteScale,
                        onToggleCriticalZone = onToggleCriticalZone,
                    )
                } else {
                    SiteWorldLiveGuidanceCard(
                        passBrief = passBrief,
                        checkpointCount = checkpointCount,
                        entryLocked = workflowState.entryLocked,
                        weakSignalEvents = workflowState.weakSignalEvents,
                        criticalZoneCount = uiState.siteWorldCriticalZones.size,
                        matchedCriticalZones = uiState.siteWorldCriticalZones.intersect(workflowState.markedAnchors.toSet()).size,
                        prompt = livePrompt,
                        supportPrompts = liveSupportPrompts,
                    )
                    SiteWorldAnchorToolCard(
                        highlightedAnchorTypes = highlightedAnchorTypes,
                        onMarkAnchor = onMarkAnchor,
                        onMarkEntryLock = onMarkEntryLock,
                        onMarkWeakSignal = onMarkWeakSignal,
                    )
                }
            }

            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                SessionStatusCard(
                    permissionsGranted = permissionsGranted,
                    isRecording = isRecording,
                    elapsedSeconds = elapsedSeconds,
                    uiState = uiState,
                    runtimeStatus = when {
                        usingArcoreRuntime -> "ARCore capture active"
                        arcoreSupportLevel == ARCoreSupportLevel.SupportedInstalled -> "ARCore preflight preview"
                        arcoreSupportLevel == ARCoreSupportLevel.SupportedNeedsInstall -> "ARCore install required"
                        else -> "CameraX video preview"
                    },
                )

                when {
                    !permissionsGranted -> {
                        Button(
                            onClick = onRequestPermissions,
                            modifier = Modifier.fillMaxWidth(),
                            colors = ButtonDefaults.buttonColors(
                                containerColor = BlueprintAccent,
                                contentColor = BlueprintBlack,
                            ),
                        ) {
                            Text("Grant camera + microphone access")
                        }
                    }

                    !isRecording -> {
                        Button(
                            onClick = onStartRecording,
                            enabled = canStartRecording,
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
                            onClick = onStopRecording,
                            enabled = !isBusy,
                            modifier = Modifier.fillMaxWidth(),
                            colors = ButtonDefaults.buttonColors(
                                containerColor = BlueprintAccent,
                                contentColor = BlueprintBlack,
                            ),
                        ) {
                            Text("Finish pass and review")
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ReviewScreen(
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
                ReviewSummaryRow("Duration", formatDurationMs(draft.captureDurationMs))
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

@Composable
private fun SiteWorldPreflightCard(
    siteScale: SiteWorldSiteScale,
    criticalZoneOptions: List<SiteWorldAnchorType>,
    selectedCriticalZones: Set<SiteWorldAnchorType>,
    routePlan: List<String>,
    requiredRules: List<String>,
    optionalRules: List<String>,
    passBrief: SiteWorldPassBrief,
    onUpdateSiteScale: (SiteWorldSiteScale) -> Unit,
    onToggleCriticalZone: (SiteWorldAnchorType) -> Unit,
) {
    SurfaceCard {
        Text("Site World Candidate")
        Text(passBrief.title, color = BlueprintTeal)
        Text(passBrief.summary, color = BlueprintTextMuted)

        Text("Site size", color = BlueprintSectionLabel, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf(
                SiteWorldSiteScale.SmallSimple,
                SiteWorldSiteScale.Medium,
                SiteWorldSiteScale.MultiZone,
            ).forEach { scale ->
                FilterChip(
                    label = when (scale) {
                        SiteWorldSiteScale.SmallSimple -> "Small"
                        SiteWorldSiteScale.Medium -> "Medium"
                        SiteWorldSiteScale.MultiZone -> "Multi-zone"
                    },
                    selected = siteScale == scale,
                    onClick = { onUpdateSiteScale(scale) },
                )
            }
        }

        Text("Critical zones", color = BlueprintSectionLabel, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            criticalZoneOptions.chunked(3).forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    row.forEach { anchor ->
                        FilterChip(
                            label = anchor.label,
                            selected = selectedCriticalZones.contains(anchor),
                            onClick = { onToggleCriticalZone(anchor) },
                        )
                    }
                }
            }
        }

        SiteWorldListSection("Route plan", routePlan)
        SiteWorldListSection("Required", requiredRules)
        SiteWorldListSection("Optional", optionalRules)
        SiteWorldListSection("Operator prompts", passBrief.exactPrompts.take(2).map { "\"$it\"" })
    }
}

@Composable
private fun SiteWorldLiveGuidanceCard(
    passBrief: SiteWorldPassBrief,
    checkpointCount: Int,
    entryLocked: Boolean,
    weakSignalEvents: Int,
    criticalZoneCount: Int,
    matchedCriticalZones: Int,
    prompt: String,
    supportPrompts: List<String>,
) {
    SurfaceCard {
        Text(passBrief.title)
        Text(passBrief.summary, color = BlueprintTextMuted)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterChip(label = if (entryLocked) "Entry locked" else "Entry lock pending", selected = entryLocked, onClick = {})
            FilterChip(
                label = "Checkpoints $checkpointCount/${passBrief.requiredCheckpointTarget}",
                selected = checkpointCount >= passBrief.requiredCheckpointTarget,
                onClick = {},
            )
            if (criticalZoneCount > 0) {
                FilterChip(
                    label = "Critical $matchedCriticalZones/$criticalZoneCount",
                    selected = matchedCriticalZones >= criticalZoneCount,
                    onClick = {},
                )
            }
            if (weakSignalEvents > 0) {
                FilterChip(label = "Weak $weakSignalEvents", selected = true, onClick = {})
            }
        }
        Text(prompt, color = BlueprintTextPrimary, fontWeight = FontWeight.SemiBold)
        supportPrompts.forEach { item ->
            Text(item, color = BlueprintTextMuted, fontSize = 13.sp)
        }
    }
}

@Composable
private fun SiteWorldAnchorToolCard(
    highlightedAnchorTypes: Set<SiteWorldAnchorType>,
    onMarkAnchor: (SiteWorldAnchorType) -> Unit,
    onMarkEntryLock: () -> Unit,
    onMarkWeakSignal: () -> Unit,
) {
    SurfaceCard {
        Text("Checkpoints")
        Text("Mark anchors to improve overlap, revisits, and loop closure.", color = BlueprintTextMuted)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterChip(label = "Lock entry", selected = true, onClick = onMarkEntryLock)
            FilterChip(label = "Weak segment", selected = false, onClick = onMarkWeakSignal)
        }
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf(
                SiteWorldAnchorType.Doorway,
                SiteWorldAnchorType.Intersection,
                SiteWorldAnchorType.DockTurn,
                SiteWorldAnchorType.HandoffPoint,
                SiteWorldAnchorType.ControlPanel,
                SiteWorldAnchorType.FloorTransition,
                SiteWorldAnchorType.RestrictedBoundary,
                SiteWorldAnchorType.ExitPoint,
            ).chunked(3).forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    row.forEach { anchor ->
                        FilterChip(
                            label = anchor.label,
                            selected = highlightedAnchorTypes.contains(anchor),
                            onClick = { onMarkAnchor(anchor) },
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun SiteWorldReviewCard(review: SiteWorldPassReview) {
    SurfaceCard {
        Text(review.title)
        Text(review.summary, color = BlueprintTextMuted)
        Text(
            text = "${review.completedRequiredPasses}/${review.totalRequiredPasses} passes complete · ${review.score}",
            color = when (review.tone) {
                SiteWorldReviewTone.Ready -> BlueprintSuccess
                SiteWorldReviewTone.Caution -> BlueprintAccent
                SiteWorldReviewTone.ActionRequired -> BlueprintError
            },
            fontWeight = FontWeight.SemiBold,
        )
        if (review.completedItems.isNotEmpty()) {
            SiteWorldListSection("Completed", review.completedItems)
        }
        if (review.missingItems.isNotEmpty()) {
            SiteWorldListSection("Still needed", review.missingItems)
        }
        review.weakSignalSummary?.let {
            Text(it.replace("weak_signal_events:", "Weak signal events: "), color = BlueprintTextMuted, fontSize = 13.sp)
        }
    }
}

@Composable
private fun SiteWorldListSection(title: String, items: List<String>) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(title, color = BlueprintSectionLabel, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
        items.forEach { item ->
            Text("• $item", color = BlueprintTextSecondary, fontSize = 13.sp, lineHeight = 18.sp)
        }
    }
}

@Composable
private fun FilterChip(
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
) {
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(999.dp))
            .background(if (selected) BlueprintTeal.copy(alpha = 0.28f) else Color(0xFF1A1A1A))
            .border(1.dp, if (selected) BlueprintTeal.copy(alpha = 0.5f) else BlueprintBorder, RoundedCornerShape(999.dp))
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 8.dp),
    ) {
        Text(
            text = label,
            color = BlueprintTextPrimary,
            fontSize = 13.sp,
            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Medium,
        )
    }
}

@Composable
private fun SessionStatusCard(
    permissionsGranted: Boolean,
    isRecording: Boolean,
    elapsedSeconds: Long,
    uiState: CaptureSessionUiState,
    runtimeStatus: String,
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
                Text(runtimeStatus, color = BlueprintTextMuted)
            }
        }

        Text(statusLabel(uiState), color = BlueprintTextMuted)

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
private fun CaptureStatCard(label: String, value: String, modifier: Modifier = Modifier) {
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

private enum class PostCaptureTone { Good, Warning, Neutral }

@Composable
private fun PostCaptureReadinessRow(label: String, value: String, tone: PostCaptureTone) {
    val valueColor = when (tone) {
        PostCaptureTone.Good -> BlueprintSuccess
        PostCaptureTone.Warning -> BlueprintAccent
        PostCaptureTone.Neutral -> BlueprintTextPrimary
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
private fun PostCaptureReadinessDivider() {
    Box(modifier = Modifier.fillMaxWidth().height(1.dp).background(BlueprintBorder))
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

private val CaptureLaunch.hasDetailsSurface: Boolean
    get() = !autoStartRecorder && targetId != null && (
        !imageUrl.isNullOrBlank() ||
            !categoryLabel.isNullOrBlank() ||
            !addressText.isNullOrBlank() ||
            detailChecklist.isNotEmpty()
        )

private val CaptureLaunch.permissionColor: Color
    get() = when (permissionTone) {
        CapturePermissionTone.Approved -> BlueprintSuccess
        CapturePermissionTone.Review -> BlueprintTeal
        CapturePermissionTone.Permission -> Color(0xFFE8B04B)
        CapturePermissionTone.Blocked -> BlueprintError
    }

private val CaptureLaunch.detailActionLabel: String
    get() = when (permissionTone) {
        CapturePermissionTone.Approved -> "Start Capture"
        CapturePermissionTone.Review -> "Start Capture"
        CapturePermissionTone.Permission -> "Check Access Before Starting"
        CapturePermissionTone.Blocked -> "Capture Not Allowed"
    }

private fun hasCapturePermissions(context: Context): Boolean {
    return REQUIRED_CAPTURE_PERMISSIONS.all { permission ->
        ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED
    }
}

private fun createRecordingFile(context: Context): File {
    return createRecordingOutputDirectory(context).resolve("walkthrough.mp4")
}

private fun createRecordingOutputDirectory(context: Context): File {
    return context.cacheDir.resolve("recordings")
        .also { it.mkdirs() }
        .resolve(UUID.randomUUID().toString())
        .also { it.mkdirs() }
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

private fun formatCompactPayout(cents: Int): String {
    val dollars = cents / 100
    val remainder = cents % 100
    return if (remainder == 0) {
        "$$dollars"
    } else {
        "$$dollars.${remainder.toString().padStart(2, '0')}"
    }
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

@Composable
private fun RecordingIndicatorBadge() {
    val infiniteTransition = rememberInfiniteTransition(label = "rec-pulse")
    val alpha by infiniteTransition.animateFloat(
        initialValue = 1f,
        targetValue = 0.25f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 700, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "rec-alpha",
    )
    Row(
        modifier = Modifier
            .clip(RoundedCornerShape(999.dp))
            .background(Color(0xCC1A1A1C))
            .border(1.dp, BlueprintError.copy(alpha = 0.35f), RoundedCornerShape(999.dp))
            .padding(horizontal = 12.dp, vertical = 7.dp),
        horizontalArrangement = Arrangement.spacedBy(7.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(8.dp)
                .clip(CircleShape)
                .background(BlueprintError.copy(alpha = alpha)),
        )
        Text(
            text = "REC",
            color = BlueprintTextPrimary,
            fontSize = 13.sp,
            fontWeight = FontWeight.Bold,
            letterSpacing = 1.2.sp,
        )
    }
}

@Composable
private fun TimerBadge(elapsedSeconds: Long) {
    val minutes = elapsedSeconds / 60
    val seconds = elapsedSeconds % 60
    val label = "%d:%02d".format(minutes, seconds)
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(999.dp))
            .background(Color(0xCC1A1A1C))
            .border(1.dp, Color.White.copy(alpha = 0.12f), RoundedCornerShape(999.dp))
            .padding(horizontal = 12.dp, vertical = 7.dp),
    ) {
        Text(
            text = label,
            color = BlueprintTextPrimary,
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold,
            letterSpacing = 0.5.sp,
        )
    }
}

private val REQUIRED_CAPTURE_PERMISSIONS = arrayOf(
    Manifest.permission.CAMERA,
    Manifest.permission.RECORD_AUDIO,
)
