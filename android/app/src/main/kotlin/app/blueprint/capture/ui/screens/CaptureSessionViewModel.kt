package app.blueprint.capture.ui.screens

import android.content.Context
import android.media.MediaMetadataRetriever
import android.os.Build
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.blueprint.capture.data.auth.AuthRepository
import app.blueprint.capture.data.capture.AndroidCaptureBundleBuilder
import app.blueprint.capture.data.capture.AndroidCaptureBundleRequest
import app.blueprint.capture.data.capture.CaptureIntakeMetadata
import app.blueprint.capture.data.capture.CaptureUploadRepository
import app.blueprint.capture.data.capture.QualificationIntakePacket
import app.blueprint.capture.data.capture.isComplete
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

data class CaptureReviewDraft(
    val capture: CaptureLaunch,
    val recordingFilePath: String,
    val captureStartEpochMs: Long,
    val captureDurationMs: Long,
    val width: Int,
    val height: Int,
    val frameRate: Double,
    val workflowName: String,
    val taskStepsText: String,
    val zone: String,
    val owner: String,
    val notes: String = "",
) {
    val recordingFile: File
        get() = File(recordingFilePath)

    val taskSteps: List<String>
        get() = taskStepsText
            .lines()
            .map { it.trim() }
            .filter { it.isNotEmpty() }

    val intakePacket: QualificationIntakePacket
        get() = QualificationIntakePacket(
            workflowName = workflowName.trim().ifBlank { null },
            taskSteps = taskSteps,
            zone = zone.trim().ifBlank { null },
            owner = owner.trim().ifBlank { null },
        )

    val notesList: List<String>
        get() = notes.trim().ifBlank { "" }
            .let { if (it.isBlank()) emptyList() else listOf(it) }

    val isStructuredIntakeComplete: Boolean
        get() = intakePacket.isComplete
}

data class CaptureSessionUiState(
    val isPackaging: Boolean = false,
    val errorMessage: String? = null,
    val reviewDraft: CaptureReviewDraft? = null,
    val queuedUploadId: String? = null,
    val savedUploadId: String? = null,
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

    fun prepareRecordedCapture(
        capture: CaptureLaunch,
        recordingFile: File,
        captureStartEpochMs: Long,
        captureDurationMs: Long,
    ) {
        viewModelScope.launch {
            runCatching {
                withContext(Dispatchers.IO) {
                    val metadata = readVideoMetadata(recordingFile)
                    CaptureReviewDraft(
                        capture = capture,
                        recordingFilePath = recordingFile.absolutePath,
                        captureStartEpochMs = captureStartEpochMs,
                        captureDurationMs = captureDurationMs,
                        width = metadata.width,
                        height = metadata.height,
                        frameRate = metadata.frameRate,
                        workflowName = capture.workflowName.orEmpty(),
                        taskStepsText = capture.workflowSteps
                            .ifEmpty { defaultTaskSteps(capture.label) }
                            .joinToString(separator = "\n"),
                        zone = capture.zone.orEmpty(),
                        owner = capture.owner.orEmpty(),
                    )
                }
            }.onSuccess { draft ->
                _uiState.value = CaptureSessionUiState(reviewDraft = draft)
            }.onFailure { error ->
                recordingFile.delete()
                _uiState.value = CaptureSessionUiState(
                    errorMessage = error.message ?: "Failed to prepare the capture for review.",
                )
            }
        }
    }

    fun updateReviewNotes(notes: String) {
        updateReviewDraft { it.copy(notes = notes) }
    }

    fun updateWorkflowName(workflowName: String) {
        updateReviewDraft { it.copy(workflowName = workflowName) }
    }

    fun updateTaskSteps(taskStepsText: String) {
        updateReviewDraft { it.copy(taskStepsText = taskStepsText) }
    }

    fun updateZone(zone: String) {
        updateReviewDraft { it.copy(zone = zone) }
    }

    fun updateOwner(owner: String) {
        updateReviewDraft { it.copy(owner = owner) }
    }

    fun packageCapture(startImmediately: Boolean) {
        val draft = _uiState.value.reviewDraft ?: return
        if (!draft.isStructuredIntakeComplete) {
            _uiState.value = _uiState.value.copy(
                errorMessage = "Add workflow details, task steps, and either a zone or owner before continuing.",
            )
            return
        }

        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isPackaging = true, errorMessage = null)

            runCatching {
                withContext(Dispatchers.IO) {
                    val creatorId = authRepository.currentUserId()
                    val captureId = UUID.randomUUID().toString()
                    val request = buildBundleRequest(
                        capture = draft.capture,
                        draft = draft,
                        creatorId = creatorId ?: "anonymous",
                        captureId = captureId,
                    )
                    val outputRoot = context.filesDir.resolve("capture_bundles").also { it.mkdirs() }
                    val bundle = bundleBuilder.writeBundle(
                        outputRoot = outputRoot,
                        request = request,
                        walkthroughSource = draft.recordingFile,
                    )
                    draft.recordingFile.delete()
                    if (startImmediately) {
                        uploadRepository.enqueueBundleUpload(
                            label = draft.capture.label,
                            bundleRoot = bundle.captureRoot,
                            request = request,
                        )
                    } else {
                        uploadRepository.saveBundleForLater(
                            label = draft.capture.label,
                            bundleRoot = bundle.captureRoot,
                            request = request,
                        )
                    }
                }
            }.onSuccess { uploadId ->
                _uiState.value = CaptureSessionUiState(
                    queuedUploadId = uploadId.takeIf { startImmediately },
                    savedUploadId = uploadId.takeUnless { startImmediately },
                )
            }.onFailure { error ->
                _uiState.value = _uiState.value.copy(
                    isPackaging = false,
                    errorMessage = error.message ?: "Failed to package the capture.",
                )
            }
        }
    }

    fun discardPendingCapture() {
        _uiState.value.reviewDraft?.recordingFile?.delete()
        _uiState.value = CaptureSessionUiState()
    }

    fun clearError() {
        _uiState.value = _uiState.value.copy(errorMessage = null)
    }

    private fun updateReviewDraft(transform: (CaptureReviewDraft) -> CaptureReviewDraft) {
        val draft = _uiState.value.reviewDraft ?: return
        _uiState.value = _uiState.value.copy(
            reviewDraft = transform(draft),
            errorMessage = null,
        )
    }

    private fun buildBundleRequest(
        capture: CaptureLaunch,
        draft: CaptureReviewDraft,
        creatorId: String,
        captureId: String,
    ): AndroidCaptureBundleRequest {
        val contextHint = listOfNotNull(
            capture.label.takeIf(String::isNotBlank),
            draft.notes.trim().ifBlank { null }?.let { "Notes: $it" },
        ).joinToString(separator = " | ")

        return AndroidCaptureBundleRequest(
            sceneId = capture.jobId ?: capture.targetId ?: fallbackSceneId(capture.label),
            captureId = captureId,
            creatorId = creatorId,
            jobId = capture.jobId ?: capture.targetId,
            siteSubmissionId = capture.siteSubmissionId,
            deviceModel = "${Build.MANUFACTURER} ${Build.MODEL}".trim(),
            osVersion = "Android ${Build.VERSION.RELEASE ?: Build.VERSION.SDK_INT}",
            fpsSource = draft.frameRate,
            width = draft.width,
            height = draft.height,
            captureStartEpochMs = draft.captureStartEpochMs,
            captureDurationMs = draft.captureDurationMs,
            captureContextHint = contextHint.ifBlank { null },
            workflowName = draft.intakePacket.workflowName,
            taskSteps = draft.intakePacket.taskSteps,
            zone = draft.intakePacket.zone,
            owner = draft.intakePacket.owner,
            operatorNotes = draft.notesList,
            intakePacket = draft.intakePacket,
            intakeMetadata = CaptureIntakeMetadata(source = "human_manual"),
            quotedPayoutCents = capture.quotedPayoutCents,
            rightsProfile = capture.rightsProfile,
            requestedOutputs = capture.requestedOutputs.ifEmpty {
                listOf("qualification", "review_intake")
            },
        )
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
