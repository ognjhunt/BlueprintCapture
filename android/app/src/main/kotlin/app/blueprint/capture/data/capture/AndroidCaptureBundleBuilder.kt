package app.blueprint.capture.data.capture

import java.io.File
import java.security.MessageDigest
import java.time.Instant
import java.util.Locale
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject

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
    private val lineJson = Json {
        prettyPrint = false
        encodeDefaults = true
        explicitNulls = false
    }

    private data class BundleEvidence(
        val captureProfileId: String,
        val captureModality: String,
        val geometrySource: String?,
        val geometryExpectedDownstream: Boolean,
        val sensorAvailability: SensorAvailability,
        val captureEvidence: CaptureEvidence,
        val captureCapabilities: CaptureCapabilities,
        val motionProvenance: String?,
        val motionAuthority: CaptureAuthority,
    )

    private data class MaterializedMotionFiles(
        val motionFile: File,
        val diagnosticImuFile: File?,
    )

    fun writeBundle(
        outputRoot: File,
        request: AndroidCaptureBundleRequest,
        walkthroughSource: File,
        imuSamplesSource: File? = null,
        arcoreEvidenceDirectory: File? = null,
        glassesEvidenceDirectory: File? = null,
        companionPhoneDirectory: File? = null,
    ): AndroidCaptureBundleResult {
        val captureRoot = outputRoot.resolve("scenes/${request.sceneId}/captures/${request.captureId}")
        val rawDirectory = captureRoot.resolve("raw")
        rawDirectory.mkdirs()

        walkthroughSource.copyTo(rawDirectory.resolve("walkthrough.mp4"), overwrite = true)
        val arcoreRawDirectory = rawDirectory.resolve("arcore")
        if (request.captureSource == AndroidCaptureSource.AndroidXrGlasses) {
            arcoreRawDirectory.deleteRecursively()
        } else {
            arcoreEvidenceDirectory?.takeIf { it.exists() }?.let { copyDirectory(it, arcoreRawDirectory) }
        }
        glassesEvidenceDirectory?.takeIf { it.exists() }?.let { copyDirectory(it, rawDirectory.resolve("glasses")) }
        companionPhoneDirectory?.takeIf { it.exists() }?.let { copyDirectory(it, rawDirectory.resolve("companion_phone")) }
        val motionFiles = materializeMotionFiles(rawDirectory, imuSamplesSource)
        val motionSamplesFile = motionFiles.motionFile
        val arcoreRoot = rawDirectory.resolve("arcore")
        val relocalizationEvents = deriveRelocalizationEvents(arcoreRoot.resolve("tracking_state.jsonl"))
        materializeSyncMap(
            rawDirectory = rawDirectory,
            framesFile = arcoreRoot.resolve("frames.jsonl"),
            posesFile = arcoreRoot.resolve("poses.jsonl"),
            fallbackCoordinateFrameSessionId = request.captureTopology?.captureSessionId ?: request.captureId,
        )

        val bundleEvidence = inspectEvidence(
            request = request,
            rawDirectory = rawDirectory,
            motionFile = motionSamplesFile,
            relocalizationEvents = relocalizationEvents,
        )

        val captureModality = bundleEvidence.captureModality
        val evidenceTier = evidenceTierFor(request, captureModality)
        val captureSource = if (request.captureSource == AndroidCaptureSource.AndroidPhone) "android" else "glasses"
        val captureTierHint = if (request.captureSource == AndroidCaptureSource.AndroidPhone) "tier2_android" else "tier2_glasses"
        val coordinateFrameSessionId = request.captureTopology?.captureSessionId ?: request.captureId
        val upstreamHandoff = upstreamHandoffFor(request)
        val captureTopology = request.captureTopology ?: CaptureTopologyMetadata(
            captureSessionId = request.captureId,
            routeId = "route_unknown",
            passId = "pass_primary_1",
            passIndex = 1,
            intendedPassRole = "primary",
        )
        val recordingWorldFrame = recordingWorldFrameFor(bundleEvidence)

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
            captureProfileId = bundleEvidence.captureProfileId,
            evidenceTier = evidenceTier,
            rightsProfile = request.rightsProfile ?: "unknown",
            requestedOutputs = request.requestedOutputs,
            siteSubmissionId = request.siteSubmissionId,
            buyerRequestId = request.buyerRequestId,
            captureJobId = request.captureJobId,
            upstreamHandoff = upstreamHandoff,
            siteIdentity = request.siteIdentity,
            captureTopology = captureTopology,
            captureMode = request.captureMode,
            taskTextHint = request.intakePacket?.workflowName
                ?: request.workflowName
                ?: request.captureContextHint,
            taskSteps = request.intakePacket?.taskSteps ?: request.taskSteps,
            targetKPI = request.intakePacket?.targetKPI,
            zone = request.intakePacket?.zone ?: request.zone,
            owner = request.intakePacket?.owner ?: request.owner,
            sceneMemoryCapture = SceneMemoryCapture(
                sensorAvailability = bundleEvidence.sensorAvailability,
                operatorNotes = request.operatorNotes,
                inaccessibleAreas = request.inaccessibleAreas,
                motionProvenance = bundleEvidence.motionProvenance,
                motionTimestampsCaptureRelative = bundleEvidence.captureEvidence.motionTimestampsCaptureRelative,
                geometrySource = bundleEvidence.geometrySource,
                geometryExpectedDownstream = bundleEvidence.geometryExpectedDownstream,
            ),
            captureRights = CaptureRights(
                payoutEligible = captureContributorPayoutEligible(request),
                consentNotes = listOfNotNull(
                    request.rightsProfile?.let { "rights_profile:$it" },
                    request.siteIdentity?.siteIdSource?.let { "site_id_source:$it" },
                ),
            ),
            captureEvidence = bundleEvidence.captureEvidence,
            captureCapabilities = bundleEvidence.captureCapabilities,
        )

        // -----------------------------------------------------------------
        // capture_context.json
        // -----------------------------------------------------------------
        val context = CaptureContext(
            sceneId = request.sceneId,
            captureId = request.captureId,
            siteSubmissionId = request.siteSubmissionId,
            buyerRequestId = request.buyerRequestId,
            captureJobId = request.captureJobId,
            upstreamHandoff = upstreamHandoff,
            captureSource = captureSource,
            requestedOutputs = request.requestedOutputs,
            taskTextHint = request.intakePacket?.workflowName
                ?: request.workflowName
                ?: request.captureContextHint,
            taskSteps = request.intakePacket?.taskSteps ?: request.taskSteps,
            targetKPI = request.intakePacket?.targetKPI,
            zone = request.intakePacket?.zone ?: request.zone,
            owner = request.intakePacket?.owner ?: request.owner,
            operatorNotes = request.operatorNotes,
            captureEvidence = bundleEvidence.captureEvidence,
            captureProfileId = bundleEvidence.captureProfileId,
            captureCapabilities = bundleEvidence.captureCapabilities,
            captureRights = CaptureRights(payoutEligible = captureContributorPayoutEligible(request)),
            sceneMemory = SceneMemoryCapture(
                sensorAvailability = bundleEvidence.sensorAvailability,
                operatorNotes = request.operatorNotes,
                inaccessibleAreas = request.inaccessibleAreas,
                motionProvenance = bundleEvidence.motionProvenance,
                motionTimestampsCaptureRelative = bundleEvidence.captureEvidence.motionTimestampsCaptureRelative,
                geometrySource = bundleEvidence.geometrySource,
                geometryExpectedDownstream = bundleEvidence.geometryExpectedDownstream,
            ),
            siteIdentity = request.siteIdentity,
            captureTopology = captureTopology,
            captureMode = request.captureMode,
        )

        val hypothesis = request.taskHypothesis ?: synthesizeTaskHypothesis(request)
        val completion = UploadComplete(
            sceneId = request.sceneId,
            captureId = request.captureId,
        )
        val rightsConsent = RightsConsentFile(
            sceneId = request.sceneId,
            captureId = request.captureId,
            captureContributorPayoutEligible = captureContributorPayoutEligible(request),
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
        rawDirectory.resolve("recording_session.json").writeText(
            json.encodeToString(
                RecordingSessionFile(
                    sceneId = request.sceneId,
                    captureId = request.captureId,
                    siteVisitId = captureTopology.captureSessionId,
                    routeId = captureTopology.routeId,
                    passId = captureTopology.passId,
                    passIndex = captureTopology.passIndex,
                    passRole = captureTopology.intendedPassRole,
                    coordinateFrameSessionId = coordinateFrameSessionId,
                    arkitSessionId = coordinateFrameSessionId,
                    worldFrameDefinition = recordingWorldFrame.worldFrameDefinition,
                    units = recordingWorldFrame.units,
                    handedness = recordingWorldFrame.handedness,
                    gravityAligned = recordingWorldFrame.gravityAligned,
                    sessionResetCount = recordingWorldFrame.sessionResetCount,
                    capturedAt = Instant.ofEpochMilli(request.captureStartEpochMs).toString(),
                ),
            ),
        )
        rawDirectory.resolve("route_anchors.json")
            .writeText(json.encodeToString(RouteAnchorsFile()))
        rawDirectory.resolve("checkpoint_events.json")
            .writeText(json.encodeToString(CheckpointEventsFile()))
        rawDirectory.resolve("relocalization_events.json")
            .writeText(json.encodeToString(RelocalizationEventsFile(relocalizationEvents = relocalizationEvents)))
        rawDirectory.resolve("overlap_graph.json")
            .writeText(
                json.encodeToString(
                    OverlapGraphFile(
                        siteVisitId = captureTopology.captureSessionId,
                        routeId = captureTopology.routeId,
                        passId = captureTopology.passId,
                        passRole = captureTopology.intendedPassRole,
                        coordinateFrameSessionId = coordinateFrameSessionId,
                        relocalizationEventCount = relocalizationEvents.size,
                    ),
                ),
            )
        rawDirectory.resolve("semantic_anchor_observations.jsonl").writeText("")

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
        val imuSamplesFile = motionFiles.diagnosticImuFile ?: motionSamplesFile

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
        provenanceFile.writeText(json.encodeToString(provisionalProvenance.copy(bundleSha256 = computedBundleHash)))
        val finalArtifactHashes = buildArtifactHashes(rawDirectory, exclude = setOf("hashes.json"))
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
            AndroidCaptureSource.AndroidXrGlasses ->
                if (hasScaffolding) "android_xr_plus_scaffolding" else "android_xr_video_only"
            AndroidCaptureSource.AndroidPhone ->
                if (hasScaffolding) "android_plus_scaffolding" else "android_video_only"
        }
    }

    private fun upstreamHandoffFor(request: AndroidCaptureBundleRequest): UpstreamHandoff {
        val siteSubmissionId = request.siteSubmissionId?.trim()?.takeIf { it.isNotEmpty() }
        val buyerRequestId = request.buyerRequestId?.trim()?.takeIf { it.isNotEmpty() }
        val captureJobId = request.captureJobId?.trim()?.takeIf { it.isNotEmpty() }
        val blockers = buildList {
            if (siteSubmissionId == null) add("missing_site_submission_id")
            if (buyerRequestId == null) add("missing_buyer_request_id")
            if (captureJobId == null) add("missing_capture_job_id")
        }
        return UpstreamHandoff(
            siteSubmissionId = siteSubmissionId,
            buyerRequestId = buyerRequestId,
            captureJobId = captureJobId,
            siteSubmissionIdPresent = siteSubmissionId != null,
            buyerRequestIdPresent = buyerRequestId != null,
            captureJobIdPresent = captureJobId != null,
            hostedReviewTruthState = if (blockers.isEmpty()) "upstream_ids_present" else "blocked_missing_upstream_ids",
            blockers = blockers,
        )
    }

    private fun evidenceTierFor(request: AndroidCaptureBundleRequest, captureModality: String): String {
        val intakeComplete = isIntakeComplete(request.intakePacket)
        val scaffolding = request.scaffoldingPacket
        val validatedMetricBundle = !scaffolding?.calibrationAssets.isNullOrEmpty() &&
            (scaffolding?.validatedScaleMeters != null) &&
            (scaffolding?.validatedPoseCoverage ?: 0.0) >= 0.7 &&
            (scaffolding?.hiddenZoneBound ?: 1.0) <= 0.35 &&
            !scaffolding?.scaleAnchorAssets.isNullOrEmpty() &&
            !scaffolding?.checkpointAssets.isNullOrEmpty()
        if (
            captureModality in setOf("glasses_plus_scaffolding", "android_plus_scaffolding", "android_xr_plus_scaffolding") &&
            intakeComplete &&
            validatedMetricBundle
        ) {
            return "video_with_validated_scaffolding"
        }
        return "pre_screen_video"
    }

    private fun inspectEvidence(
        request: AndroidCaptureBundleRequest,
        rawDirectory: File,
        motionFile: File?,
        relocalizationEvents: List<RelocalizationEventRecord>,
    ): BundleEvidence {
        val arcoreRoot = rawDirectory.resolve("arcore")
        val glassesRoot = rawDirectory.resolve("glasses")
        val companionPhoneRoot = rawDirectory.resolve("companion_phone")
        val allowArcoreEvidence = request.captureSource != AndroidCaptureSource.AndroidXrGlasses
        val arcorePoseRows = if (allowArcoreEvidence) countJsonlRows(arcoreRoot.resolve("poses.jsonl")) else 0
        val arcoreIntrinsicsValid =
            allowArcoreEvidence && isValidIntrinsicsFile(arcoreRoot.resolve("session_intrinsics.json"))
        val arcoreDepthFrames = maxOf(
            if (allowArcoreEvidence) countFiles(arcoreRoot.resolve("depth")) else 0,
            if (allowArcoreEvidence) countManifestFrames(arcoreRoot.resolve("depth_manifest.json")) else 0,
        )
        val arcoreConfidenceFrames = maxOf(
            if (allowArcoreEvidence) countFiles(arcoreRoot.resolve("confidence")) else 0,
            if (allowArcoreEvidence) countManifestFrames(arcoreRoot.resolve("confidence_manifest.json")) else 0,
        )
        val arcorePointCloudSamples =
            if (allowArcoreEvidence) countJsonlRows(arcoreRoot.resolve("point_cloud.jsonl")) else 0
        val arcorePlaneRows = if (allowArcoreEvidence) countJsonlRows(arcoreRoot.resolve("planes.jsonl")) else 0
        val arcoreTrackingStateRows =
            if (allowArcoreEvidence) countJsonlRows(arcoreRoot.resolve("tracking_state.jsonl")) else 0
        val arcoreLightEstimateRows =
            if (allowArcoreEvidence) countJsonlRows(arcoreRoot.resolve("light_estimates.jsonl")) else 0
        val glassesFrameTimestampRows = countJsonlRows(glassesRoot.resolve("frame_timestamps.jsonl"))
        val glassesDeviceStateRows = countJsonlRows(glassesRoot.resolve("device_state.jsonl"))
        val glassesHealthEventRows = countJsonlRows(glassesRoot.resolve("health_events.jsonl"))
        val companionPhonePoseRows = countJsonlRows(companionPhoneRoot.resolve("poses.jsonl"))
        val companionPhoneIntrinsicsValid = isValidIntrinsicsFile(companionPhoneRoot.resolve("session_intrinsics.json"))
        val companionPhoneCalibration = companionPhoneRoot.resolve("calibration.json").exists()
        val motionSamples = countJsonlRows(motionFile)
        val isGlassesCapture = request.captureSource == AndroidCaptureSource.MetaGlasses ||
            request.captureSource == AndroidCaptureSource.AndroidXrGlasses
        val motionProvenance =
            if (isGlassesCapture && motionSamples > 0) {
                "phone_imu_diagnostic_only"
            } else if (motionSamples > 0) {
                "phone_imu_accelerometer_gyroscope"
            } else {
                null
            }
        val motionAuthority =
            if (isGlassesCapture && motionSamples > 0) {
                CaptureAuthority.DiagnosticOnly
            } else if (motionSamples > 0) CaptureAuthority.AuthoritativeRaw
            else CaptureAuthority.NotAvailable
        val missingDepthReason =
            if (arcoreDepthFrames > 0) null
            else if (arcorePoseRows > 0 || arcoreIntrinsicsValid) "not_enabled"
            else "not_supported"
        val captureProfileId = when {
            request.captureSource == AndroidCaptureSource.MetaGlasses &&
                (companionPhonePoseRows > 0 || companionPhoneIntrinsicsValid) -> "glasses_pov_companion_phone"
            request.captureSource == AndroidCaptureSource.MetaGlasses -> "glasses_pov"
            request.captureSource == AndroidCaptureSource.AndroidXrGlasses -> "android_xr_glasses"
            arcorePoseRows > 0 && arcoreIntrinsicsValid && arcoreDepthFrames > 0 -> "android_arcore_depth"
            arcorePoseRows > 0 && arcoreIntrinsicsValid -> "android_arcore_pose_only"
            else -> "android_camera_only"
        }
        val captureModality = when {
            request.captureSource == AndroidCaptureSource.MetaGlasses &&
                (companionPhonePoseRows > 0 || !request.scaffoldingPacket?.scaffoldingUsed.isNullOrEmpty()) -> "glasses_plus_scaffolding"
            request.captureSource == AndroidCaptureSource.MetaGlasses -> "glasses_video_only"
            request.captureSource == AndroidCaptureSource.AndroidXrGlasses &&
                !request.scaffoldingPacket?.scaffoldingUsed.isNullOrEmpty() -> "android_xr_plus_scaffolding"
            request.captureSource == AndroidCaptureSource.AndroidXrGlasses -> "android_xr_video_only"
            arcorePoseRows > 0 && arcoreIntrinsicsValid && arcoreDepthFrames > 0 -> "android_arcore_depth"
            arcorePoseRows > 0 && arcoreIntrinsicsValid -> "android_arcore_pose_only"
            !request.scaffoldingPacket?.scaffoldingUsed.isNullOrEmpty() -> "android_plus_scaffolding"
            else -> "android_video_only"
        }
        val geometrySource = when {
            arcorePoseRows > 0 -> "arcore"
            companionPhonePoseRows > 0 -> "companion_phone"
            else -> null
        }
        val geometryExpectedDownstream = geometrySource != null
        val poseAuthority = when {
            arcorePoseRows > 0 -> CaptureAuthority.RawTrackingOnly
            request.captureSource == AndroidCaptureSource.MetaGlasses -> CaptureAuthority.NotAvailable
            request.captureSource == AndroidCaptureSource.AndroidXrGlasses -> CaptureAuthority.NotAvailable
            else -> CaptureAuthority.NotAvailable
        }
        val intrinsicsAuthority = if (arcoreIntrinsicsValid) CaptureAuthority.RawTrackingOnly else CaptureAuthority.NotAvailable
        val depthAuthority = if (arcoreDepthFrames > 0) CaptureAuthority.RawTrackingOnly else CaptureAuthority.NotAvailable
        val sensorAvailability = SensorAvailability(
            arkitPoses = false,
            arkitIntrinsics = false,
            arkitDepth = false,
            arkitConfidence = false,
            arkitMeshes = false,
            cameraPose = arcorePoseRows > 0,
            cameraIntrinsics = arcoreIntrinsicsValid,
            depth = arcoreDepthFrames > 0,
            depthConfidence = arcoreConfidenceFrames > 0,
            missingDepthReason = missingDepthReason,
            mesh = false,
            pointCloud = arcorePointCloudSamples > 0,
            planes = arcorePlaneRows > 0,
            featurePoints = false,
            trackingState = arcoreTrackingStateRows > 0,
            relocalizationEvents = relocalizationEvents.isNotEmpty(),
            lightEstimate = arcoreLightEstimateRows > 0,
            geospatial = false,
            motion = motionSamples > 0,
            motionAuthoritative = motionAuthority == CaptureAuthority.AuthoritativeRaw,
            companionPhonePose = companionPhonePoseRows > 0,
            companionPhoneIntrinsics = companionPhoneIntrinsicsValid,
            companionPhoneCalibration = companionPhoneCalibration,
        )
        val captureEvidence = CaptureEvidence(
            arkitFrameRows = 0,
            arkitPoseRows = 0,
            arkitIntrinsicsValid = false,
            arkitDepthFrames = 0,
            arkitConfidenceFrames = 0,
            arkitMeshFiles = 0,
            poseRows = arcorePoseRows,
            intrinsicsValid = arcoreIntrinsicsValid,
            depthFrames = arcoreDepthFrames,
            confidenceFrames = arcoreConfidenceFrames,
            meshFiles = 0,
            pointCloudSamples = arcorePointCloudSamples,
            planeRows = arcorePlaneRows,
            featurePointRows = 0,
            trackingStateRows = arcoreTrackingStateRows,
            relocalizationEventRows = relocalizationEvents.size,
            lightEstimateRows = arcoreLightEstimateRows,
            geospatialRows = 0,
            motionSamples = motionSamples,
            poseAuthority = poseAuthority,
            intrinsicsAuthority = intrinsicsAuthority,
            depthAuthority = depthAuthority,
            geospatialAuthority = CaptureAuthority.NotAvailable,
            motionAuthority = motionAuthority,
            motionProvenance = motionProvenance,
            motionTimestampsCaptureRelative = motionSamples > 0,
            geometrySource = geometrySource,
            geometryExpectedDownstream = geometryExpectedDownstream,
        )
        val captureCapabilities = CaptureCapabilities(
            cameraPose = sensorAvailability.cameraPose,
            cameraIntrinsics = sensorAvailability.cameraIntrinsics,
            depth = sensorAvailability.depth,
            depthConfidence = sensorAvailability.depthConfidence,
            missingDepthReason = missingDepthReason,
            mesh = sensorAvailability.mesh,
            pointCloud = sensorAvailability.pointCloud,
            planes = sensorAvailability.planes,
            featurePoints = sensorAvailability.featurePoints,
            trackingState = sensorAvailability.trackingState,
            relocalizationEvents = sensorAvailability.relocalizationEvents,
            lightEstimate = sensorAvailability.lightEstimate,
            geospatial = false,
            motion = sensorAvailability.motion,
            motionAuthoritative = sensorAvailability.motionAuthoritative,
            companionPhonePose = sensorAvailability.companionPhonePose,
            companionPhoneIntrinsics = sensorAvailability.companionPhoneIntrinsics,
            companionPhoneCalibration = sensorAvailability.companionPhoneCalibration,
            poseRows = captureEvidence.poseRows,
            intrinsicsValid = captureEvidence.intrinsicsValid,
            depthFrames = captureEvidence.depthFrames,
            confidenceFrames = captureEvidence.confidenceFrames,
            meshFiles = captureEvidence.meshFiles,
            pointCloudSamples = captureEvidence.pointCloudSamples,
            planeRows = captureEvidence.planeRows,
            featurePointRows = captureEvidence.featurePointRows,
            trackingStateRows = captureEvidence.trackingStateRows,
            relocalizationEventRows = captureEvidence.relocalizationEventRows,
            lightEstimateRows = captureEvidence.lightEstimateRows,
            geospatialRows = 0,
            motionSamples = captureEvidence.motionSamples,
            poseAuthority = captureEvidence.poseAuthority,
            intrinsicsAuthority = captureEvidence.intrinsicsAuthority,
            depthAuthority = captureEvidence.depthAuthority,
            geospatialAuthority = CaptureAuthority.NotAvailable,
            motionAuthority = captureEvidence.motionAuthority,
            motionProvenance = motionProvenance,
            geometrySource = geometrySource,
            geometryExpectedDownstream = geometryExpectedDownstream,
        )
        return BundleEvidence(
            captureProfileId = captureProfileId,
            captureModality = captureModality,
            geometrySource = geometrySource,
            geometryExpectedDownstream = geometryExpectedDownstream,
            sensorAvailability = sensorAvailability,
            captureEvidence = captureEvidence,
            captureCapabilities = captureCapabilities,
            motionProvenance = motionProvenance,
            motionAuthority = motionAuthority,
        )
    }

    private fun captureContributorPayoutEligible(request: AndroidCaptureBundleRequest): Boolean {
        if (request.captureSource == AndroidCaptureSource.AndroidXrGlasses) return false
        return (request.quotedPayoutCents ?: 0) > 0
    }

    private fun isIntakeComplete(packet: QualificationIntakePacket?): Boolean {
        if (packet == null) return false
        val hasWorkflow = !packet.workflowName.isNullOrBlank()
        val hasSteps = packet.taskSteps.any { it.isNotBlank() }
        val hasZoneOrOwner = !packet.zone.isNullOrBlank() || !packet.owner.isNullOrBlank()
        return hasWorkflow && hasSteps && hasZoneOrOwner
    }

    private fun synthesizeTaskHypothesis(request: AndroidCaptureBundleRequest): TaskHypothesis {
        val packet = request.intakePacket ?: QualificationIntakePacket()
        val metadata = request.intakeMetadata ?: CaptureIntakeMetadata(source = CaptureIntakeSource.Authoritative)
        return TaskHypothesis(
            workflowName = packet.workflowName ?: request.workflowName,
            taskSteps = packet.taskSteps.ifEmpty { request.taskSteps },
            zone = packet.zone ?: request.zone,
            owner = packet.owner ?: request.owner,
            confidence = metadata.confidence,
            source = metadata.source,
            model = metadata.model,
            fps = metadata.fps,
            warnings = metadata.warnings,
            status = CaptureTaskHypothesisStatus.Accepted,
        )
    }

    private fun copyDirectory(source: File, destination: File) {
        if (!source.exists()) return
        destination.mkdirs()
        source.listFiles().orEmpty().forEach { child ->
            val target = destination.resolve(child.name)
            if (child.isDirectory) {
                copyDirectory(child, target)
            } else {
                child.copyTo(target, overwrite = true)
            }
        }
    }

    private fun materializeMotionFiles(rawDirectory: File, imuSamplesSource: File?): MaterializedMotionFiles {
        val motionFile = rawDirectory.resolve("motion.jsonl")
        val source = imuSamplesSource?.takeIf { it.exists() && it.length() > 0 }
        if (source == null) {
            motionFile.writeText("")
            return MaterializedMotionFiles(motionFile = motionFile, diagnosticImuFile = null)
        }

        if (isCanonicalMotionFile(source)) {
            source.copyTo(motionFile, overwrite = true)
            return MaterializedMotionFiles(motionFile = motionFile, diagnosticImuFile = null)
        }

        val diagnosticFile = rawDirectory.resolve("android_imu_samples.jsonl")
        source.copyTo(diagnosticFile, overwrite = true)
        motionFile.writeText("")
        return MaterializedMotionFiles(motionFile = motionFile, diagnosticImuFile = diagnosticFile)
    }

    private fun isCanonicalMotionFile(file: File): Boolean {
        val lines = file.readLines().filter { it.isNotBlank() }
        if (lines.isEmpty()) return false
        return lines.all { line ->
            val payload = parseJsonObject(line) ?: return@all false
            val required = listOf(
                "timestamp",
                "t_capture_sec",
                "t_monotonic_ns",
                "wall_time",
                "motion_provenance",
                "attitude",
                "rotation_rate",
                "gravity",
                "user_acceleration",
            )
            required.all { hasJsonValue(payload, it) } &&
                hasObjectKeys(payload, "attitude", listOf("roll", "pitch", "yaw", "quaternion")) &&
                hasObjectKeys(payload, "rotation_rate", listOf("x", "y", "z")) &&
                hasObjectKeys(payload, "gravity", listOf("x", "y", "z")) &&
                hasObjectKeys(payload, "user_acceleration", listOf("x", "y", "z")) &&
                runCatching {
                    val quaternion = payload["attitude"]!!.jsonObject["quaternion"]!!.jsonObject
                    listOf("x", "y", "z", "w").all { hasJsonValue(quaternion, it) }
                }.getOrDefault(false)
        }
    }

    private fun hasObjectKeys(payload: JsonObject, key: String, requiredKeys: List<String>): Boolean {
        val nested = runCatching { payload[key]?.jsonObject }.getOrNull() ?: return false
        return requiredKeys.all { hasJsonValue(nested, it) }
    }

    private fun hasJsonValue(payload: JsonObject, key: String): Boolean {
        val value = payload[key] ?: return false
        return value.toString() != "null"
    }

    private fun countJsonlRows(file: File?): Int {
        if (file == null || !file.exists() || file.length() == 0L) return 0
        return file.readLines().count { it.trim().isNotEmpty() }
    }

    private fun materializeSyncMap(
        rawDirectory: File,
        framesFile: File,
        posesFile: File,
        fallbackCoordinateFrameSessionId: String,
    ) {
        val rows = buildSyncMapRows(framesFile, posesFile, fallbackCoordinateFrameSessionId)
        val syncMapFile = rawDirectory.resolve("sync_map.jsonl")
        if (rows.isEmpty()) {
            syncMapFile.writeText("")
            return
        }
        syncMapFile.writeText(rows.joinToString(separator = "\n") { lineJson.encodeToString(it) } + "\n")
    }

    private fun buildSyncMapRows(
        framesFile: File,
        posesFile: File,
        fallbackCoordinateFrameSessionId: String,
    ): List<SyncMapRow> {
        val frameRows = readFrameTimeRows(framesFile)
        if (frameRows.isEmpty()) return emptyList()
        val poseRows = readFrameTimeRows(posesFile)
        val posesByFrameId = poseRows.associateBy { it.frameId }
        val posesByTime = poseRows.sortedBy { it.tCaptureSec }
        return frameRows.map { frameRow ->
            val exactPose = posesByFrameId[frameRow.frameId]
            val matchedPose = exactPose ?: nearestByCaptureTime(frameRow.tCaptureSec, posesByTime)
            val syncStatus = when {
                exactPose != null -> "exact_frame_id_match"
                matchedPose != null -> "nearest_pose_time_match"
                else -> "pose_unavailable_for_frame"
            }
            SyncMapRow(
                frameId = frameRow.frameId,
                tVideoSec = frameRow.tCaptureSec,
                tCaptureSec = frameRow.tCaptureSec,
                poseFrameId = matchedPose?.frameId,
                syncStatus = syncStatus,
                deltaMs = matchedPose?.let { round3(kotlin.math.abs(frameRow.tCaptureSec - it.tCaptureSec) * 1000.0) },
                tMonotonicNs = frameRow.tMonotonicNs,
                coordinateFrameSessionId = frameRow.coordinateFrameSessionId
                    ?: matchedPose?.coordinateFrameSessionId
                    ?: fallbackCoordinateFrameSessionId,
            )
        }
    }

    private fun deriveRelocalizationEvents(trackingStateFile: File): List<RelocalizationEventRecord> {
        val trackingRows = readTrackingRows(trackingStateFile)
        if (trackingRows.isEmpty()) return emptyList()
        val events = mutableListOf<RelocalizationEventRecord>()
        var trackingEstablished = false
        var openLoss: TrackingLossWindow? = null
        trackingRows.forEach { row ->
            if (row.trackingState == "tracking") {
                if (openLoss != null) {
                    events += RelocalizationEventRecord(
                        startFrameId = openLoss?.startFrameId,
                        endFrameId = row.frameId,
                        startTCaptureSec = openLoss?.startTCaptureSec,
                        endTCaptureSec = row.tCaptureSec,
                        frameCount = openLoss?.frameCount ?: 0,
                        recovered = true,
                    )
                    openLoss = null
                }
                trackingEstablished = true
                return@forEach
            }
            if (!trackingEstablished) return@forEach
            openLoss = if (openLoss == null) {
                TrackingLossWindow(
                    startFrameId = row.frameId,
                    startTCaptureSec = row.tCaptureSec,
                    frameCount = 1,
                )
            } else {
                openLoss!!.copy(frameCount = openLoss!!.frameCount + 1)
            }
        }
        openLoss?.let {
            events += RelocalizationEventRecord(
                startFrameId = it.startFrameId,
                startTCaptureSec = it.startTCaptureSec,
                frameCount = it.frameCount,
                recovered = false,
            )
        }
        return events
    }

    private fun recordingWorldFrameFor(bundleEvidence: BundleEvidence): RecordingWorldFrame {
        return when {
            bundleEvidence.captureCapabilities.cameraPose -> RecordingWorldFrame(
                worldFrameDefinition = "arcore_world_origin_at_session_start",
                gravityAligned = true,
            )
            bundleEvidence.captureCapabilities.companionPhonePose -> RecordingWorldFrame(
                worldFrameDefinition = "companion_phone_world_tracking_origin_at_session_start",
                gravityAligned = true,
            )
            else -> RecordingWorldFrame(
                worldFrameDefinition = "unavailable_no_public_world_tracking",
                handedness = "unknown",
                gravityAligned = false,
            )
        }
    }

    private fun readFrameTimeRows(file: File): List<FrameTimeRow> {
        if (!file.exists() || file.length() == 0L) return emptyList()
        return file.readLines().mapNotNull { line ->
            val payload = parseJsonObject(line) ?: return@mapNotNull null
            val frameId = readString(payload, "frame_id")
                ?: readNumber(payload, "frame_index")?.toInt()?.let { String.format("%06d", it + 1) }
                ?: return@mapNotNull null
            val tCaptureSec = readNumber(payload, "t_capture_sec") ?: return@mapNotNull null
            FrameTimeRow(
                frameId = frameId,
                tCaptureSec = tCaptureSec,
                tMonotonicNs = readNumber(payload, "t_monotonic_ns")?.toLong(),
                coordinateFrameSessionId = readString(payload, "coordinate_frame_session_id"),
            )
        }
    }

    private fun readTrackingRows(file: File): List<TrackingStateRow> {
        if (!file.exists() || file.length() == 0L) return emptyList()
        return file.readLines().mapNotNull { line ->
            val payload = parseJsonObject(line) ?: return@mapNotNull null
            val frameId = readString(payload, "frame_id") ?: return@mapNotNull null
            val tCaptureSec = readNumber(payload, "t_capture_sec") ?: return@mapNotNull null
            val trackingState = readString(payload, "tracking_state") ?: return@mapNotNull null
            TrackingStateRow(frameId = frameId, tCaptureSec = tCaptureSec, trackingState = trackingState)
        }
    }

    private fun nearestByCaptureTime(timeSec: Double, rows: List<FrameTimeRow>): FrameTimeRow? {
        if (rows.isEmpty()) return null
        var low = 0
        var high = rows.lastIndex
        while (low < high) {
            val mid = (low + high) / 2
            if (rows[mid].tCaptureSec < timeSec) {
                low = mid + 1
            } else {
                high = mid
            }
        }
        val candidate = rows[low]
        val previous = rows.getOrNull(low - 1)
        return if (previous != null && kotlin.math.abs(previous.tCaptureSec - timeSec) <= kotlin.math.abs(candidate.tCaptureSec - timeSec)) {
            previous
        } else {
            candidate
        }
    }

    private fun parseJsonObject(line: String): JsonObject? {
        if (line.isBlank()) return null
        return runCatching { json.parseToJsonElement(line).jsonObject }.getOrNull()
    }

    private fun readString(payload: JsonObject, key: String): String? {
        return (payload[key] as? JsonPrimitive)
            ?.content
            ?.takeIf { it.isNotBlank() && it != "null" }
    }

    private fun readNumber(payload: JsonObject, key: String): Double? {
        return (payload[key] as? JsonPrimitive)?.content?.toDoubleOrNull()
    }

    private fun countFiles(directory: File): Int {
        if (!directory.exists()) return 0
        return directory.walkTopDown().count { it.isFile }
    }

    private fun countManifestFrames(file: File): Int {
        if (!file.exists()) return 0
        val content = runCatching { json.parseToJsonElement(file.readText()) }.getOrNull() ?: return 0
        val payload = content.jsonObject
        val frames = payload["frames"] ?: payload["artifacts"] ?: return 0
        return runCatching { frames.jsonArray.size }.getOrDefault(0)
    }

    private fun isValidIntrinsicsFile(file: File): Boolean {
        if (!file.exists()) return false
        val content = runCatching { json.parseToJsonElement(file.readText()) }.getOrNull() ?: return false
        val jsonObject = content.jsonObject
        val candidate = runCatching { jsonObject["intrinsics"]?.jsonObject }.getOrNull() ?: jsonObject
        return listOf("fx", "fy", "cx", "cy").all { key ->
            candidate[key]?.toString()?.toDoubleOrNull()?.isFinite() == true
        } && listOf("width", "height").all { key ->
            (candidate[key]?.toString()?.toIntOrNull() ?: 0) > 0
        }
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

    private fun round3(value: Double): Double = String.format(Locale.US, "%.3f", value).toDouble()

    private data class FrameTimeRow(
        val frameId: String,
        val tCaptureSec: Double,
        val tMonotonicNs: Long?,
        val coordinateFrameSessionId: String?,
    )

    private data class TrackingStateRow(
        val frameId: String,
        val tCaptureSec: Double,
        val trackingState: String,
    )

    private data class TrackingLossWindow(
        val startFrameId: String,
        val startTCaptureSec: Double,
        val frameCount: Int,
    )

    private data class RecordingWorldFrame(
        val worldFrameDefinition: String,
        val units: String = "meters",
        val handedness: String = "right_handed",
        val gravityAligned: Boolean,
        val sessionResetCount: Int = 0,
    )
}
