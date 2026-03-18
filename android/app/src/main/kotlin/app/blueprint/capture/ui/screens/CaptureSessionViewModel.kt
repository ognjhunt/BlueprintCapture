package app.blueprint.capture.ui.screens

import android.content.Context
import android.media.MediaMetadataRetriever
import android.os.Build
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.blueprint.capture.data.auth.AuthRepository
import app.blueprint.capture.data.capture.AndroidCaptureBundleBuilder
import app.blueprint.capture.data.capture.AndroidCaptureBundleRequest
import app.blueprint.capture.data.capture.CaptureExportService
import app.blueprint.capture.data.capture.CaptureIMUSampler
import app.blueprint.capture.data.capture.CaptureIntakeMetadata
import app.blueprint.capture.data.capture.CaptureIntakeSource
import app.blueprint.capture.data.capture.CaptureManualIntakeDraft
import app.blueprint.capture.data.capture.CaptureTaskHypothesisStatus
import app.blueprint.capture.data.capture.CaptureUploadRepository
import app.blueprint.capture.data.capture.IntakeResolutionOutcome
import app.blueprint.capture.data.capture.IntakeResolutionService
import app.blueprint.capture.data.capture.QualificationIntakePacket
import app.blueprint.capture.data.capture.TaskHypothesis
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

enum class FinishedCaptureActionState {
    Idle,
    GeneratingIntake,
    QueueingUpload,
    SavingForLater,
    Exporting,
}

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
    val helperText: String = "Add a workflow name, at least one task step, and either a zone or owner.",
    val reviewTitle: String = "Complete Intake",
    val intakeMetadata: CaptureIntakeMetadata? = null,
    val taskHypothesis: TaskHypothesis? = null,
    val preparedBundlePath: String? = null,
    val preparedCaptureId: String? = null,
    // IMU motion sample count written during the session
    val motionSampleCount: Int = 0,
    // Path to pre-written imu_samples.jsonl file from CaptureIMUSampler
    val imuSamplesFilePath: String? = null,
) {
    val recordingFile: File get() = File(recordingFilePath)
    val preparedBundleFile: File? get() = preparedBundlePath?.let(::File)
    val imuSamplesFile: File? get() = imuSamplesFilePath?.let(::File)

    val taskSteps: List<String>
        get() = taskStepsText.lines().map { it.trim() }.filter { it.isNotEmpty() }

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

    val isStructuredIntakeComplete: Boolean get() = intakePacket.isComplete

    fun buildRequest(creatorId: String, captureId: String): AndroidCaptureBundleRequest {
        val contextHint = listOfNotNull(
            capture.label.takeIf(String::isNotBlank),
            notes.trim().ifBlank { null }?.let { "Notes: $it" },
        ).joinToString(separator = " | ")

        val intakeMetadataValue = intakeMetadata ?: if (isStructuredIntakeComplete) {
            CaptureIntakeMetadata(source = CaptureIntakeSource.HumanManual)
        } else {
            null
        }

        return AndroidCaptureBundleRequest(
            sceneId = capture.jobId ?: capture.targetId ?: captureFallbackSceneId(capture.label),
            captureId = captureId,
            creatorId = creatorId,
            jobId = capture.jobId ?: capture.targetId,
            siteSubmissionId = capture.siteSubmissionId,
            deviceModel = "${Build.MANUFACTURER} ${Build.MODEL}".trim(),
            osVersion = "Android ${Build.VERSION.RELEASE ?: Build.VERSION.SDK_INT}",
            fpsSource = frameRate,
            width = width,
            height = height,
            captureStartEpochMs = captureStartEpochMs,
            captureDurationMs = captureDurationMs,
            captureContextHint = contextHint.ifBlank { null },
            workflowName = intakePacket.workflowName,
            taskSteps = intakePacket.taskSteps,
            zone = intakePacket.zone,
            owner = intakePacket.owner,
            operatorNotes = notesList,
            intakePacket = intakePacket.takeIf {
                it.workflowName != null || it.taskSteps.isNotEmpty() ||
                    it.zone != null || it.owner != null
            },
            intakeMetadata = intakeMetadataValue,
            taskHypothesis = taskHypothesis,
            quotedPayoutCents = capture.quotedPayoutCents,
            rightsProfile = capture.rightsProfile,
            requestedOutputs = capture.requestedOutputs.ifEmpty {
                listOf("qualification", "review_intake")
            },
            motionSampleCount = motionSampleCount,
        )
    }

    fun updateFromManualDraft(
        manualDraft: CaptureManualIntakeDraft,
        metadata: CaptureIntakeMetadata? = intakeMetadata,
        hypothesis: TaskHypothesis? = taskHypothesis,
    ): CaptureReviewDraft = copy(
        workflowName = manualDraft.workflowName,
        taskStepsText = manualDraft.taskStepsText,
        zone = manualDraft.zone,
        owner = manualDraft.owner,
        helperText = manualDraft.helperText,
        reviewTitle = manualDraft.reviewTitle,
        intakeMetadata = metadata,
        taskHypothesis = hypothesis,
    )

    fun invalidatePreparedBundle(): CaptureReviewDraft {
        preparedBundleFile?.deleteRecursively()
        return copy(preparedBundlePath = null, preparedCaptureId = null)
    }

    fun markManualEdit(): CaptureReviewDraft {
        val updatedMetadata = when (intakeMetadata?.source) {
            CaptureIntakeSource.AiInferred -> CaptureIntakeMetadata(
                source = CaptureIntakeSource.HumanManual,
                warnings = intakeMetadata.warnings,
            )
            else -> intakeMetadata
        }
        val updatedHypothesis = taskHypothesis?.copy(
            confidence = null,
            source = CaptureIntakeSource.HumanManual,
            model = null,
            fps = null,
            status = CaptureTaskHypothesisStatus.Accepted,
        )
        return copy(intakeMetadata = updatedMetadata, taskHypothesis = updatedHypothesis)
    }

    companion object {
        fun fromResolution(
            base: CaptureReviewDraft,
            request: AndroidCaptureBundleRequest,
            helperText: String,
            reviewTitle: String,
        ): CaptureReviewDraft {
            val packet = request.intakePacket
            return base.copy(
                workflowName = packet?.workflowName ?: request.workflowName.orEmpty(),
                taskStepsText = packet?.taskSteps.orEmpty()
                    .ifEmpty { request.taskSteps }
                    .joinToString(separator = "\n"),
                zone = packet?.zone ?: request.zone.orEmpty(),
                owner = packet?.owner ?: request.owner.orEmpty(),
                helperText = helperText,
                reviewTitle = reviewTitle,
                intakeMetadata = request.intakeMetadata,
                taskHypothesis = request.taskHypothesis,
            )
        }
    }
}

data class CaptureSessionUiState(
    val actionState: FinishedCaptureActionState = FinishedCaptureActionState.Idle,
    val errorMessage: String? = null,
    val reviewDraft: CaptureReviewDraft? = null,
    val queuedUploadId: String? = null,
    val savedUploadId: String? = null,
    val exportSharePath: String? = null,
    val exportMessage: String? = null,
)

@HiltViewModel
class CaptureSessionViewModel @Inject constructor(
    @ApplicationContext private val context: Context,
    private val authRepository: AuthRepository,
    private val bundleBuilder: AndroidCaptureBundleBuilder,
    private val uploadRepository: CaptureUploadRepository,
    private val intakeResolutionService: IntakeResolutionService,
    private val exportService: CaptureExportService,
) : ViewModel() {

    private val _uiState = MutableStateFlow(CaptureSessionUiState())
    val uiState: StateFlow<CaptureSessionUiState> = _uiState.asStateFlow()

    /** IMU sampler is created per capture session and released on completion or discard. */
    private var imuSampler: CaptureIMUSampler? = null

    // ---------------------------------------------------------------------------
    // IMU lifecycle — called by the recording screen
    // ---------------------------------------------------------------------------

    /** Start accelerometer + gyroscope collection. Call when recording begins. */
    fun startIMUSampling(captureStartMs: Long = System.currentTimeMillis()) {
        val sampler = CaptureIMUSampler(context)
        sampler.startCapture(captureStartMs)
        imuSampler = sampler
    }

    /** Stop sampling and flush to a .jsonl file alongside the recording. Returns sample count. */
    fun stopIMUSamplingAndFlush(rawOutputDir: File): Pair<File?, Int> {
        val sampler = imuSampler ?: return Pair(null, 0)
        val count = sampler.sampleCount()
        val file = if (count > 0) sampler.writeToFile(rawOutputDir) else null
        imuSampler = null
        return Pair(file, count)
    }

    // ---------------------------------------------------------------------------
    // Capture preparation
    // ---------------------------------------------------------------------------

    fun prepareRecordedCapture(
        capture: CaptureLaunch,
        recordingFile: File,
        captureStartEpochMs: Long,
        captureDurationMs: Long,
        imuSamplesFile: File? = null,
        motionSampleCount: Int = 0,
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
                        motionSampleCount = motionSampleCount,
                        imuSamplesFilePath = imuSamplesFile?.absolutePath,
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

    // ---------------------------------------------------------------------------
    // Review draft mutations
    // ---------------------------------------------------------------------------

    fun updateReviewNotes(notes: String) {
        updateReviewDraft { it.copy(notes = notes).markManualEdit().invalidatePreparedBundle() }
    }

    fun updateWorkflowName(workflowName: String) {
        updateReviewDraft { it.copy(workflowName = workflowName).markManualEdit().invalidatePreparedBundle() }
    }

    fun updateTaskSteps(taskStepsText: String) {
        updateReviewDraft { it.copy(taskStepsText = taskStepsText).markManualEdit().invalidatePreparedBundle() }
    }

    fun updateZone(zone: String) {
        updateReviewDraft { it.copy(zone = zone).markManualEdit().invalidatePreparedBundle() }
    }

    fun updateOwner(owner: String) {
        updateReviewDraft { it.copy(owner = owner).markManualEdit().invalidatePreparedBundle() }
    }

    // ---------------------------------------------------------------------------
    // Upload / save / export actions
    // ---------------------------------------------------------------------------

    fun queueUploadNow() { resolveAndContinue(action = FinishedCaptureActionState.QueueingUpload) }
    fun saveForLater() { resolveAndContinue(action = FinishedCaptureActionState.SavingForLater) }
    fun exportForTesting() { resolveAndContinue(action = FinishedCaptureActionState.Exporting) }

    fun consumeExportShare() {
        _uiState.value = _uiState.value.copy(exportSharePath = null)
    }

    fun discardPendingCapture() {
        _uiState.value.reviewDraft?.recordingFile?.takeIf(File::exists)?.delete()
        _uiState.value.reviewDraft?.preparedBundleFile?.deleteRecursively()
        _uiState.value.reviewDraft?.imuSamplesFile?.delete()
        imuSampler?.release()
        imuSampler = null
        _uiState.value = CaptureSessionUiState()
    }

    fun clearError() {
        _uiState.value = _uiState.value.copy(errorMessage = null)
    }

    // ---------------------------------------------------------------------------
    // Internals
    // ---------------------------------------------------------------------------

    private fun updateReviewDraft(transform: (CaptureReviewDraft) -> CaptureReviewDraft) {
        val draft = _uiState.value.reviewDraft ?: return
        _uiState.value = _uiState.value.copy(
            reviewDraft = transform(draft),
            errorMessage = null,
            exportMessage = null,
        )
    }

    private fun resolveAndContinue(action: FinishedCaptureActionState) {
        val draft = _uiState.value.reviewDraft ?: return
        val creatorId = authRepository.currentUserId() ?: "anonymous"
        val captureId = draft.preparedCaptureId ?: UUID.randomUUID().toString()
        val request = draft.buildRequest(creatorId = creatorId, captureId = captureId)

        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(
                actionState = if (action == FinishedCaptureActionState.Exporting)
                    FinishedCaptureActionState.GeneratingIntake
                else
                    action,
                errorMessage = null,
            )

            when (val resolution = intakeResolutionService.resolve(request)) {
                is IntakeResolutionOutcome.Resolved -> {
                    val resolvedDraft = CaptureReviewDraft.fromResolution(
                        base = draft,
                        request = resolution.request,
                        helperText = resolvedHelperText(resolution.request),
                        reviewTitle = "Submission Ready",
                    ).copy(preparedCaptureId = captureId)
                    _uiState.value = _uiState.value.copy(
                        reviewDraft = resolvedDraft,
                        actionState = action,
                    )
                    continueWithResolvedDraft(resolvedDraft, resolution.request, action)
                }
                is IntakeResolutionOutcome.NeedsManualEntry -> {
                    val updatedDraft = CaptureReviewDraft.fromResolution(
                        base = draft,
                        request = resolution.request,
                        helperText = resolution.draft.helperText,
                        reviewTitle = resolution.draft.reviewTitle,
                    ).copy(preparedCaptureId = captureId)
                    _uiState.value = _uiState.value.copy(
                        reviewDraft = updatedDraft,
                        actionState = FinishedCaptureActionState.Idle,
                        errorMessage = "Review the inferred intake before continuing.",
                    )
                }
            }
        }
    }

    private suspend fun continueWithResolvedDraft(
        draft: CaptureReviewDraft,
        request: AndroidCaptureBundleRequest,
        action: FinishedCaptureActionState,
    ) {
        runCatching {
            withContext(Dispatchers.IO) {
                val bundleRoot = ensurePackagedBundle(draft = draft, request = request)

                when (action) {
                    FinishedCaptureActionState.QueueingUpload ->
                        uploadRepository.enqueueBundleUpload(
                            label = draft.capture.label,
                            bundleRoot = bundleRoot,
                            request = request,
                        )
                    FinishedCaptureActionState.SavingForLater ->
                        uploadRepository.saveBundleForLater(
                            label = draft.capture.label,
                            bundleRoot = bundleRoot,
                            request = request,
                        )
                    FinishedCaptureActionState.Exporting ->
                        exportService.exportCapture(request = request, bundleRoot = bundleRoot)
                    FinishedCaptureActionState.Idle,
                    FinishedCaptureActionState.GeneratingIntake ->
                        error("Unexpected action state $action")
                }
            }
        }.onSuccess { result ->
            when (action) {
                FinishedCaptureActionState.QueueingUpload ->
                    _uiState.value = CaptureSessionUiState(queuedUploadId = result as String)
                FinishedCaptureActionState.SavingForLater ->
                    _uiState.value = CaptureSessionUiState(savedUploadId = result as String)
                FinishedCaptureActionState.Exporting -> {
                    val bundle = result as app.blueprint.capture.data.capture.FinalizedCaptureBundle
                    _uiState.value = _uiState.value.copy(
                        actionState = FinishedCaptureActionState.Idle,
                        exportSharePath = bundle.shareArtifact.absolutePath,
                        exportMessage = "Export ready. Android saved a local testing bundle.",
                    )
                }
                else -> Unit
            }
        }.onFailure { error ->
            _uiState.value = _uiState.value.copy(
                actionState = FinishedCaptureActionState.Idle,
                errorMessage = error.message ?: "Capture action failed.",
            )
        }
    }

    private fun resolvedHelperText(request: AndroidCaptureBundleRequest): String =
        when (request.intakeMetadata?.source) {
            CaptureIntakeSource.Authoritative -> "Structured intake came from the target metadata."
            CaptureIntakeSource.HumanManual -> "Structured intake is complete and ready for packaging."
            CaptureIntakeSource.AiInferred -> "Android inferred the intake from capture context and accepted it."
            null -> "Structured intake is complete and ready for packaging."
        }

    private fun ensurePackagedBundle(
        draft: CaptureReviewDraft,
        request: AndroidCaptureBundleRequest,
    ): File {
        val existing = draft.preparedBundleFile
        if (existing != null && existing.exists()) return existing

        val outputRoot = context.filesDir.resolve("capture_bundles").also { it.mkdirs() }
        val bundle = bundleBuilder.writeBundle(
            outputRoot = outputRoot,
            request = request,
            walkthroughSource = draft.recordingFile,
            imuSamplesSource = draft.imuSamplesFile,
        )
        draft.recordingFile.takeIf(File::exists)?.delete()

        val updatedDraft = draft.copy(
            preparedBundlePath = bundle.captureRoot.absolutePath,
            preparedCaptureId = request.captureId,
        )
        _uiState.value = _uiState.value.copy(reviewDraft = updatedDraft)
        return bundle.captureRoot
    }

    private fun readVideoMetadata(file: File): VideoMetadata {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(file.absolutePath)
            val width = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                ?.toIntOrNull() ?: 1920
            val height = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                ?.toIntOrNull() ?: 1080
            val frameRate = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_CAPTURE_FRAMERATE)
                ?.toDoubleOrNull() ?: 30.0
            VideoMetadata(width = width, height = height, frameRate = frameRate)
        } finally {
            retriever.release()
        }
    }

    private companion object {
        fun defaultTaskSteps(label: String): List<String> = listOf(
            "Start with a wide exterior or entry framing pass for $label",
            "Walk the main path slowly and hold transitions for review",
            "Sweep corners, service points, and sightline blockers before ending",
        )
    }
}

private fun captureFallbackSceneId(label: String): String =
    label.lowercase(Locale.US)
        .replace("[^a-z0-9]+".toRegex(), "-")
        .trim('-')
        .ifBlank { "open-capture" }

private data class VideoMetadata(val width: Int, val height: Int, val frameRate: Double)
