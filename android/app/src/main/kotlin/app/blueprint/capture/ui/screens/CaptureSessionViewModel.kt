package app.blueprint.capture.ui.screens

import android.content.Context
import android.media.MediaMetadataRetriever
import android.os.Build
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.blueprint.capture.data.auth.AuthRepository
import app.blueprint.capture.data.capture.AndroidCaptureBundleBuilder
import app.blueprint.capture.data.capture.AndroidCaptureBundleRequest
import app.blueprint.capture.data.capture.CaptureUploadRepository
import app.blueprint.capture.data.model.CaptureLaunch
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.File
import java.util.Locale
import java.util.UUID
import javax.inject.Inject
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

data class CaptureSessionUiState(
    val isPackaging: Boolean = false,
    val errorMessage: String? = null,
    val queuedUploadId: String? = null,
)

@HiltViewModel
class CaptureSessionViewModel @Inject constructor(
    @ApplicationContext private val context: Context,
    private val authRepository: AuthRepository,
    private val bundleBuilder: AndroidCaptureBundleBuilder,
    private val uploadRepository: CaptureUploadRepository,
) : ViewModel() {
    private val _uiState = MutableStateFlow(CaptureSessionUiState())
    val uiState: StateFlow<CaptureSessionUiState> = _uiState.asStateFlow()

    fun queueRecordedCapture(
        capture: CaptureLaunch,
        recordingFile: File,
        captureStartEpochMs: Long,
        captureDurationMs: Long,
    ) {
        viewModelScope.launch {
            _uiState.value = CaptureSessionUiState(isPackaging = true)

            runCatching {
                withContext(Dispatchers.IO) {
                    val metadata = readVideoMetadata(recordingFile)
                    val creatorId = authRepository.currentUserId()
                    val captureId = UUID.randomUUID().toString()
                    val taskSteps = capture.workflowSteps.ifEmpty { defaultTaskSteps(capture.label) }
                    val request = AndroidCaptureBundleRequest(
                        sceneId = capture.jobId ?: capture.targetId ?: fallbackSceneId(capture.label),
                        captureId = captureId,
                        creatorId = creatorId ?: "anonymous",
                        jobId = capture.jobId ?: capture.targetId,
                        siteSubmissionId = capture.siteSubmissionId,
                        deviceModel = "${Build.MANUFACTURER} ${Build.MODEL}".trim(),
                        osVersion = "Android ${Build.VERSION.RELEASE ?: Build.VERSION.SDK_INT}",
                        fpsSource = metadata.frameRate,
                        width = metadata.width,
                        height = metadata.height,
                        captureStartEpochMs = captureStartEpochMs,
                        captureDurationMs = captureDurationMs,
                        captureContextHint = capture.label,
                        workflowName = capture.workflowName ?: capture.label,
                        taskSteps = taskSteps,
                        zone = capture.zone,
                        owner = capture.owner,
                        quotedPayoutCents = capture.quotedPayoutCents,
                        rightsProfile = capture.rightsProfile,
                        requestedOutputs = capture.requestedOutputs,
                    )
                    val outputRoot = context.filesDir.resolve("capture_bundles").also { it.mkdirs() }
                    val bundle = bundleBuilder.writeBundle(
                        outputRoot = outputRoot,
                        request = request,
                        walkthroughSource = recordingFile,
                    )
                    recordingFile.delete()
                    uploadRepository.enqueueBundleUpload(
                        label = capture.label,
                        bundleRoot = bundle.captureRoot,
                        request = request,
                    )
                }
            }.onSuccess { uploadId ->
                _uiState.value = CaptureSessionUiState(queuedUploadId = uploadId)
            }.onFailure { error ->
                _uiState.value = CaptureSessionUiState(
                    errorMessage = error.message ?: "Failed to package the capture.",
                )
            }
        }
    }

    fun clearError() {
        _uiState.value = _uiState.value.copy(errorMessage = null)
    }

    private fun readVideoMetadata(file: File): VideoMetadata {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(file.absolutePath)
            val width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                ?.toIntOrNull()
                ?: 1920
            val height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                ?.toIntOrNull()
                ?: 1080
            val frameRate = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_CAPTURE_FRAMERATE)
                ?.toDoubleOrNull()
                ?: 30.0
            VideoMetadata(
                width = width,
                height = height,
                frameRate = frameRate,
            )
        } finally {
            retriever.release()
        }
    }

    private fun fallbackSceneId(label: String): String {
        return label.lowercase(Locale.US)
            .replace("[^a-z0-9]+".toRegex(), "-")
            .trim('-')
            .ifBlank { "open-capture" }
    }

    private fun defaultTaskSteps(label: String): List<String> = listOf(
        "Start with a wide exterior or entry framing pass for $label",
        "Walk the main path slowly and hold transitions for review",
        "Sweep corners, service points, and sightline blockers before ending",
    )
}

private data class VideoMetadata(
    val width: Int,
    val height: Int,
    val frameRate: Double,
)
