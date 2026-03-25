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
import app.blueprint.capture.data.capture.CaptureModeMetadata
import app.blueprint.capture.data.capture.CaptureScaffoldingPacket
import app.blueprint.capture.data.capture.CaptureTopologyMetadata
import app.blueprint.capture.data.capture.CaptureTaskHypothesisStatus
import app.blueprint.capture.data.capture.CaptureUploadRepository
import app.blueprint.capture.data.capture.IntakeResolutionOutcome
import app.blueprint.capture.data.capture.IntakeResolutionService
import app.blueprint.capture.data.capture.QualificationIntakePacket
import app.blueprint.capture.data.capture.SiteIdentity
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

enum class SiteWorldSiteScale {
    SmallSimple,
    Medium,
    MultiZone,
}

enum class SiteWorldAnchorType(val label: String) {
    Entrance("Entrance"),
    Doorway("Doorway"),
    Intersection("Intersection"),
    DockTurn("Dock turn"),
    HandoffPoint("Handoff"),
    ControlPanel("Control panel"),
    FloorTransition("Floor transition"),
    RestrictedBoundary("Restricted boundary"),
    ExitPoint("Exit"),
}

enum class SiteWorldReviewTone {
    Ready,
    Caution,
    ActionRequired,
}

data class SiteWorldPassBrief(
    val role: String,
    val title: String,
    val summary: String,
    val requiredCheckpointTarget: Int,
    val requiredPrompt: String,
    val exactPrompts: List<String>,
)

data class SiteWorldPassReview(
    val passAttemptIndex: Int,
    val passRole: String,
    val title: String,
    val tone: SiteWorldReviewTone,
    val score: Int,
    val summary: String,
    val completedItems: List<String>,
    val missingItems: List<String>,
    val weakSignalSummary: String?,
    val nextActionLabel: String?,
    val canFinishWorkflow: Boolean,
    val shouldAdvanceWorkflow: Boolean,
    val completedRequiredPasses: Int,
    val totalRequiredPasses: Int,
    val exactPrompts: List<String>,
)

data class SiteWorldRecordingState(
    val entryLocked: Boolean = false,
    val markedAnchors: List<SiteWorldAnchorType> = emptyList(),
    val weakSignalEvents: Int = 0,
)

data class CaptureReviewDraft(
    val capture: CaptureLaunch,
    val recordingFilePath: String,
    val recordingWorkspacePath: String? = null,
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
    val arcoreEvidenceDirectoryPath: String? = null,
    val coordinateFrameSessionId: String? = null,
    val siteWorldSiteScale: SiteWorldSiteScale = SiteWorldSiteScale.Medium,
    val siteWorldCriticalZones: Set<SiteWorldAnchorType> = emptySet(),
    val siteWorldPassAttemptIndex: Int = 1,
    val siteWorldPassRole: String = "primary",
    val siteWorldEntryLocked: Boolean = false,
    val siteWorldMarkedAnchors: List<SiteWorldAnchorType> = emptyList(),
    val siteWorldWeakSignalEvents: Int = 0,
    val siteWorldReview: SiteWorldPassReview? = null,
) {
    val recordingFile: File get() = File(recordingFilePath)
    val recordingWorkspace: File? get() = recordingWorkspacePath?.let(::File)
    val preparedBundleFile: File? get() = preparedBundlePath?.let(::File)
    val imuSamplesFile: File? get() = imuSamplesFilePath?.let(::File)
    val arcoreEvidenceDirectory: File? get() = arcoreEvidenceDirectoryPath?.let(::File)

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

        val routeId = capture.siteSubmissionId ?: capture.targetId ?: capture.jobId ?: "android-route"
        val checkpointAssets = buildList {
            if (siteWorldEntryLocked) add("anchor_entry")
            addAll(
                siteWorldMarkedAnchors.map { anchor ->
                    when (anchor) {
                        SiteWorldAnchorType.Entrance -> "semantic_entrance"
                        SiteWorldAnchorType.Doorway -> "semantic_doorway"
                        SiteWorldAnchorType.Intersection -> "semantic_corridor_intersection"
                        SiteWorldAnchorType.DockTurn -> "semantic_dock_turn"
                        SiteWorldAnchorType.HandoffPoint -> "semantic_handoff_point"
                        SiteWorldAnchorType.ControlPanel -> "semantic_control_panel"
                        SiteWorldAnchorType.FloorTransition -> "semantic_floor_transition"
                        SiteWorldAnchorType.RestrictedBoundary -> "semantic_restricted_boundary"
                        SiteWorldAnchorType.ExitPoint -> "semantic_exit_point"
                    }
                },
            )
        }.distinct()

        val coveragePlan = siteWorldCoveragePlan(
            siteScale = siteWorldSiteScale,
            passRole = siteWorldPassRole,
            criticalZones = siteWorldCriticalZones,
        )
        val scaffoldingUsed = siteWorldScaffoldingUsed(
            siteScale = siteWorldSiteScale,
            passRole = siteWorldPassRole,
            criticalZones = siteWorldCriticalZones,
        )
        val workflowNotes = buildList {
            add("site_world_scale:${siteWorldSiteScale.name.lowercase(Locale.US)}")
            add("pass_role:$siteWorldPassRole")
            add("checkpoints:${siteWorldMarkedAnchors.filter { it != SiteWorldAnchorType.Entrance }.size}")
            if (siteWorldCriticalZones.isNotEmpty()) {
                add(
                    "critical_zones:${
                        siteWorldCriticalZones.joinToString(",") { it.name.lowercase(Locale.US) }
                    }",
                )
            }
            if (siteWorldWeakSignalEvents > 0) {
                add("weak_signal_events:$siteWorldWeakSignalEvents")
            }
            siteWorldReview?.weakSignalSummary?.let(::add)
        }

        return AndroidCaptureBundleRequest(
            sceneId = capture.jobId ?: capture.targetId ?: captureFallbackSceneId(capture.label),
            captureId = captureId,
            creatorId = creatorId,
            jobId = capture.jobId ?: capture.targetId,
            siteSubmissionId = capture.siteSubmissionId,
            siteIdentity = SiteIdentity(
                siteId = capture.siteSubmissionId ?: capture.targetId ?: capture.jobId ?: captureFallbackSceneId(capture.label),
                siteIdSource = if (!capture.siteSubmissionId.isNullOrBlank()) "site_submission" else if (!capture.targetId.isNullOrBlank()) "buyer_request" else "open_capture",
                siteName = capture.label.takeIf(String::isNotBlank),
            ),
            captureTopology = CaptureTopologyMetadata(
                captureSessionId = coordinateFrameSessionId ?: captureId,
                routeId = routeId,
                passId = captureId,
                passIndex = siteWorldPassAttemptIndex,
                intendedPassRole = siteWorldPassRole,
                entryAnchorId = if (siteWorldEntryLocked) "anchor_entry" else null,
                returnAnchorId = if (siteWorldPassRole == "loop_closure") "anchor_entry" else null,
                entryAnchorTCaptureSec = if (siteWorldEntryLocked) 0.0 else null,
                entryAnchorHoldDurationSec = if (siteWorldEntryLocked) 3.0 else null,
            ),
            captureMode = CaptureModeMetadata(
                requestedMode = "site_world_candidate",
                resolvedMode = "site_world_candidate",
            ),
            scaffoldingPacket = CaptureScaffoldingPacket(
                scaffoldingUsed = scaffoldingUsed,
                coveragePlan = coveragePlan,
                checkpointAssets = checkpointAssets,
                uncertaintyPriors = mapOf("missing_intake" to 0.6),
            ),
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
            operatorNotes = notesList + workflowNotes,
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
    val siteWorldSiteScale: SiteWorldSiteScale = SiteWorldSiteScale.Medium,
    val siteWorldCriticalZones: Set<SiteWorldAnchorType> = emptySet(),
    val siteWorldWorkflowConfigured: Boolean = false,
    val siteWorldCompletedRequiredPasses: Int = 0,
    val siteWorldRecordingState: SiteWorldRecordingState = SiteWorldRecordingState(),
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

    val siteWorldCriticalZoneOptions: List<SiteWorldAnchorType> = listOf(
        SiteWorldAnchorType.DockTurn,
        SiteWorldAnchorType.HandoffPoint,
        SiteWorldAnchorType.ControlPanel,
        SiteWorldAnchorType.FloorTransition,
        SiteWorldAnchorType.RestrictedBoundary,
    )

    val currentSiteWorldPassBrief: SiteWorldPassBrief
        get() = passBriefFor(
            role = currentPlannedPassRole,
            siteScale = _uiState.value.siteWorldSiteScale,
            criticalZones = _uiState.value.siteWorldCriticalZones,
        )

    val currentPlannedPassRole: String
        get() = plannedPassRoleFor(
            stageIndex = _uiState.value.siteWorldCompletedRequiredPasses + 1,
            siteScale = _uiState.value.siteWorldSiteScale,
            criticalZones = _uiState.value.siteWorldCriticalZones,
        )

    val highlightedAnchorTypesForCurrentPass: Set<SiteWorldAnchorType>
        get() = when (currentPlannedPassRole) {
            "revisit" -> setOf(
                SiteWorldAnchorType.Entrance,
                SiteWorldAnchorType.Doorway,
                SiteWorldAnchorType.Intersection,
                SiteWorldAnchorType.ExitPoint,
            ) + _uiState.value.siteWorldCriticalZones
            "loop_closure" -> setOf(
                SiteWorldAnchorType.Entrance,
                SiteWorldAnchorType.Doorway,
                SiteWorldAnchorType.Intersection,
                SiteWorldAnchorType.ExitPoint,
            )
            "critical_zone_revisit" -> _uiState.value.siteWorldCriticalZones.ifEmpty {
                siteWorldCriticalZoneOptions.toSet()
            }
            else -> setOf(
                SiteWorldAnchorType.Doorway,
                SiteWorldAnchorType.Intersection,
                SiteWorldAnchorType.DockTurn,
                SiteWorldAnchorType.HandoffPoint,
                SiteWorldAnchorType.FloorTransition,
                SiteWorldAnchorType.RestrictedBoundary,
            ) + _uiState.value.siteWorldCriticalZones
        }

    val siteWorldRoutePlanSummary: List<String>
        get() = routePlanFor(_uiState.value.siteWorldSiteScale)

    val siteWorldRequiredRules: List<String>
        get() = buildList {
            add("Entrance lock: hold at the main entry before walking.")
            add("Shared checkpoints: stop at doorways, intersections, dock turns, and zone thresholds.")
            add("Weak-signal recovery: mark weak segments so they can be revisited before finishing.")
            when (_uiState.value.siteWorldSiteScale) {
                SiteWorldSiteScale.SmallSimple -> add("Loop close back to the entry or main starting threshold.")
                SiteWorldSiteScale.Medium -> add("Run one reverse revisit on the main spine before loop closure.")
                SiteWorldSiteScale.MultiZone -> add("Return to the hub or spine after each zone before moving to the next one.")
            }
            if (_uiState.value.siteWorldCriticalZones.isNotEmpty()) {
                add("Revisit every selected critical zone from the opposite direction before finishing.")
            }
        }

    val siteWorldOptionalRules: List<String>
        get() = listOf(
            "Add notes only when access limits or unusual blockers matter downstream.",
            "Mark extra checkpoints if the space is repetitive, but do not wander just to raise counts.",
            "Take an extra static sweep only when you are already at a strong shared checkpoint.",
        )

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
        arcoreEvidenceDirectory: File? = null,
        coordinateFrameSessionId: String? = null,
    ) {
        viewModelScope.launch {
            val snapshot = _uiState.value
            val passAttemptIndex = snapshot.siteWorldCompletedRequiredPasses + 1
            val passRole = currentPlannedPassRole
            val review = buildSiteWorldPassReview(
                siteScale = snapshot.siteWorldSiteScale,
                passAttemptIndex = passAttemptIndex,
                passRole = passRole,
                recordingState = snapshot.siteWorldRecordingState,
                criticalZones = snapshot.siteWorldCriticalZones,
                completedRequiredPasses = snapshot.siteWorldCompletedRequiredPasses,
            )
            runCatching {
                withContext(Dispatchers.IO) {
                    val metadata = readVideoMetadata(recordingFile)
                    CaptureReviewDraft(
                        capture = capture,
                        recordingFilePath = recordingFile.absolutePath,
                        recordingWorkspacePath = recordingFile.parentFile?.absolutePath,
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
                        arcoreEvidenceDirectoryPath = arcoreEvidenceDirectory?.absolutePath,
                        coordinateFrameSessionId = coordinateFrameSessionId,
                        siteWorldSiteScale = snapshot.siteWorldSiteScale,
                        siteWorldCriticalZones = snapshot.siteWorldCriticalZones,
                        siteWorldPassAttemptIndex = passAttemptIndex,
                        siteWorldPassRole = passRole,
                        siteWorldEntryLocked = snapshot.siteWorldRecordingState.entryLocked,
                        siteWorldMarkedAnchors = snapshot.siteWorldRecordingState.markedAnchors,
                        siteWorldWeakSignalEvents = snapshot.siteWorldRecordingState.weakSignalEvents,
                        siteWorldReview = review,
                    )
                }
            }.onSuccess { draft ->
                val nextCompletedRequiredPasses = if (review.shouldAdvanceWorkflow) {
                    minOf(review.completedRequiredPasses, review.totalRequiredPasses)
                } else {
                    snapshot.siteWorldCompletedRequiredPasses
                }
                _uiState.value = snapshot.copy(
                    reviewDraft = draft,
                    errorMessage = null,
                    exportMessage = null,
                    siteWorldCompletedRequiredPasses = nextCompletedRequiredPasses,
                )
            }.onFailure { error ->
                recordingFile.delete()
                _uiState.value = snapshot.copy(
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
        _uiState.value.reviewDraft?.recordingWorkspace?.takeIf(File::exists)?.deleteRecursively()
        _uiState.value.reviewDraft?.recordingFile?.takeIf(File::exists)?.delete()
        _uiState.value.reviewDraft?.preparedBundleFile?.deleteRecursively()
        _uiState.value.reviewDraft?.imuSamplesFile?.delete()
        _uiState.value.reviewDraft?.arcoreEvidenceDirectory?.deleteRecursively()
        imuSampler?.release()
        imuSampler = null
        _uiState.value = CaptureSessionUiState()
    }

    fun clearError() {
        _uiState.value = _uiState.value.copy(errorMessage = null)
    }

    fun updateSiteWorldSiteScale(scale: SiteWorldSiteScale) {
        _uiState.value = _uiState.value.copy(siteWorldSiteScale = scale)
    }

    fun toggleCriticalZone(anchorType: SiteWorldAnchorType) {
        val updated = _uiState.value.siteWorldCriticalZones.toMutableSet().apply {
            if (!add(anchorType)) remove(anchorType)
        }
        _uiState.value = _uiState.value.copy(siteWorldCriticalZones = updated)
    }

    fun configureSiteWorldWorkflow() {
        _uiState.value = _uiState.value.copy(siteWorldWorkflowConfigured = true)
    }

    fun beginWorkflowRecordingPass() {
        _uiState.value = _uiState.value.copy(
            siteWorldWorkflowConfigured = true,
            siteWorldRecordingState = SiteWorldRecordingState(),
            errorMessage = null,
            exportMessage = null,
        )
    }

    fun markSiteWorldAnchor(anchorType: SiteWorldAnchorType) {
        val state = _uiState.value.siteWorldRecordingState
        val updatedAnchors = state.markedAnchors + anchorType
        _uiState.value = _uiState.value.copy(
            siteWorldRecordingState = state.copy(
                entryLocked = state.entryLocked || anchorType == SiteWorldAnchorType.Entrance,
                markedAnchors = updatedAnchors,
            ),
        )
    }

    fun markSiteWorldEntryLock() {
        val state = _uiState.value.siteWorldRecordingState
        val updatedAnchors = if (state.markedAnchors.contains(SiteWorldAnchorType.Entrance)) {
            state.markedAnchors
        } else {
            state.markedAnchors + SiteWorldAnchorType.Entrance
        }
        _uiState.value = _uiState.value.copy(
            siteWorldRecordingState = state.copy(
                entryLocked = true,
                markedAnchors = updatedAnchors,
            ),
        )
    }

    fun noteWeakSignalSegment() {
        val state = _uiState.value.siteWorldRecordingState
        _uiState.value = _uiState.value.copy(
            siteWorldRecordingState = state.copy(weakSignalEvents = state.weakSignalEvents + 1),
        )
    }

    fun resetSiteWorldWorkflowSession() {
        _uiState.value = CaptureSessionUiState()
    }

    fun continueWorkflowFromReview() {
        val draft = _uiState.value.reviewDraft ?: return
        if (draft.siteWorldReview?.shouldAdvanceWorkflow == true) {
            _uiState.value = _uiState.value.copy(
                reviewDraft = null,
                actionState = FinishedCaptureActionState.Idle,
                errorMessage = null,
                exportMessage = null,
                siteWorldCompletedRequiredPasses = draft.siteWorldReview.completedRequiredPasses,
                siteWorldRecordingState = SiteWorldRecordingState(),
            )
        } else {
            _uiState.value = _uiState.value.copy(
                reviewDraft = null,
                actionState = FinishedCaptureActionState.Idle,
                errorMessage = null,
                exportMessage = null,
                siteWorldRecordingState = SiteWorldRecordingState(),
            )
        }
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
                actionState = action,
                errorMessage = null,
            )

            // Alpha: skip AI intake resolution entirely — proceed directly with the raw request
            val skipResolution = true
            val syntheticResolution: IntakeResolutionOutcome = IntakeResolutionOutcome.Resolved(request)
            when (val resolution = if (skipResolution) syntheticResolution else intakeResolutionService.resolve(request)) {
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
                    // Alpha: AI intake is disabled — skip the manual form and proceed directly
                    val resolvedDraft = CaptureReviewDraft.fromResolution(
                        base = draft,
                        request = resolution.request,
                        helperText = "",
                        reviewTitle = "Capture complete",
                    ).copy(preparedCaptureId = captureId)
                    _uiState.value = _uiState.value.copy(
                        reviewDraft = resolvedDraft,
                        actionState = action,
                        errorMessage = null,
                    )
                    continueWithResolvedDraft(resolvedDraft, resolution.request, action)
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
            arcoreEvidenceDirectory = draft.arcoreEvidenceDirectory,
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

private fun workflowPassSequence(
    siteScale: SiteWorldSiteScale,
    criticalZones: Set<SiteWorldAnchorType>,
): List<String> {
    val roles = when (siteScale) {
        SiteWorldSiteScale.SmallSimple -> mutableListOf("primary", "loop_closure")
        SiteWorldSiteScale.Medium,
        SiteWorldSiteScale.MultiZone -> mutableListOf("primary", "revisit", "loop_closure")
    }
    if (criticalZones.isNotEmpty()) roles += "critical_zone_revisit"
    return roles
}

private fun plannedPassRoleFor(
    stageIndex: Int,
    siteScale: SiteWorldSiteScale = SiteWorldSiteScale.Medium,
    criticalZones: Set<SiteWorldAnchorType> = emptySet(),
): String {
    val roles = workflowPassSequence(siteScale, criticalZones)
    val clampedIndex = (stageIndex - 1).coerceIn(0, roles.lastIndex)
    return roles[clampedIndex]
}

private fun routePlanFor(siteScale: SiteWorldSiteScale): List<String> =
    when (siteScale) {
        SiteWorldSiteScale.SmallSimple -> listOf(
            "Lock at the entrance, capture one clean outbound route, then return on the same path.",
            "Pause once at the far end and once at a shared threshold before closing the loop.",
        )
        SiteWorldSiteScale.Medium -> listOf(
            "Lock at the entrance, follow the main spine, and pause at every doorway or intersection that branches the route.",
            "Add a reverse-direction revisit before the final loop closure.",
        )
        SiteWorldSiteScale.MultiZone -> listOf(
            "Lock at the entrance, use one hub or spine, and treat each zone as an out-and-back branch.",
            "Do not leave a zone until you have a shared threshold checkpoint and a return to the hub.",
        )
    }

private fun siteWorldCoveragePlan(
    siteScale: SiteWorldSiteScale,
    passRole: String,
    criticalZones: Set<SiteWorldAnchorType>,
): List<String> {
    val brief = passBriefFor(passRole, siteScale, criticalZones)
    return buildList {
        addAll(routePlanFor(siteScale))
        add(brief.summary)
        if (criticalZones.isNotEmpty()) {
            add(
                "Critical zone revisits requested for: ${
                    criticalZones.joinToString(", ") { it.label }
                }.",
            )
        }
    }
}

private fun siteWorldScaffoldingUsed(
    siteScale: SiteWorldSiteScale,
    passRole: String,
    criticalZones: Set<SiteWorldAnchorType>,
): List<String> = buildList {
    add("site_world_candidate")
    add("entry_anchor_hold")
    add("shared_checkpoint_prompts")
    add("pass_role_$passRole")
    if (siteScale == SiteWorldSiteScale.MultiZone) add("hub_return_plan")
    if (criticalZones.isNotEmpty()) add("critical_zone_revisits")
}

private fun currentCheckpointTarget(siteScale: SiteWorldSiteScale): Int =
    when (siteScale) {
        SiteWorldSiteScale.SmallSimple -> 2
        SiteWorldSiteScale.Medium -> 4
        SiteWorldSiteScale.MultiZone -> 6
    }

private fun passBriefFor(
    role: String,
    siteScale: SiteWorldSiteScale = SiteWorldSiteScale.Medium,
    criticalZones: Set<SiteWorldAnchorType> = emptySet(),
): SiteWorldPassBrief {
    return when (role) {
        "revisit" -> SiteWorldPassBrief(
            role = role,
            title = "Revisit Pass",
            summary = "Reverse through shared checkpoints before closing the route.",
            requiredCheckpointTarget = maxOf(1, currentCheckpointTarget(siteScale) / 2),
            requiredPrompt = "Turn back and reacquire the last checkpoint from the reverse direction before leaving this zone.",
            exactPrompts = listOf(
                "Turn back and reacquire the last checkpoint from the reverse direction before leaving this zone.",
                "Pause at the intersection. Sweep each branch briefly, then continue down your chosen path.",
            ),
        )
        "loop_closure" -> SiteWorldPassBrief(
            role = role,
            title = "Loop Closure",
            summary = "Return to the entrance or hub and match the starting view.",
            requiredCheckpointTarget = 1,
            requiredPrompt = "Return to your start anchor. Match the original entrance view as closely as practical, then hold for 3 seconds.",
            exactPrompts = listOf(
                "Return to your start anchor. Match the original entrance view as closely as practical, then hold for 3 seconds.",
                "Before leaving this shared area, pause and show the last checkpoint again for 2 seconds.",
            ),
        )
        "critical_zone_revisit" -> SiteWorldPassBrief(
            role = role,
            title = "Critical Zone Revisit",
            summary = "Reacquire operationally critical boundaries and handoff geometry.",
            requiredCheckpointTarget = maxOf(1, criticalZones.size),
            requiredPrompt = "Capture the static boundary, approach path, and exit path. Revisit once from the opposite direction.",
            exactPrompts = listOf(
                "This is a critical zone. Capture the static boundary, approach path, and exit path. Revisit once from the opposite direction.",
                "Match the earlier view within a few steps. Hold briefly. Show the same threshold or boundary geometry again.",
            ),
        )
        else -> SiteWorldPassBrief(
            role = "primary",
            title = "Primary Route",
            summary = when (siteScale) {
                SiteWorldSiteScale.SmallSimple -> "One clean outbound route, one far-end checkpoint, then return to the start."
                SiteWorldSiteScale.Medium -> "Cover the main spine and pause at doorways, intersections, and shared thresholds."
                SiteWorldSiteScale.MultiZone -> "Use a hub or spine and capture each zone as an out-and-back branch."
            },
            requiredCheckpointTarget = currentCheckpointTarget(siteScale),
            requiredPrompt = "Walk forward slowly. Pause at every major threshold or branch before moving on.",
            exactPrompts = listOf(
                "Stand at the main entry point. Hold still for 3 seconds. Slowly pan left, center, right. Keep the door frame, floor edge, and nearby wall in view.",
                "At this doorway, stop at the threshold. Show left frame, center opening, right frame. Then continue.",
            ),
        )
    }
}

private fun buildSiteWorldPassReview(
    siteScale: SiteWorldSiteScale,
    passAttemptIndex: Int,
    passRole: String,
    recordingState: SiteWorldRecordingState,
    criticalZones: Set<SiteWorldAnchorType>,
    completedRequiredPasses: Int,
): SiteWorldPassReview {
    val brief = passBriefFor(passRole, siteScale, criticalZones)
    val totalRequiredPasses = workflowPassSequence(siteScale, criticalZones).size
    val sharedAnchors = recordingState.markedAnchors.filter {
        it in setOf(
            SiteWorldAnchorType.Doorway,
            SiteWorldAnchorType.Intersection,
            SiteWorldAnchorType.DockTurn,
            SiteWorldAnchorType.HandoffPoint,
            SiteWorldAnchorType.FloorTransition,
            SiteWorldAnchorType.RestrictedBoundary,
        )
    }
    val anchorSet = recordingState.markedAnchors.toSet()
    val criticalMatches = criticalZones.intersect(anchorSet)
    val hasLoopAnchor = recordingState.entryLocked ||
        anchorSet.contains(SiteWorldAnchorType.Entrance) ||
        anchorSet.contains(SiteWorldAnchorType.ExitPoint)

    val completedItems = mutableListOf<String>()
    val missingItems = mutableListOf<String>()

    if (recordingState.entryLocked) {
        completedItems += "Entrance localization hold captured."
    } else {
        missingItems += "Entrance localization hold is required before the route counts."
    }

    when (passRole) {
        "revisit" -> {
            if (sharedAnchors.size >= brief.requiredCheckpointTarget) {
                completedItems += "Reverse-direction shared checkpoints captured."
            } else {
                missingItems += "Reacquire at least ${brief.requiredCheckpointTarget} doorway or intersection checkpoints in reverse."
            }
        }
        "loop_closure" -> {
            if (hasLoopAnchor) {
                completedItems += "Loop closure returned to the entrance or shared endpoint."
            } else {
                missingItems += "Return to the original entrance or shared endpoint before finishing this pass."
            }
        }
        "critical_zone_revisit" -> {
            if (criticalZones.isEmpty() || criticalMatches.isNotEmpty()) {
                completedItems += "Critical zone revisit captured."
            } else {
                missingItems += "Revisit one of the selected critical zones: ${criticalZones.joinToString(", ") { it.label }}."
            }
        }
        else -> {
            if (sharedAnchors.size >= brief.requiredCheckpointTarget) {
                completedItems += "Shared checkpoint target met."
            } else {
                missingItems += "Capture ${brief.requiredCheckpointTarget} shared checkpoints at doorways, intersections, or thresholds."
            }
        }
    }

    val weakSignalSummary = if (recordingState.weakSignalEvents > 0) {
        "weak_signal_events:${recordingState.weakSignalEvents}"
    } else {
        null
    }
    if (recordingState.weakSignalEvents > 0) {
        missingItems += "Weak segments were flagged and should be revisited before finishing."
    }

    val shouldAdvance = missingItems.isEmpty()
    val score = (100 - (missingItems.size * 18) - (recordingState.weakSignalEvents * 8)).coerceIn(20, 100)
    val tone = when {
        missingItems.isEmpty() -> SiteWorldReviewTone.Ready
        recordingState.weakSignalEvents > 0 -> SiteWorldReviewTone.ActionRequired
        else -> SiteWorldReviewTone.Caution
    }
    val nextCompletedRequiredPasses = if (shouldAdvance) {
        minOf(completedRequiredPasses + 1, totalRequiredPasses)
    } else {
        completedRequiredPasses
    }

    return SiteWorldPassReview(
        passAttemptIndex = passAttemptIndex,
        passRole = passRole,
        title = brief.title,
        tone = tone,
        score = score,
        summary = brief.summary,
        completedItems = completedItems,
        missingItems = missingItems,
        weakSignalSummary = weakSignalSummary,
        nextActionLabel = nextWorkflowActionLabel(
            passRole = passRole,
            shouldAdvance = shouldAdvance,
            hasWeakSignalConcern = recordingState.weakSignalEvents > 0,
            completedRequiredPasses = nextCompletedRequiredPasses,
            totalRequiredPasses = totalRequiredPasses,
            siteScale = siteScale,
            criticalZones = criticalZones,
        ),
        canFinishWorkflow = nextCompletedRequiredPasses >= totalRequiredPasses && recordingState.weakSignalEvents == 0,
        shouldAdvanceWorkflow = shouldAdvance,
        completedRequiredPasses = nextCompletedRequiredPasses,
        totalRequiredPasses = totalRequiredPasses,
        exactPrompts = brief.exactPrompts,
    )
}

private fun nextWorkflowActionLabel(
    passRole: String,
    shouldAdvance: Boolean,
    hasWeakSignalConcern: Boolean,
    completedRequiredPasses: Int,
    totalRequiredPasses: Int,
    siteScale: SiteWorldSiteScale,
    criticalZones: Set<SiteWorldAnchorType>,
): String? {
    if (hasWeakSignalConcern) return "Recapture weak segments"
    if (!shouldAdvance) {
        return when (passRole) {
            "loop_closure" -> "Retry loop closure"
            "critical_zone_revisit" -> "Retry critical zone revisit"
            else -> "Retake ${passBriefFor(passRole, siteScale, criticalZones).title.lowercase(Locale.US)}"
        }
    }
    if (completedRequiredPasses >= totalRequiredPasses) return null
    return when (plannedPassRoleFor(completedRequiredPasses + 1, siteScale, criticalZones)) {
        "revisit" -> "Start revisit pass"
        "loop_closure" -> "Start loop closure"
        "critical_zone_revisit" -> "Revisit critical zones"
        else -> "Start next pass"
    }
}
