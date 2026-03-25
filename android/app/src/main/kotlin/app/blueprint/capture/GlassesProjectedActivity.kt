package app.blueprint.capture

import android.Manifest
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.viewModels
import androidx.camera.video.Recording
import androidx.camera.video.VideoRecordEvent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.lifecycleScope
import androidx.xr.projected.ProjectedDeviceController
import androidx.xr.projected.ProjectedDisplayController
import androidx.xr.projected.experimental.ExperimentalProjectedApi
import androidx.xr.projected.permissions.ProjectedPermissionsRequestParams
import androidx.xr.projected.permissions.ProjectedPermissionsResultContract
import app.blueprint.capture.data.glasses.GlassesCapabilities
import app.blueprint.capture.data.glasses.voice.AndroidOnDeviceSpeechInput
import app.blueprint.capture.data.glasses.voice.AndroidVoiceOutput
import app.blueprint.capture.data.glasses.voice.UnavailableGeminiLiveConnector
import app.blueprint.capture.data.glasses.voice.VoiceSessionOrchestrator
import app.blueprint.capture.data.glasses.voice.VoiceSessionState
import app.blueprint.capture.data.model.CaptureLaunch
import app.blueprint.capture.data.glasses.androidxr.AndroidXrProjectedCaptureManager
import app.blueprint.capture.data.glasses.androidxr.AndroidXrProjectedLaunch
import app.blueprint.capture.ui.screens.AndroidXrViewModel
import app.blueprint.capture.ui.theme.BlueprintTheme
import dagger.hilt.android.AndroidEntryPoint
import java.io.File
import kotlinx.coroutines.launch

@AndroidEntryPoint
@OptIn(ExperimentalProjectedApi::class)
class GlassesProjectedActivity : ComponentActivity() {
    private val viewModel: AndroidXrViewModel by viewModels()

    private var displayController: ProjectedDisplayController? = null
    private var captureManager: AndroidXrProjectedCaptureManager? = null
    private var voiceSessionOrchestrator: VoiceSessionOrchestrator? = null
    private var activeRecording: Recording? = null

    private var captureLaunch by mutableStateOf<CaptureLaunch?>(null)
    private var areVisualsOn by mutableStateOf(true)
    private var isVisualUiSupported by mutableStateOf(false)
    private var permissionsGranted by mutableStateOf(false)
    private var permissionDenied by mutableStateOf(false)
    private var voiceState by mutableStateOf<VoiceSessionState>(VoiceSessionState.Idle)
    private var voiceTranscript by mutableStateOf<String?>(null)
    private var captureStatus by mutableStateOf("Ready to launch an Android XR session.")
    private var captureError by mutableStateOf<String?>(null)
    private var cameraReady by mutableStateOf(false)
    private var isRecording by mutableStateOf(false)
    private var captureStartEpochMs by mutableLongStateOf(0L)

    private val requestPermissionLauncher: ActivityResultLauncher<List<ProjectedPermissionsRequestParams>> =
        registerForActivityResult(ProjectedPermissionsResultContract()) { results ->
            permissionsGranted = results[Manifest.permission.CAMERA] == true &&
                results[Manifest.permission.RECORD_AUDIO] == true
            permissionDenied = !permissionsGranted
            if (permissionsGranted) {
                initializeProjectedExperience()
            }
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        captureLaunch = AndroidXrProjectedLaunch.parse(intent)
        viewModel.setCaptureContext(captureLaunch)

        if (hasRequiredProjectedPermissions()) {
            permissionsGranted = true
            initializeProjectedExperience()
        } else {
            requestHardwarePermissions()
        }

        setContent {
            BlueprintTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background,
                ) {
                    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
                    GlassesProjectedScreen(
                        captureLaunch = captureLaunch,
                        isVisualUiSupported = isVisualUiSupported,
                        areVisualsOn = areVisualsOn,
                        permissionsGranted = permissionsGranted,
                        permissionDenied = permissionDenied,
                        cameraReady = cameraReady,
                        isRecording = isRecording,
                        isFinalizing = uiState.isFinalizing,
                        queuedUploadId = uiState.queuedUploadId,
                        voiceState = voiceState,
                        voiceTranscript = voiceTranscript,
                        captureStatus = captureStatus,
                        captureError = captureError ?: uiState.launchError,
                        onRetryPermissions = ::requestHardwarePermissions,
                        onStartVoice = {
                            voiceSessionOrchestrator?.startSession(
                                welcomeText = buildWelcomeText(captureLaunch, isVisualUiSupported),
                                preferGeminiLive = true,
                            )
                        },
                        onStartCapture = ::startProjectedCapture,
                        onStopCapture = ::stopProjectedCapture,
                        onClose = ::finish,
                    )
                }
            }
        }
    }

    override fun onStart() {
        super.onStart()
        if (permissionsGranted) {
            voiceSessionOrchestrator?.startSession(
                welcomeText = buildWelcomeText(captureLaunch, isVisualUiSupported),
                preferGeminiLive = true,
            )
        }
    }

    override fun onDestroy() {
        activeRecording?.stop()
        voiceSessionOrchestrator?.endSession()
        voiceSessionOrchestrator?.release()
        captureManager?.close()
        displayController?.close()
        viewModel.resetRuntimeCapabilities()
        super.onDestroy()
    }

    private fun hasRequiredProjectedPermissions(): Boolean {
        return ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == android.content.pm.PackageManager.PERMISSION_GRANTED &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == android.content.pm.PackageManager.PERMISSION_GRANTED
    }

    private fun requestHardwarePermissions() {
        val params = ProjectedPermissionsRequestParams(
            permissions = listOf(Manifest.permission.CAMERA, Manifest.permission.RECORD_AUDIO),
            rationale = "Camera and microphone access are required for Android XR hands-free capture and voice control.",
        )
        requestPermissionLauncher.launch(listOf(params))
    }

    private fun initializeProjectedExperience() {
        lifecycleScope.launch {
            val projectedDeviceController = ProjectedDeviceController.create(this@GlassesProjectedActivity)
            isVisualUiSupported = projectedDeviceController.capabilities.contains(
                ProjectedDeviceController.Capability.CAPABILITY_VISUAL_UI,
            )
            viewModel.updateRuntimeCapabilities(
                GlassesCapabilities(
                    hasDisplay = isVisualUiSupported,
                    supportsProjectedCamera = true,
                    supportsProjectedMic = true,
                    supportsDevicePose = true,
                    supportsGeospatial = true,
                ),
            )

            val controller = ProjectedDisplayController.create(this@GlassesProjectedActivity)
            displayController = controller
            controller.addPresentationModeChangedListener { flags ->
                areVisualsOn = flags.hasPresentationMode(ProjectedDisplayController.PresentationMode.VISUALS_ON)
            }

            captureManager = AndroidXrProjectedCaptureManager(this@GlassesProjectedActivity)
            captureManager?.prepare()
                ?.onSuccess {
                    cameraReady = true
                    captureStatus = "Projected camera is ready. Capture will be validated on hardware, not in the emulator."
                }
                ?.onFailure { error ->
                    captureError = error.message ?: "Projected camera is not ready."
                }

            initializeVoice()
        }
    }

    private fun initializeVoice() {
        voiceSessionOrchestrator?.release()
        voiceSessionOrchestrator = VoiceSessionOrchestrator(
            scope = lifecycleScope,
            geminiLiveConnector = UnavailableGeminiLiveConnector(
                message = "Gemini Live app wiring is not configured in BlueprintCapture yet; falling back to on-device speech.",
            ),
            speechInput = AndroidOnDeviceSpeechInput(
                context = this,
                onResults = { matches, confidences ->
                    voiceSessionOrchestrator?.notifySpeechResults(matches, confidences)
                },
                onError = { message ->
                    voiceSessionOrchestrator?.notifyRecognitionError(message)
                },
            ),
            voiceOutput = AndroidVoiceOutput(
                context = this,
                onUtteranceDone = { utteranceId ->
                    voiceSessionOrchestrator?.notifyUtteranceCompleted(utteranceId)
                },
            ),
            onStateChanged = { state ->
                voiceState = state
                captureStatus = when (state) {
                    is VoiceSessionState.Starting -> "Starting voice session."
                    is VoiceSessionState.Listening -> "Listening via ${state.source.replace('_', ' ')}."
                    is VoiceSessionState.Thinking -> "Heard: ${state.transcript}"
                    is VoiceSessionState.Speaking ->
                        if (state.fallback) "Speaking guidance with on-device voice fallback."
                        else "Speaking guidance."
                    is VoiceSessionState.Errored -> state.message
                    VoiceSessionState.Ended -> "Voice session ended."
                    VoiceSessionState.Idle -> captureStatus
                }
            },
            onTranscript = { transcript ->
                voiceTranscript = transcript
            },
        )
    }

    private fun startProjectedCapture() {
        if (!cameraReady) {
            captureError = "Projected camera capture is not ready on this device."
            return
        }
        val outputDirectory = filesDir.resolve("xr_projected_captures/${System.currentTimeMillis()}").also { it.mkdirs() }
        val outputFile = outputDirectory.resolve("walkthrough.mp4")
        captureStartEpochMs = System.currentTimeMillis()
        captureError = null
        captureStatus = "Starting projected recording."
        captureManager?.startRecording(
            outputFile = outputFile,
            withAudio = true,
        ) { event ->
            when (event) {
                is VideoRecordEvent.Start -> {
                    isRecording = true
                    captureStatus = "Recording from the projected glasses camera."
                }

                is VideoRecordEvent.Status -> {
                    captureStatus = "Recording ${(event.recordingStats.recordedDurationNanos / 1_000_000_000L)}s"
                }

                is VideoRecordEvent.Finalize -> {
                    isRecording = false
                    activeRecording = null
                    if (event.hasError()) {
                        captureError = event.cause?.message ?: "Projected recording failed."
                    } else {
                        viewModel.finalizeProjectedCapture(
                            recordingFile = outputFile,
                            captureStartEpochMs = captureStartEpochMs,
                            captureDurationMs = event.recordingStats.recordedDurationNanos / 1_000_000L,
                        )
                    }
                }
            }
        }?.onSuccess { recording ->
            activeRecording = recording
        }?.onFailure { error ->
            captureError = error.message ?: "Projected recording could not start."
        }
    }

    private fun stopProjectedCapture() {
        activeRecording?.stop()
    }

    private fun buildWelcomeText(
        captureLaunch: CaptureLaunch?,
        hasDisplay: Boolean,
    ): String {
        val target = captureLaunch?.label ?: "Blueprint Capture"
        return if (hasDisplay) {
            "Android XR session ready for $target."
        } else {
            "Android XR audio session ready for $target. Voice guidance is active."
        }
    }
}

@androidx.compose.runtime.Composable
private fun GlassesProjectedScreen(
    captureLaunch: CaptureLaunch?,
    isVisualUiSupported: Boolean,
    areVisualsOn: Boolean,
    permissionsGranted: Boolean,
    permissionDenied: Boolean,
    cameraReady: Boolean,
    isRecording: Boolean,
    isFinalizing: Boolean,
    queuedUploadId: String?,
    voiceState: VoiceSessionState,
    voiceTranscript: String?,
    captureStatus: String,
    captureError: String?,
    onRetryPermissions: () -> Unit,
    onStartVoice: () -> Unit,
    onStartCapture: () -> Unit,
    onStopCapture: () -> Unit,
    onClose: () -> Unit,
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Text(
                text = captureLaunch?.label ?: "Android XR readiness mode",
                style = MaterialTheme.typography.headlineSmall,
                color = MaterialTheme.colorScheme.onBackground,
            )
            Text(
                text = if (isVisualUiSupported) {
                    if (areVisualsOn) "Display-capable glasses with visuals on." else "Display-capable glasses with visuals currently off."
                } else {
                    "Audio-first or displayless glasses mode."
                },
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onBackground,
            )

            ProjectedInfoCard(title = "Voice state", body = voiceState.toHumanLabel())
            ProjectedInfoCard(title = "Capture status", body = captureStatus)
            voiceTranscript?.let { transcript ->
                ProjectedInfoCard(title = "Last transcript", body = transcript)
            }
            ProjectedInfoCard(
                title = "Capabilities",
                body = buildString {
                    append(if (cameraReady) "Projected camera ready" else "Projected camera pending")
                    append(" • ")
                    append(if (permissionsGranted) "Permissions granted" else "Permissions missing")
                },
            )

            captureError?.let {
                Text(
                    text = it,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.error,
                )
            }
            queuedUploadId?.let {
                Text(
                    text = "Queued upload: $it",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.primary,
                )
            }

            if (isFinalizing) {
                CircularProgressIndicator()
            }

            Spacer(modifier = Modifier.height(8.dp))

            when {
                permissionDenied || !permissionsGranted -> {
                    Button(onClick = onRetryPermissions) {
                        Text("Grant camera + mic")
                    }
                }

                isRecording -> {
                    Button(onClick = onStopCapture) {
                        Text("Stop capture")
                    }
                }

                else -> {
                    Button(onClick = onStartCapture, enabled = cameraReady) {
                        Text("Start projected capture")
                    }
                }
            }

            OutlinedButton(onClick = onStartVoice) {
                Text("Restart voice")
            }

            OutlinedButton(onClick = onClose) {
                Text("Close")
            }
        }
    }
}

@androidx.compose.runtime.Composable
private fun ProjectedInfoCard(
    title: String,
    body: String,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(
            text = title,
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            text = body,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurface,
        )
    }
}

private fun VoiceSessionState.toHumanLabel(): String = when (this) {
    VoiceSessionState.Idle -> "Idle"
    is VoiceSessionState.Starting -> "Starting"
    is VoiceSessionState.Listening -> "Listening (${source.replace('_', ' ')})"
    is VoiceSessionState.Thinking -> "Thinking about \"$transcript\""
    is VoiceSessionState.Speaking -> "Speaking"
    is VoiceSessionState.Errored -> "Error: $message"
    VoiceSessionState.Ended -> "Ended"
}
