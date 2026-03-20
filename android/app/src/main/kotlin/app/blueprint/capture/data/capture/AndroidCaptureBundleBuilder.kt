package app.blueprint.capture.data.capture

import java.io.File
import java.security.MessageDigest
import java.time.Instant
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
    val provenanceFile: File,
    val rightsConsentFile: File,
    val videoTrackFile: File,
    val hashesFile: File,
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

        val captureModality = captureModalityFor(request)
        val evidenceTier = evidenceTierFor(request, captureModality)
        val captureSource = if (request.captureSource == AndroidCaptureSource.MetaGlasses) "glasses" else "android"
        val captureTierHint = if (request.captureSource == AndroidCaptureSource.MetaGlasses) "tier2_glasses" else "tier2_android"
        val coordinateFrameSessionId = request.captureTopology?.captureSessionId ?: request.captureId
        val captureTopology = request.captureTopology ?: CaptureTopologyMetadata(
            captureSessionId = request.captureId,
            routeId = "route_unknown",
            passId = "pass_primary_1",
            passIndex = 1,
            intendedPassRole = "primary",
        )

        // -----------------------------------------------------------------
        // manifest.json
        // -----------------------------------------------------------------
        val manifest = CaptureManifest(
            sceneId = request.sceneId,
            captureId = request.captureId,
            videoUri = "raw/walkthrough.mp4",
            deviceModel = request.deviceModel,
            osVersion = request.osVersion,
            fpsSource = request.fpsSource,
            width = request.width,
            height = request.height,
            captureStartEpochMs = request.captureStartEpochMs,
            hasLiDAR = request.hasLiDAR,
            captureSource = captureSource,
            captureTierHint = captureTierHint,
            coordinateFrameSessionId = coordinateFrameSessionId,
            captureModality = captureModality,
            evidenceTier = evidenceTier,
            requestedOutputs = request.requestedOutputs,
            siteIdentity = request.siteIdentity,
            captureTopology = captureTopology,
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
            captureTopology = captureTopology,
            captureMode = request.captureMode,
        )

        val hypothesis = request.taskHypothesis ?: request.synthesizedTaskHypothesis()
        val completion = UploadComplete(
            sceneId = request.sceneId,
            captureId = request.captureId,
        )
        val rightsConsent = RightsConsentFile(
            sceneId = request.sceneId,
            captureId = request.captureId,
            captureContributorPayoutEligible = (request.quotedPayoutCents ?: 0) > 0,
            consentNotes = listOfNotNull(request.rightsProfile?.let { "rights_profile:$it" }),
        )
        val videoTrack = VideoTrackFile(
            videoFile = "walkthrough.mp4",
            durationSec = (request.captureDurationMs ?: 0L) / 1000.0,
            frameCount = (((request.captureDurationMs ?: 0L) / 1000.0) * request.fpsSource).toInt(),
            nominalFps = request.fpsSource,
            width = request.width,
            height = request.height,
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
        val intakeFile = rawDirectory.resolve("intake_packet.json")
            .also { it.writeText(json.encodeToString(request.intakePacket ?: QualificationIntakePacket())) }
        val completionFile = rawDirectory.resolve("capture_upload_complete.json")
            .also { it.writeText(json.encodeToString(completion)) }
        val rightsConsentFile = rawDirectory.resolve("rights_consent.json")
            .also { it.writeText(json.encodeToString(rightsConsent)) }
        val videoTrackFile = rawDirectory.resolve("video_track.json")
            .also { it.writeText(json.encodeToString(videoTrack)) }

        // -----------------------------------------------------------------
        // Phase 2 optional files — written only when data is present
        // -----------------------------------------------------------------
        val siteIdentityFile = request.siteIdentity?.let { identity ->
            rawDirectory.resolve("site_identity.json")
                .also { it.writeText(json.encodeToString(identity)) }
        }

        val captureTopologyFile = rawDirectory.resolve("capture_topology.json")
            .also { it.writeText(json.encodeToString(captureTopology)) }

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

        val provisionalProvenance = ProvenanceFile(
            sceneId = request.sceneId,
            captureId = request.captureId,
            captureSource = captureSource,
            capturedByUserId = request.creatorId,
            uploadedByUserId = request.creatorId,
            deviceInstallationId = request.creatorId,
            bundleCreatedAt = Instant.ofEpochMilli(request.captureStartEpochMs).toString(),
            uploadCompletedAt = Instant.now().toString(),
            bundleSha256 = "pending",
        )
        val provenanceFile = rawDirectory.resolve("provenance.json")
            .also { it.writeText(json.encodeToString(provisionalProvenance)) }

        val hashesFile = rawDirectory.resolve("hashes.json")
        val artifactHashes = buildArtifactHashes(rawDirectory, exclude = setOf("hashes.json"))
        val computedBundleHash = bundleHash(artifactHashes)
        val finalArtifactHashes = buildArtifactHashes(rawDirectory, exclude = setOf("hashes.json"))
        provenanceFile.writeText(json.encodeToString(provisionalProvenance.copy(bundleSha256 = computedBundleHash)))
        hashesFile.writeText(json.encodeToString(HashesFile(bundleSha256 = bundleHash(finalArtifactHashes), artifacts = finalArtifactHashes)))

        return AndroidCaptureBundleResult(
            captureRoot = captureRoot,
            rawDirectory = rawDirectory,
            manifestFile = manifestFile,
            contextFile = contextFile,
            hypothesisFile = hypothesisFile,
            intakeFile = intakeFile,
            completionFile = completionFile,
            provenanceFile = provenanceFile,
            rightsConsentFile = rightsConsentFile,
            videoTrackFile = videoTrackFile,
            hashesFile = hashesFile,
            siteIdentityFile = siteIdentityFile,
            captureTopologyFile = captureTopologyFile,
            captureModeFile = captureModeFile,
            scaffoldingPacketFile = scaffoldingPacketFile,
            imuSamplesFile = imuSamplesFile,
        )
    }

    private fun captureModalityFor(request: AndroidCaptureBundleRequest): String {
        val hasScaffolding = !request.scaffoldingPacket?.scaffoldingUsed.isNullOrEmpty()
        return when (request.captureSource) {
            AndroidCaptureSource.MetaGlasses ->
                if (hasScaffolding) "glasses_plus_scaffolding" else "glasses_video_only"
            AndroidCaptureSource.AndroidPhone ->
                if (hasScaffolding) "android_plus_scaffolding" else "android_video_only"
        }
    }

    private fun evidenceTierFor(request: AndroidCaptureBundleRequest, captureModality: String): String {
        val intakeComplete = request.intakePacket?.isComplete == true
        val scaffolding = request.scaffoldingPacket
        val validatedMetricBundle = !scaffolding?.calibrationAssets.isNullOrEmpty() &&
            (scaffolding?.validatedScaleMeters != null) &&
            (scaffolding?.validatedPoseCoverage ?: 0.0) >= 0.7 &&
            (scaffolding?.hiddenZoneBound ?: 1.0) <= 0.35 &&
            !scaffolding?.scaleAnchorAssets.isNullOrEmpty() &&
            !scaffolding?.checkpointAssets.isNullOrEmpty()
        if (
            captureModality in setOf("glasses_plus_scaffolding", "android_plus_scaffolding") &&
            intakeComplete &&
            validatedMetricBundle
        ) {
            return "video_with_validated_scaffolding"
        }
        return "pre_screen_video"
    }

    private fun buildArtifactHashes(root: File, exclude: Set<String>): Map<String, String> {
        val files = root.walkTopDown()
            .filter { it.isFile && it.name !in exclude }
            .sortedBy { it.relativeTo(root).invariantSeparatorsPath }
            .toList()
        return files.associate { file ->
            file.relativeTo(root).invariantSeparatorsPath to sha256(file.readBytes())
        }
    }

    private fun bundleHash(artifactHashes: Map<String, String>): String {
        val canonical = artifactHashes.entries
            .sortedBy { it.key }
            .joinToString("\n") { (path, hash) -> "$path:$hash" }
        return sha256(canonical.toByteArray())
    }

    private fun sha256(bytes: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(bytes)
        return digest.joinToString("") { "%02x".format(it) }
    }
}
