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
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
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
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.LocationOn
import androidx.compose.material.icons.rounded.MonetizationOn
import androidx.compose.material.icons.rounded.NearMe
import androidx.compose.material.icons.rounded.Schedule
import androidx.compose.material.icons.rounded.Visibility
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
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
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.LocalLifecycleOwner
import app.blueprint.capture.data.capture.ARCoreCaptureManager
import app.blueprint.capture.data.capture.ARCoreSupport
import app.blueprint.capture.data.model.CaptureLaunch
import app.blueprint.capture.data.model.CapturePermissionTone
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
        reviewDraft != null -> PostCaptureReviewSurface(
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

        showRecorder -> CaptureRecorderHost(
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
                    return@CaptureRecorderHost
                }

                val captureUseCase = videoCapture
                if (captureUseCase == null) {
                    val (imuFile, _) = viewModel.stopIMUSamplingAndFlush(outputDirectory)
                    imuFile?.delete()
                    outputDirectory.deleteRecursively()
                    cameraError = "Android camera session is not ready."
                    return@CaptureRecorderHost
                }
                val outputFile = outputDirectory.resolve("walkthrough.mp4")
                var pendingRecording = captureUseCase.output.prepareRecording(
                    context,
                    FileOutputOptions.Builder(outputFile).build(),
                )
                // CapturePermissionGate requests RECORD_AUDIO before this
                // screen renders; re-checked explicitly at the call site. If
                // it were ever revoked mid-session, keep the video evidence
                // and record without audio instead of failing the capture.
                if (androidx.core.content.ContextCompat.checkSelfPermission(
                        context,
                        Manifest.permission.RECORD_AUDIO,
                    ) == PackageManager.PERMISSION_GRANTED
                ) {
                    pendingRecording = pendingRecording.withAudioEnabled()
                }

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
    val payoutDisplay = capture.payoutDisplay
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
                            iconTint = if (payoutDisplay.hasQuotedPayout) BlueprintSuccess else BlueprintTextSecondary,
                            text = payoutDisplay.metricText,
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

                PayoutBanner(display = payoutDisplay)

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
    display: CapturePayoutDisplay,
) {
    val accent = if (display.hasQuotedPayout) BlueprintSuccess else BlueprintTeal
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(Color(0xFF171717))
            .border(1.dp, accent.copy(alpha = 0.22f), RoundedCornerShape(18.dp)),
    ) {
        Box(
            modifier = Modifier
                .padding(vertical = 14.dp)
                .size(width = 4.dp, height = 58.dp)
                .background(accent, RoundedCornerShape(3.dp)),
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
                    .background(accent.copy(alpha = 0.18f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = if (display.hasQuotedPayout) Icons.Rounded.MonetizationOn else Icons.Rounded.Visibility,
                    contentDescription = null,
                    tint = accent,
                    modifier = Modifier.size(22.dp),
                )
            }
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                Text(
                    text = display.bannerTitle,
                    style = TextStyle(
                        color = BlueprintTextPrimary,
                        fontSize = 18.sp,
                        lineHeight = 22.sp,
                        fontWeight = FontWeight.SemiBold,
                        letterSpacing = (-0.2).sp,
                    ),
                )
                Text(
                    text = display.bannerBody,
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

private fun createRecordingOutputDirectory(context: Context): File {
    return context.cacheDir.resolve("recordings")
        .also { it.mkdirs() }
        .resolve(UUID.randomUUID().toString())
        .also { it.mkdirs() }
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
