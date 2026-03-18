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
    // Phase 2 optional files
    val siteIdentityFile: File?,
    val captureTopologyFile: File?,
    val captureModeFile: File?,
    val scaffoldingPacketFile: File?,
    val imuSamplesFile: File?,
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
        imuSamplesSource: File? = null,
    ): AndroidCaptureBundleResult {
        val captureRoot = outputRoot.resolve("scenes/${request.sceneId}/captures/${request.captureId}")
        val rawDirectory = captureRoot.resolve("raw")
        rawDirectory.mkdirs()

        walkthroughSource.copyTo(rawDirectory.resolve("walkthrough.mp4"), overwrite = true)

        // -----------------------------------------------------------------
        // manifest.json
        // -----------------------------------------------------------------
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
            siteIdentity = request.siteIdentity,
            captureTopology = request.captureTopology,
            captureMode = request.captureMode,
            taskTextHint = request.intakePacket?.workflowName
                ?: request.workflowName
                ?: request.captureContextHint,
            taskSteps = request.intakePacket?.taskSteps ?: request.taskSteps,
            zone = request.intakePacket?.zone ?: request.zone,
            owner = request.intakePacket?.owner ?: request.owner,
            sceneMemoryCapture = SceneMemoryCapture(
                operatorNotes = request.operatorNotes,
                motionProvenance = if (request.motionSampleCount > 0)
                    "phone_imu_accelerometer_gyroscope"
                else
                    "phone_imu_diagnostic_only",
                motionTimestampsCaptureRelative = true,
            ),
            captureRights = CaptureRights(
                payoutEligible = (request.quotedPayoutCents ?: 0) > 0,
                consentNotes = listOfNotNull(
                    request.rightsProfile?.let { "rights_profile:$it" },
                    request.siteIdentity?.siteIdSource?.let { "site_id_source:$it" },
                ),
            ),
            captureEvidence = CaptureEvidence(
                motionSamples = request.motionSampleCount,
                motionProvenance = if (request.motionSampleCount > 0)
                    "phone_imu_accelerometer_gyroscope"
                else
                    "phone_imu_diagnostic_only",
                motionTimestampsCaptureRelative = true,
            ),
        )

        // -----------------------------------------------------------------
        // capture_context.json
        // -----------------------------------------------------------------
        val context = CaptureContext(
            siteSubmissionId = request.siteSubmissionId ?: request.sceneId,
            taskTextHint = request.intakePacket?.workflowName
                ?: request.workflowName
                ?: request.captureContextHint,
            taskSteps = request.intakePacket?.taskSteps ?: request.taskSteps,
            zone = request.intakePacket?.zone ?: request.zone,
            owner = request.intakePacket?.owner ?: request.owner,
            operatorNotes = request.operatorNotes,
            captureEvidence = CaptureEvidence(
                motionSamples = request.motionSampleCount,
                motionProvenance = if (request.motionSampleCount > 0)
                    "phone_imu_accelerometer_gyroscope"
                else
                    "phone_imu_diagnostic_only",
            ),
            captureRights = CaptureRights(
                payoutEligible = (request.quotedPayoutCents ?: 0) > 0,
            ),
            siteIdentity = request.siteIdentity,
            captureTopology = request.captureTopology,
            captureMode = request.captureMode,
        )

        val hypothesis = request.taskHypothesis ?: request.synthesizedTaskHypothesis()
        val completion = UploadComplete(
            sceneId = request.sceneId,
            captureId = request.captureId,
        )

        // -----------------------------------------------------------------
        // Write core files
        // -----------------------------------------------------------------
        val manifestFile = rawDirectory.resolve("manifest.json")
            .also { it.writeText(json.encodeToString(manifest)) }
        val contextFile = rawDirectory.resolve("capture_context.json")
            .also { it.writeText(json.encodeToString(context)) }
        val hypothesisFile = rawDirectory.resolve("task_hypothesis.json")
            .also { it.writeText(json.encodeToString(hypothesis)) }
        val intakeFile = request.intakePacket?.let { packet ->
            rawDirectory.resolve("intake_packet.json")
                .also { it.writeText(json.encodeToString(packet)) }
        }
        val completionFile = rawDirectory.resolve("capture_upload_complete.json")
            .also { it.writeText(json.encodeToString(completion)) }

        // -----------------------------------------------------------------
        // Phase 2 optional files — written only when data is present
        // -----------------------------------------------------------------
        val siteIdentityFile = request.siteIdentity?.let { identity ->
            rawDirectory.resolve("site_identity.json")
                .also { it.writeText(json.encodeToString(identity)) }
        }

        val captureTopologyFile = request.captureTopology?.let { topology ->
            rawDirectory.resolve("capture_topology.json")
                .also { it.writeText(json.encodeToString(topology)) }
        }

        val captureModeFile = request.captureMode?.let { mode ->
            rawDirectory.resolve("capture_mode.json")
                .also { it.writeText(json.encodeToString(mode)) }
        }

        val scaffoldingPacketFile = request.scaffoldingPacket?.let { packet ->
            rawDirectory.resolve("scaffolding_packet.json")
                .also { it.writeText(json.encodeToString(packet)) }
        }

        // IMU samples — copy pre-written file from sampler if present
        val imuSamplesFile = imuSamplesSource?.takeIf { it.exists() && it.length() > 0 }?.let {
            val dest = rawDirectory.resolve("imu_samples.jsonl")
            it.copyTo(dest, overwrite = true)
            dest
        }

        return AndroidCaptureBundleResult(
            captureRoot = captureRoot,
            rawDirectory = rawDirectory,
            manifestFile = manifestFile,
            contextFile = contextFile,
            hypothesisFile = hypothesisFile,
            intakeFile = intakeFile,
            completionFile = completionFile,
            siteIdentityFile = siteIdentityFile,
            captureTopologyFile = captureTopologyFile,
            captureModeFile = captureModeFile,
            scaffoldingPacketFile = scaffoldingPacketFile,
            imuSamplesFile = imuSamplesFile,
        )
    }
}
