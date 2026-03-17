package app.blueprint.capture.data.capture

import java.io.File
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

data class AndroidCaptureBundleResult(
    val captureRoot: File,
    val rawDirectory: File,
    val manifestFile: File,
    val contextFile: File,
    val hypothesisFile: File,
    val intakeFile: File?,
    val completionFile: File,
)

@Singleton
class AndroidCaptureBundleBuilder @Inject constructor() {
    private val json = Json {
        prettyPrint = true
        encodeDefaults = true
        explicitNulls = false
    }

    fun writeBundle(
        outputRoot: File,
        request: AndroidCaptureBundleRequest,
        walkthroughSource: File,
    ): AndroidCaptureBundleResult {
        val captureRoot = outputRoot.resolve("scenes/${request.sceneId}/captures/${request.captureId}")
        val rawDirectory = captureRoot.resolve("raw")
        rawDirectory.mkdirs()

        val walkthroughTarget = rawDirectory.resolve("walkthrough.mp4")
        walkthroughSource.copyTo(walkthroughTarget, overwrite = true)

        val manifest = CaptureManifest(
            sceneId = request.sceneId,
            videoUri = "raw/walkthrough.mp4",
            deviceModel = request.deviceModel,
            osVersion = request.osVersion,
            fpsSource = request.fpsSource,
            width = request.width,
            height = request.height,
            captureStartEpochMs = request.captureStartEpochMs,
            hasLiDAR = request.hasLiDAR,
            requestedOutputs = request.requestedOutputs,
            taskTextHint = request.intakePacket?.workflowName ?: request.workflowName ?: request.captureContextHint,
            taskSteps = request.intakePacket?.taskSteps ?: request.taskSteps,
            zone = request.intakePacket?.zone ?: request.zone,
            owner = request.intakePacket?.owner ?: request.owner,
            sceneMemoryCapture = SceneMemoryCapture(
                operatorNotes = request.operatorNotes,
            ),
            captureRights = CaptureRights(
                payoutEligible = (request.quotedPayoutCents ?: 0) > 0,
                consentNotes = listOfNotNull(request.rightsProfile?.let { "rights_profile:$it" }),
            ),
            captureEvidence = CaptureEvidence(),
        )
        val context = CaptureContext(
            siteSubmissionId = request.siteSubmissionId ?: request.sceneId,
            taskTextHint = request.intakePacket?.workflowName ?: request.workflowName ?: request.captureContextHint,
            taskSteps = request.intakePacket?.taskSteps ?: request.taskSteps,
            zone = request.intakePacket?.zone ?: request.zone,
            owner = request.intakePacket?.owner ?: request.owner,
            operatorNotes = request.operatorNotes,
        )
        val hypothesis = TaskHypothesis(
            workflowName = request.intakePacket?.workflowName ?: request.workflowName,
            taskSteps = request.intakePacket?.taskSteps ?: request.taskSteps,
            zone = request.intakePacket?.zone ?: request.zone,
            owner = request.intakePacket?.owner ?: request.owner,
        )
        val completion = UploadComplete(
            sceneId = request.sceneId,
            captureId = request.captureId,
        )

        val manifestFile = rawDirectory.resolve("manifest.json").also { it.writeText(json.encodeToString(manifest)) }
        val contextFile = rawDirectory.resolve("capture_context.json").also { it.writeText(json.encodeToString(context)) }
        val hypothesisFile = rawDirectory.resolve("task_hypothesis.json").also { it.writeText(json.encodeToString(hypothesis)) }
        val intakeFile = request.intakePacket?.let { packet ->
            rawDirectory.resolve("intake_packet.json").also { it.writeText(json.encodeToString(packet)) }
        }
        val completionFile = rawDirectory.resolve("capture_upload_complete.json").also {
            it.writeText(json.encodeToString(completion))
        }

        return AndroidCaptureBundleResult(
            captureRoot = captureRoot,
            rawDirectory = rawDirectory,
            manifestFile = manifestFile,
            contextFile = contextFile,
            hypothesisFile = hypothesisFile,
            intakeFile = intakeFile,
            completionFile = completionFile,
        )
    }
}
