package app.blueprint.capture.ui.screens

import android.app.Activity
import android.content.Context
import android.media.MediaMetadataRetriever
import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.blueprint.capture.data.auth.AuthRepository
import app.blueprint.capture.data.capture.AndroidCaptureBundleBuilder
import app.blueprint.capture.data.capture.AndroidCaptureBundleRequest
import app.blueprint.capture.data.capture.AndroidCaptureSource
import app.blueprint.capture.data.capture.CaptureIntakeMetadata
import app.blueprint.capture.data.capture.CaptureIntakeSource
import app.blueprint.capture.data.capture.CaptureModeMetadata
import app.blueprint.capture.data.capture.CaptureScaffoldingPacket
import app.blueprint.capture.data.capture.CaptureTopologyMetadata
import app.blueprint.capture.data.capture.CaptureUploadRepository
import app.blueprint.capture.data.capture.QualificationIntakePacket
import app.blueprint.capture.data.capture.SiteIdentity
import app.blueprint.capture.data.glasses.AndroidXrCapabilityRepository
import app.blueprint.capture.data.glasses.AndroidXrProjectedPlatform
import app.blueprint.capture.data.glasses.GlassesCapabilities
import app.blueprint.capture.data.glasses.androidxr.AndroidXrProjectedLaunch
import app.blueprint.capture.data.model.CaptureLaunch
import androidx.xr.projected.ProjectedContext
import androidx.xr.projected.experimental.ExperimentalProjectedApi
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.File
import java.util.Locale
import java.util.UUID
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class AndroidXrUiState(
    val captureLaunch: CaptureLaunch? = null,
    val isProjectedDeviceConnected: Boolean = false,
    val capabilities: GlassesCapabilities = AndroidXrProjectedPlatform.capabilities,
    val launchMessage: String = "Launch the projected activity on connected Android XR glasses to validate video-first capture on hardware.",
    val launchError: String? = null,
    val isFinalizing: Boolean = false,
    val queuedUploadId: String? = null,
)

@HiltViewModel
@OptIn(ExperimentalProjectedApi::class)
class AndroidXrViewModel @Inject constructor(
    @ApplicationContext private val context: Context,
    private val authRepository: AuthRepository,
    private val bundleBuilder: AndroidCaptureBundleBuilder,
    private val uploadRepository: CaptureUploadRepository,
    private val capabilityRepository: AndroidXrCapabilityRepository,
) : ViewModel() {
    private companion object {
        const val TAG = "AndroidXrViewModel"
    }

    private val _uiState = MutableStateFlow(AndroidXrUiState())
    val uiState: StateFlow<AndroidXrUiState> = _uiState.asStateFlow()

    init {
        viewModelScope.launch {
            ProjectedContext.isProjectedDeviceConnected(context, coroutineContext).collect { connected ->
                _uiState.value = _uiState.value.copy(
                    isProjectedDeviceConnected = connected,
                    launchMessage = if (connected) {
                        "Connected Android XR glasses detected. Open the projected activity to validate projected camera, mic, and display behavior on hardware."
                    } else {
                        "No Android XR projected device is connected yet. Use a paired AI-glasses device or emulator."
                    },
                )
            }
        }
        viewModelScope.launch {
            capabilityRepository.capabilities.collect { capabilities ->
                _uiState.value = _uiState.value.copy(capabilities = capabilities)
            }
        }
    }

    fun setCaptureContext(captureLaunch: CaptureLaunch?) {
        if (_uiState.value.captureLaunch == captureLaunch) return
        _uiState.value = _uiState.value.copy(
            captureLaunch = captureLaunch,
            queuedUploadId = null,
            launchError = null,
        )
    }

    fun updateRuntimeCapabilities(capabilities: GlassesCapabilities) {
        capabilityRepository.update(capabilities)
    }

    fun resetRuntimeCapabilities() {
        capabilityRepository.reset()
    }

    fun launchProjectedExperience(activity: Activity?) {
        if (activity == null) {
            _uiState.value = _uiState.value.copy(
                launchError = "An Activity context is required to launch the Android XR projected activity.",
            )
            return
        }
        runCatching {
            val intent = AndroidXrProjectedLaunch.intent(activity, _uiState.value.captureLaunch)
            val options = ProjectedContext.createProjectedActivityOptions(activity)
            activity.startActivity(intent, options.toBundle())
        }.onSuccess {
            _uiState.value = _uiState.value.copy(
                launchError = null,
                launchMessage = "Projected activity launched. Continue on the connected glasses to validate capture and permission flow.",
            )
        }.onFailure { error ->
            Log.w(TAG, "launchProjectedExperience failed", error)
            _uiState.value = _uiState.value.copy(
                launchError = error.message ?: "Projected launch failed.",
            )
        }
    }

    fun finalizeProjectedCapture(
        recordingFile: File,
        captureStartEpochMs: Long,
        captureDurationMs: Long,
    ) {
        val captureLaunch = _uiState.value.captureLaunch
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isFinalizing = true, queuedUploadId = null, launchError = null)
            runCatching {
                authRepository.ensureAnonymousSession()
                val creatorId = authRepository.currentUserId()
                    ?: error("Unable to resolve a signed or guest capture session for upload.")
                val captureId = UUID.randomUUID().toString()
                val metadata = readVideoMetadata(recordingFile, captureDurationMs)
                val request = (captureLaunch ?: CaptureLaunch(label = "Android XR readiness capture")).toAndroidXrBundleRequest(
                    creatorId = creatorId,
                    captureId = captureId,
                    captureStartEpochMs = captureStartEpochMs,
                    captureDurationMs = captureDurationMs,
                    width = metadata.width,
                    height = metadata.height,
                    frameRate = metadata.frameRate,
                )
                val outputRoot = context.filesDir.resolve("capture_bundles").also(File::mkdirs)
                val bundle = bundleBuilder.writeBundle(
                    outputRoot = outputRoot,
                    request = request,
                    walkthroughSource = recordingFile,
                )
                uploadRepository.enqueueBundleUpload(
                    label = captureLaunch?.label ?: "Android XR readiness capture",
                    bundleRoot = bundle.captureRoot,
                    request = request,
                )
            }.onSuccess { uploadId ->
                _uiState.value = _uiState.value.copy(
                    isFinalizing = false,
                    queuedUploadId = uploadId,
                    launchMessage = "Projected glasses capture bundled and queued for upload.",
                    launchError = null,
                )
            }.onFailure { error ->
                Log.w(TAG, "finalizeProjectedCapture failed", error)
                _uiState.value = _uiState.value.copy(
                    isFinalizing = false,
                    launchError = error.message ?: "Projected capture could not be finalized.",
                )
            }
        }
    }

    private fun readVideoMetadata(
        file: File,
        durationMs: Long,
    ): AndroidXrVideoMetadata {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(file.absolutePath)
            val width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                ?.toIntOrNull() ?: 1280
            val height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                ?.toIntOrNull() ?: 720
            val frameRate = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_CAPTURE_FRAMERATE)
                ?.toDoubleOrNull()
                ?: if (durationMs > 0L) 15.0 else 10.0
            AndroidXrVideoMetadata(width = width, height = height, frameRate = frameRate)
        } finally {
            retriever.release()
        }
    }
}

private data class AndroidXrVideoMetadata(
    val width: Int,
    val height: Int,
    val frameRate: Double,
)

private fun CaptureLaunch.toAndroidXrBundleRequest(
    creatorId: String,
    captureId: String,
    captureStartEpochMs: Long,
    captureDurationMs: Long,
    width: Int,
    height: Int,
    frameRate: Double,
): AndroidCaptureBundleRequest {
    val sceneId = jobId ?: targetId ?: androidXrFallbackSceneId(label)
    val siteId = siteSubmissionId ?: targetId ?: jobId ?: sceneId
    val workflowStepsValue = workflowSteps.ifEmpty {
        listOf(
            "Record the outward-facing route from the glasses point of view with continuous motion.",
            "Use voice to mark constraints, coverage gaps, and site-specific review notes.",
            "Keep private people, screens, and paperwork out of frame throughout the capture.",
        )
    }
    return AndroidCaptureBundleRequest(
        sceneId = sceneId,
        captureId = captureId,
        creatorId = creatorId,
        jobId = jobId ?: targetId,
        siteSubmissionId = siteSubmissionId,
        deviceModel = "Android XR projected glasses",
        osVersion = android.os.Build.VERSION.RELEASE ?: android.os.Build.VERSION.SDK_INT.toString(),
        fpsSource = frameRate,
        width = width,
        height = height,
        captureStartEpochMs = captureStartEpochMs,
        captureDurationMs = captureDurationMs,
        captureSource = AndroidCaptureSource.AndroidXrGlasses,
        captureContextHint = label.ifBlank { null },
        workflowName = workflowName,
        taskSteps = workflowStepsValue,
        zone = zone,
        owner = owner,
        operatorNotes = listOfNotNull(
            "capture_origin:android_xr_projected",
            addressText?.takeIf(String::isNotBlank)?.let { "address:$it" },
        ),
        intakePacket = QualificationIntakePacket(
            workflowName = workflowName ?: "Android XR projected capture",
            taskSteps = workflowStepsValue,
            zone = zone,
            owner = owner,
        ),
        intakeMetadata = CaptureIntakeMetadata(source = CaptureIntakeSource.HumanManual),
        quotedPayoutCents = quotedPayoutCents,
        rightsProfile = rightsProfile,
        requestedOutputs = requestedOutputs.ifEmpty { listOf("qualification", "review_intake") },
        siteIdentity = SiteIdentity(
            siteId = siteId,
            siteIdSource = if (!siteSubmissionId.isNullOrBlank()) {
                "site_submission"
            } else if (!targetId.isNullOrBlank()) {
                "buyer_request"
            } else {
                "open_capture"
            },
            siteName = label.takeIf(String::isNotBlank),
            addressFull = addressText?.takeIf(String::isNotBlank),
        ),
        captureTopology = CaptureTopologyMetadata(
            captureSessionId = captureId,
            routeId = siteId,
            passId = captureId,
            passIndex = 1,
            intendedPassRole = "primary",
        ),
        captureMode = CaptureModeMetadata(
            requestedMode = "site_world_candidate",
            resolvedMode = "site_world_candidate",
        ),
        scaffoldingPacket = CaptureScaffoldingPacket(
            scaffoldingUsed = listOf("android_xr_projected_activity", "audio_first_glasses"),
            coveragePlan = workflowStepsValue,
        ),
    )
}

private fun androidXrFallbackSceneId(label: String): String =
    label.lowercase(Locale.US)
        .replace("[^a-z0-9]+".toRegex(), "-")
        .trim('-')
        .ifBlank { "android-xr-open-capture" }
