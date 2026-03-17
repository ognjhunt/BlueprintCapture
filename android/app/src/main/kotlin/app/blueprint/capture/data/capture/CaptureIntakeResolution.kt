package app.blueprint.capture.data.capture

import javax.inject.Inject
import javax.inject.Singleton
import kotlin.math.roundToInt

data class CaptureManualIntakeDraft(
    val workflowName: String = "",
    val taskStepsText: String = "",
    val zone: String = "",
    val owner: String = "",
    val helperText: String = "Add a workflow name, at least one task step, and either a zone or owner.",
    val reviewTitle: String = "Complete Intake",
) {
    val taskSteps: List<String>
        get() = taskStepsText
            .split('\n')
            .map { it.trim() }
            .filter { it.isNotEmpty() }

    fun makePacket(): QualificationIntakePacket {
        return QualificationIntakePacket(
            workflowName = workflowName.trim().ifBlank { null },
            taskSteps = taskSteps,
            zone = zone.trim().ifBlank { null },
            owner = owner.trim().ifBlank { null },
        )
    }

    companion object {
        fun fromPacket(
            packet: QualificationIntakePacket?,
            helperText: String,
            reviewTitle: String = "Complete Intake",
        ): CaptureManualIntakeDraft {
            return CaptureManualIntakeDraft(
                workflowName = packet?.workflowName.orEmpty(),
                taskStepsText = packet?.taskSteps.orEmpty().joinToString(separator = "\n"),
                zone = packet?.zone.orEmpty(),
                owner = packet?.owner.orEmpty(),
                helperText = helperText,
                reviewTitle = reviewTitle,
            )
        }
    }
}

sealed interface IntakeResolutionOutcome {
    data class Resolved(val request: AndroidCaptureBundleRequest) : IntakeResolutionOutcome
    data class NeedsManualEntry(
        val request: AndroidCaptureBundleRequest,
        val draft: CaptureManualIntakeDraft,
    ) : IntakeResolutionOutcome
}

data class CaptureIntakeInferenceResult(
    val intakePacket: QualificationIntakePacket,
    val metadata: CaptureIntakeMetadata,
    val taskHypothesis: TaskHypothesis,
)

interface CaptureIntakeInferenceServiceProtocol {
    suspend fun inferIntake(request: AndroidCaptureBundleRequest): CaptureIntakeInferenceResult
}

@Singleton
class CaptureIntakeInferenceService @Inject constructor() : CaptureIntakeInferenceServiceProtocol {
    override suspend fun inferIntake(request: AndroidCaptureBundleRequest): CaptureIntakeInferenceResult {
        val contextParts = request.captureContextHint
            .orEmpty()
            .split('|')
            .map { it.trim() }
            .filter { it.isNotEmpty() && !it.startsWith("Notes:", ignoreCase = true) }

        val workflowName = request.workflowName
            ?.takeIf { it.isNotBlank() }
            ?: request.intakePacket?.workflowName
            ?: contextParts.firstOrNull()

        val taskSteps = request.taskSteps
            .filter { it.isNotBlank() }
            .ifEmpty { defaultTaskSteps(workflowName ?: contextParts.firstOrNull() ?: "capture walkthrough") }

        val zone = request.zone?.takeIf { it.isNotBlank() } ?: request.intakePacket?.zone
        val owner = request.owner?.takeIf { it.isNotBlank() } ?: request.intakePacket?.owner

        val warnings = mutableListOf<String>()
        if (request.workflowName.isNullOrBlank()) {
            warnings += "Workflow name was inferred from the capture context and should be confirmed."
        }
        if (request.taskSteps.isEmpty()) {
            warnings += "Task steps were inferred from the walkthrough context."
        }
        if (zone.isNullOrBlank() && owner.isNullOrBlank()) {
            warnings += "Add either a zone or owner before submission."
        }

        val packet = QualificationIntakePacket(
            workflowName = workflowName,
            taskSteps = taskSteps,
            zone = zone,
            owner = owner,
        )

        val confidence = buildConfidence(
            workflowPresent = !workflowName.isNullOrBlank(),
            stepCount = taskSteps.size,
            hasZoneOrOwner = !zone.isNullOrBlank() || !owner.isNullOrBlank(),
            hasContext = contextParts.isNotEmpty(),
        )

        val metadata = CaptureIntakeMetadata(
            source = CaptureIntakeSource.AiInferred,
            model = "android-local-heuristic-v1",
            fps = request.fpsSource.roundToInt(),
            confidence = confidence,
            warnings = warnings,
        )
        val taskHypothesis = TaskHypothesis(
            workflowName = workflowName,
            taskSteps = taskSteps,
            zone = zone,
            owner = owner,
            confidence = confidence,
            source = CaptureIntakeSource.AiInferred,
            model = metadata.model,
            fps = metadata.fps,
            warnings = warnings,
            status = if (packet.isComplete && confidence >= AUTO_ACCEPT_CONFIDENCE) {
                CaptureTaskHypothesisStatus.Accepted
            } else {
                CaptureTaskHypothesisStatus.NeedsConfirmation
            },
        )

        return CaptureIntakeInferenceResult(
            intakePacket = packet,
            metadata = metadata,
            taskHypothesis = taskHypothesis,
        )
    }

    private fun defaultTaskSteps(topic: String): List<String> {
        return listOf(
            "Start with a wide framing pass for $topic.",
            "Walk the main route slowly and hold transitions for review.",
            "Sweep corners, thresholds, and blockers before ending the capture.",
        )
    }

    private fun buildConfidence(
        workflowPresent: Boolean,
        stepCount: Int,
        hasZoneOrOwner: Boolean,
        hasContext: Boolean,
    ): Double {
        var confidence = 0.35
        if (workflowPresent) confidence += 0.2
        confidence += (stepCount.coerceAtMost(3) * 0.1)
        if (hasZoneOrOwner) confidence += 0.15
        if (hasContext) confidence += 0.1
        return confidence.coerceIn(0.4, 0.93)
    }

    private companion object {
        const val AUTO_ACCEPT_CONFIDENCE = 0.8
    }
}

@Singleton
class IntakeResolutionService @Inject constructor(
    private val inferenceService: CaptureIntakeInferenceService,
) {
    suspend fun resolve(request: AndroidCaptureBundleRequest): IntakeResolutionOutcome {
        if (request.intakePacket?.isComplete == true) {
            if (request.taskHypothesis?.status == CaptureTaskHypothesisStatus.NeedsConfirmation) {
                val draft = CaptureManualIntakeDraft.fromPacket(
                    packet = request.intakePacket,
                    helperText = manualEntryHelperText(request.taskHypothesis),
                    reviewTitle = "Review AI Task Guess",
                )
                return IntakeResolutionOutcome.NeedsManualEntry(request, draft)
            }

            val resolved = request.copy(
                intakeMetadata = request.intakeMetadata ?: CaptureIntakeMetadata(
                    source = CaptureIntakeSource.Authoritative,
                ),
                taskHypothesis = request.taskHypothesis ?: request.synthesizedTaskHypothesis(
                    status = CaptureTaskHypothesisStatus.Accepted,
                ),
            )
            return IntakeResolutionOutcome.Resolved(resolved)
        }

        return try {
            val inferred = inferenceService.inferIntake(request)
            val candidate = request.copy(
                workflowName = inferred.intakePacket.workflowName ?: request.workflowName,
                taskSteps = inferred.intakePacket.taskSteps.ifEmpty { request.taskSteps },
                zone = inferred.intakePacket.zone ?: request.zone,
                owner = inferred.intakePacket.owner ?: request.owner,
                intakePacket = inferred.intakePacket,
                intakeMetadata = inferred.metadata,
                taskHypothesis = inferred.taskHypothesis,
            )

            if (
                inferred.intakePacket.isComplete &&
                inferred.taskHypothesis.status == CaptureTaskHypothesisStatus.Accepted
            ) {
                IntakeResolutionOutcome.Resolved(candidate)
            } else {
                val draft = CaptureManualIntakeDraft.fromPacket(
                    packet = inferred.intakePacket,
                    helperText = manualEntryHelperText(inferred.taskHypothesis),
                    reviewTitle = "Review AI Task Guess",
                )
                IntakeResolutionOutcome.NeedsManualEntry(candidate, draft)
            }
        } catch (error: Exception) {
            val helperText = inferenceFailureHelperText(error)
            val draft = CaptureManualIntakeDraft.fromPacket(
                packet = request.intakePacket,
                helperText = helperText,
            )
            IntakeResolutionOutcome.NeedsManualEntry(request, draft)
        }
    }

    private fun manualEntryHelperText(taskHypothesis: TaskHypothesis?): String {
        if (taskHypothesis == null) {
            return "AI intake was unavailable. Enter minimal workflow details to continue."
        }

        val workflow = taskHypothesis.workflowName?.takeIf { it.isNotBlank() } ?: "Unknown task"
        val confidence = ((taskHypothesis.confidence ?: 0.0) * 100.0).roundToInt()
        val warningText = taskHypothesis.warnings
            .filter { it.isNotBlank() }
            .joinToString(separator = " ")
            .ifBlank { "Please confirm or edit the task before continuing." }
        return "We think this task is '$workflow' ($confidence% confidence). $warningText"
    }

    private fun inferenceFailureHelperText(error: Exception): String {
        val detail = error.localizedMessage ?: "Inference failed."
        return "AI intake failed: $detail"
    }
}

fun AndroidCaptureBundleRequest.withManualIntake(packet: QualificationIntakePacket): AndroidCaptureBundleRequest {
    val metadata = CaptureIntakeMetadata(source = CaptureIntakeSource.HumanManual)
    return copy(
        workflowName = packet.workflowName ?: workflowName,
        taskSteps = packet.taskSteps.ifEmpty { taskSteps },
        zone = packet.zone ?: zone,
        owner = packet.owner ?: owner,
        intakePacket = packet,
        intakeMetadata = metadata,
        taskHypothesis = synthesizedTaskHypothesis(
            packet = packet,
            metadata = metadata,
            status = CaptureTaskHypothesisStatus.Accepted,
        ),
    )
}

fun AndroidCaptureBundleRequest.synthesizedTaskHypothesis(
    packet: QualificationIntakePacket = intakePacket ?: QualificationIntakePacket(),
    metadata: CaptureIntakeMetadata = intakeMetadata ?: CaptureIntakeMetadata(source = CaptureIntakeSource.Authoritative),
    status: CaptureTaskHypothesisStatus = CaptureTaskHypothesisStatus.Accepted,
): TaskHypothesis {
    return TaskHypothesis(
        workflowName = packet.workflowName ?: workflowName,
        taskSteps = packet.taskSteps.ifEmpty { taskSteps },
        zone = packet.zone ?: zone,
        owner = packet.owner ?: owner,
        confidence = metadata.confidence,
        source = metadata.source,
        model = metadata.model,
        fps = metadata.fps,
        warnings = metadata.warnings,
        status = status,
    )
}
