package app.blueprint.capture.data.capture

import com.google.common.truth.Truth.assertThat
import java.io.File
import java.security.MessageDigest
import kotlin.io.path.createTempDirectory
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Test

class AndroidCaptureBundleBuilderTest {
    private val json = Json { ignoreUnknownKeys = true }

    @Test
    fun `bundle builder writes canonical android manifest and supplemental files`() {
        val tempDir = createTempDirectory("android-capture-bundle").toFile()
        val sourceVideo = File(tempDir, "walkthrough.mp4").apply {
            writeBytes(byteArrayOf(0x01, 0x02, 0x03))
        }
        val request = AndroidCaptureBundleRequest(
            sceneId = "scene-123",
            captureId = "capture-123",
            creatorId = "tester",
            deviceModel = "Pixel 9 Pro",
            osVersion = "Android 16",
            fpsSource = 30.0,
            width = 1920,
            height = 1080,
            captureStartEpochMs = 1_700_000_000_000,
            siteSubmissionId = "site-sub-123",
            buyerRequestId = "buyer-req-123",
            captureJobId = "capture-job-123",
            workflowName = "Inbound walk",
            taskSteps = listOf("Enter", "Sweep"),
            zone = "Aisle 4",
            inaccessibleAreas = listOf("Locked mezzanine"),
            intakePacket = QualificationIntakePacket(
                workflowName = "Inbound walk",
                taskSteps = listOf("Enter", "Sweep"),
                targetKPI = "door cycle time",
                zone = "Aisle 4",
            ),
        )

        val result = AndroidCaptureBundleBuilder().writeBundle(
            outputRoot = tempDir,
            request = request,
            walkthroughSource = sourceVideo,
        )

        assertThat(result.manifestFile.exists()).isTrue()
        assertThat(result.contextFile.exists()).isTrue()
        assertThat(result.hypothesisFile.exists()).isTrue()
        assertThat(result.completionFile.exists()).isTrue()
        assertThat(result.provenanceFile.exists()).isTrue()
        assertThat(result.rightsConsentFile.exists()).isTrue()
        assertThat(result.videoTrackFile.exists()).isTrue()
        assertThat(result.hashesFile.exists()).isTrue()
        assertThat(File(result.rawDirectory, "walkthrough.mp4").exists()).isTrue()

        val manifest = json.decodeFromString<CaptureManifest>(result.manifestFile.readText())
        val manifestJson = json.parseToJsonElement(result.manifestFile.readText()).jsonObject
        assertThat(manifest.schemaVersion).isEqualTo("v3")
        assertThat(manifest.captureId).isEqualTo("capture-123")
        assertThat(manifest.coordinateFrameSessionId).isEqualTo("capture-123")
        assertThat(manifest.captureSource).isEqualTo("android")
        assertThat(manifest.captureTierHint).isEqualTo("tier2_android")
        assertThat(manifest.captureModality).isEqualTo("android_video_only")
        assertThat(manifest.captureProfileId).isEqualTo("android_camera_only")
        assertThat(manifest.sceneMemoryCapture.sensorAvailability.arkitPoses).isFalse()
        assertThat(manifest.sceneMemoryCapture.sensorAvailability.motion).isFalse()
        assertThat(manifest.sceneMemoryCapture.inaccessibleAreas).containsExactly("Locked mezzanine")
        assertThat(manifest.captureCapabilities.depth).isFalse()
        assertThat(manifestJson["target_kpi"]?.jsonPrimitive?.contentOrNull).isEqualTo("door cycle time")
        assertThat(manifestJson["capture_capabilities"]?.jsonObject?.get("missing_depth_reason")?.jsonPrimitive?.contentOrNull)
            .isEqualTo("not_supported")
        val upstreamHandoff = manifestJson["upstream_handoff"]?.jsonObject
        assertThat(upstreamHandoff?.get("hosted_review_truth_state")?.jsonPrimitive?.contentOrNull)
            .isEqualTo("upstream_ids_present")
        assertThat(upstreamHandoff?.get("blockers")?.jsonArray).isEmpty()
        assertThat(manifest.captureEvidence.motionAuthority).isEqualTo(CaptureAuthority.NotAvailable)

        val context = json.decodeFromString<CaptureContext>(result.contextFile.readText())
        val contextJson = json.parseToJsonElement(result.contextFile.readText()).jsonObject
        assertThat(context.siteSubmissionId).isEqualTo("site-sub-123")
        assertThat(context.buyerRequestId).isEqualTo("buyer-req-123")
        assertThat(context.captureJobId).isEqualTo("capture-job-123")
        assertThat(context.taskTextHint).isEqualTo("Inbound walk")
        assertThat(context.zone).isEqualTo("Aisle 4")
        assertThat(context.targetKPI).isEqualTo("door cycle time")
        assertThat(context.captureProfileId).isEqualTo("android_camera_only")
        assertThat(context.captureCapabilities.missingDepthReason).isEqualTo("not_supported")
        assertThat(context.sceneMemory.inaccessibleAreas).containsExactly("Locked mezzanine")
        assertThat(contextJson["upstream_handoff"]?.jsonObject?.get("hosted_review_truth_state")?.jsonPrimitive?.contentOrNull)
            .isEqualTo("upstream_ids_present")

        val hypothesis = json.decodeFromString<TaskHypothesis>(result.hypothesisFile.readText())
        assertThat(hypothesis.source).isEqualTo(CaptureIntakeSource.Authoritative)
        assertThat(hypothesis.taskSteps).containsExactly("Enter", "Sweep").inOrder()

        val rightsConsent = json.decodeFromString<RightsConsentFile>(result.rightsConsentFile.readText())
        assertThat(rightsConsent.redactionRequired).isTrue()

        val hashes = json.decodeFromString<HashesFile>(result.hashesFile.readText())
        assertThat(hashes.artifacts).containsKey("manifest.json")
        assertThat(File(result.rawDirectory, "recording_session.json").exists()).isTrue()
        assertThat(File(result.rawDirectory, "motion.jsonl").exists()).isTrue()

        val recordingSession = json.decodeFromString<RecordingSessionFile>(
            File(result.rawDirectory, "recording_session.json").readText(),
        )
        assertThat(recordingSession.sceneId).isEqualTo("scene-123")
        assertThat(recordingSession.captureId).isEqualTo("capture-123")
        assertThat(recordingSession.worldFrameDefinition).isEqualTo("unavailable_no_public_world_tracking")
        assertThat(recordingSession.units).isEqualTo("meters")
        assertThat(recordingSession.gravityAligned).isFalse()
    }

    @Test
    fun `bundle builder preserves missing upstream ids as hosted review blockers`() {
        val tempDir = createTempDirectory("android-capture-missing-upstream").toFile()
        val sourceVideo = File(tempDir, "walkthrough.mp4").apply {
            writeBytes(byteArrayOf(0x01, 0x02, 0x03))
        }
        val request = AndroidCaptureBundleRequest(
            sceneId = "scene-open",
            captureId = "capture-open",
            creatorId = "tester",
            jobId = "local-job-only",
            deviceModel = "Pixel 9 Pro",
            osVersion = "Android 16",
            fpsSource = 30.0,
            width = 1920,
            height = 1080,
            captureStartEpochMs = 1_700_000_000_000,
        )

        val result = AndroidCaptureBundleBuilder().writeBundle(
            outputRoot = tempDir,
            request = request,
            walkthroughSource = sourceVideo,
        )

        val manifest = json.decodeFromString<CaptureManifest>(result.manifestFile.readText())
        assertThat(manifest.siteSubmissionId).isNull()
        assertThat(manifest.buyerRequestId).isNull()
        assertThat(manifest.captureJobId).isNull()
        assertThat(manifest.upstreamHandoff.hostedReviewTruthState).isEqualTo("blocked_missing_upstream_ids")
        assertThat(manifest.upstreamHandoff.blockers).containsExactly(
            "missing_site_submission_id",
            "missing_buyer_request_id",
            "missing_capture_job_id",
        ).inOrder()

        val context = json.decodeFromString<CaptureContext>(result.contextFile.readText())
        assertThat(context.siteSubmissionId).isNull()
        assertThat(context.upstreamHandoff.hostedReviewTruthState).isEqualTo("blocked_missing_upstream_ids")
    }

    @Test
    fun `bundle builder hashes final provenance bytes`() {
        val tempDir = createTempDirectory("android-capture-hashes").toFile()
        val sourceVideo = File(tempDir, "walkthrough.mp4").apply {
            writeBytes(byteArrayOf(0x01, 0x02, 0x03))
        }
        val request = AndroidCaptureBundleRequest(
            sceneId = "scene-123",
            captureId = "capture-123",
            creatorId = "tester",
            deviceModel = "Pixel 9 Pro",
            osVersion = "Android 16",
            fpsSource = 30.0,
            width = 1920,
            height = 1080,
            captureStartEpochMs = 1_700_000_000_000,
        )

        val result = AndroidCaptureBundleBuilder().writeBundle(
            outputRoot = tempDir,
            request = request,
            walkthroughSource = sourceVideo,
        )

        val hashes = json.decodeFromString<HashesFile>(result.hashesFile.readText())
        assertThat(hashes.artifacts["provenance.json"]).isEqualTo(sha256Hex(result.provenanceFile))
    }

    @Test
    fun `bundle builder preserves noncontract imu samples without claiming v3 motion`() {
        val tempDir = createTempDirectory("android-capture-legacy-imu").toFile()
        val sourceVideo = File(tempDir, "walkthrough.mp4").apply {
            writeBytes(byteArrayOf(0x01, 0x02, 0x03))
        }
        val imuFile = File(tempDir, "imu_samples.jsonl").apply {
            writeText("""{"t_ms":16,"ax":0.1,"ay":0.2,"az":9.8,"gx":0.01,"gy":0.02,"gz":0.03}
""")
        }
        val request = AndroidCaptureBundleRequest(
            sceneId = "scene-123",
            captureId = "capture-123",
            creatorId = "tester",
            deviceModel = "Pixel 9 Pro",
            osVersion = "Android 16",
            fpsSource = 30.0,
            width = 1920,
            height = 1080,
            captureStartEpochMs = 1_700_000_000_000,
        )

        val result = AndroidCaptureBundleBuilder().writeBundle(
            outputRoot = tempDir,
            request = request,
            walkthroughSource = sourceVideo,
            imuSamplesSource = imuFile,
        )

        val manifest = json.decodeFromString<CaptureManifest>(result.manifestFile.readText())
        assertThat(manifest.sceneMemoryCapture.motionProvenance).isNull()
        assertThat(manifest.captureCapabilities.motion).isFalse()
        assertThat(manifest.captureEvidence.motionSamples).isEqualTo(0)
        assertThat(manifest.captureEvidence.motionAuthority).isEqualTo(CaptureAuthority.NotAvailable)
        assertThat(File(result.rawDirectory, "motion.jsonl").readText()).isEmpty()
        assertThat(File(result.rawDirectory, "android_imu_samples.jsonl").readText()).isEqualTo(imuFile.readText())
        val hashes = json.decodeFromString<HashesFile>(result.hashesFile.readText())
        assertThat(hashes.artifacts).containsKey("android_imu_samples.jsonl")
    }

    @Test
    fun `bundle builder materializes arcore depth evidence when sidecars are present`() {
        val tempDir = createTempDirectory("android-capture-arcore").toFile()
        val sourceVideo = File(tempDir, "walkthrough.mp4").apply { writeBytes(byteArrayOf(0x01, 0x02, 0x03)) }
        val arcoreSource = File(tempDir, "arcore-source").apply { mkdirs() }
        File(arcoreSource, "depth").mkdirs()
        File(arcoreSource, "confidence").mkdirs()
        File(arcoreSource, "poses.jsonl").writeText("""{"frame_id":"000001","t_capture_sec":0.0,"T_world_camera":[[1,0,0,0],[0,1,0,0],[0,0,1,0],[0,0,0,1]]}
""")
        File(arcoreSource, "frames.jsonl").writeText("""{"frame_id":"000001","t_capture_sec":0.0}
""")
        File(arcoreSource, "tracking_state.jsonl").writeText("""{"frame_id":"000001","t_capture_sec":0.0}
""")
        File(arcoreSource, "point_cloud.jsonl").writeText("""{"frame_id":"000001","t_capture_sec":0.0}
""")
        File(arcoreSource, "planes.jsonl").writeText("""{"frame_id":"000001","t_capture_sec":0.0}
""")
        File(arcoreSource, "light_estimates.jsonl").writeText("""{"frame_id":"000001","t_capture_sec":0.0}
""")
        File(arcoreSource, "session_intrinsics.json").writeText("""{"fx":1,"fy":1,"cx":1,"cy":1,"width":1,"height":1}""")
        File(arcoreSource, "depth_manifest.json").writeText("""{"schema_version":"v1","frames":[{"frame_id":"000001","depth_path":"arcore/depth/000001.png","paired_confidence_path":"arcore/confidence/000001.png"}]}""")
        File(arcoreSource, "confidence_manifest.json").writeText("""{"schema_version":"v1","frames":[{"frame_id":"000001","confidence_path":"arcore/confidence/000001.png","paired_depth_path":"arcore/depth/000001.png"}]}""")
        File(arcoreSource, "depth/000001.png").writeBytes(byteArrayOf(0x01))
        File(arcoreSource, "confidence/000001.png").writeBytes(byteArrayOf(0x01))
        val imuFile = File(tempDir, "motion.jsonl").apply {
            writeText(canonicalMotionLine("phone_imu_accelerometer_gyroscope"))
        }
        val request = AndroidCaptureBundleRequest(
            sceneId = "scene-123",
            captureId = "capture-123",
            creatorId = "tester",
            deviceModel = "Pixel 9 Pro",
            osVersion = "Android 16",
            fpsSource = 30.0,
            width = 1920,
            height = 1080,
            captureStartEpochMs = 1_700_000_000_000,
        )

        val result = AndroidCaptureBundleBuilder().writeBundle(
            outputRoot = tempDir,
            request = request,
            walkthroughSource = sourceVideo,
            imuSamplesSource = imuFile,
            arcoreEvidenceDirectory = arcoreSource,
        )

        val manifest = json.decodeFromString<CaptureManifest>(result.manifestFile.readText())
        assertThat(manifest.captureProfileId).isEqualTo("android_arcore_depth")
        assertThat(manifest.captureModality).isEqualTo("android_arcore_depth")
        assertThat(manifest.captureCapabilities.cameraPose).isTrue()
        assertThat(manifest.captureCapabilities.depth).isTrue()
        assertThat(manifest.captureCapabilities.pointCloud).isTrue()
        assertThat(manifest.captureEvidence.poseAuthority).isEqualTo(CaptureAuthority.RawTrackingOnly)
        assertThat(manifest.captureEvidence.motionAuthority).isEqualTo(CaptureAuthority.AuthoritativeRaw)
        assertThat(File(result.rawDirectory, "arcore/poses.jsonl").exists()).isTrue()
        assertThat(manifest.captureCapabilities.relocalizationEvents).isFalse()
        assertThat(File(result.rawDirectory, "sync_map.jsonl").readLines()).hasSize(1)
        val syncRow = File(result.rawDirectory, "sync_map.jsonl").readLines().single()
        assertThat(syncRow).contains("exact_frame_id_match")
        assertThat(syncRow).contains("\"pose_frame_id\":\"000001\"")
        val recordingSession = json.decodeFromString<RecordingSessionFile>(
            File(result.rawDirectory, "recording_session.json").readText(),
        )
        assertThat(recordingSession.worldFrameDefinition).isEqualTo("arcore_world_origin_at_session_start")
        assertThat(recordingSession.gravityAligned).isTrue()
    }

    @Test
    fun `bundle builder marks glasses phone imu as diagnostic and companion phone scaffold explicitly`() {
        val tempDir = createTempDirectory("android-capture-glasses").toFile()
        val sourceVideo = File(tempDir, "walkthrough.mp4").apply { writeBytes(byteArrayOf(0x01, 0x02, 0x03)) }
        val glassesSource = File(tempDir, "glasses-source").apply { mkdirs() }
        File(glassesSource, "stream_metadata.json").writeText("""{"schema_version":"v1"}""")
        File(glassesSource, "frame_timestamps.jsonl").writeText("""{"frame_index":1,"t_capture_sec":0.0}
""")
        File(glassesSource, "device_state.jsonl").writeText("""{"event":"unavailable_in_public_sdk"}
""")
        File(glassesSource, "health_events.jsonl").writeText("""{"event":"unavailable_in_public_sdk"}
""")
        val companionSource = File(tempDir, "companion-phone").apply { mkdirs() }
        File(companionSource, "poses.jsonl").writeText("""{"frame_id":"000001","t_capture_sec":0.0,"T_world_camera":[[1,0,0,0],[0,1,0,0],[0,0,1,0],[0,0,0,1]]}
""")
        File(companionSource, "session_intrinsics.json").writeText("""{"fx":1,"fy":1,"cx":1,"cy":1,"width":1,"height":1}""")
        File(companionSource, "calibration.json").writeText("""{"calibrated_to_glasses_optical_center":false}""")
        val imuFile = File(tempDir, "motion.jsonl").apply {
            writeText(canonicalMotionLine("phone_imu_diagnostic_only"))
        }
        val request = AndroidCaptureBundleRequest(
            sceneId = "scene-123",
            captureId = "capture-123",
            creatorId = "tester",
            deviceModel = "Meta companion phone",
            osVersion = "Android 16",
            fpsSource = 30.0,
            width = 1280,
            height = 720,
            captureStartEpochMs = 1_700_000_000_000,
            captureSource = AndroidCaptureSource.MetaGlasses,
        )

        val result = AndroidCaptureBundleBuilder().writeBundle(
            outputRoot = tempDir,
            request = request,
            walkthroughSource = sourceVideo,
            imuSamplesSource = imuFile,
            glassesEvidenceDirectory = glassesSource,
            companionPhoneDirectory = companionSource,
        )

        val manifest = json.decodeFromString<CaptureManifest>(result.manifestFile.readText())
        assertThat(manifest.captureProfileId).isEqualTo("glasses_pov_companion_phone")
        assertThat(manifest.sceneMemoryCapture.motionProvenance).isEqualTo("phone_imu_diagnostic_only")
        assertThat(manifest.captureCapabilities.motionAuthoritative).isFalse()
        assertThat(manifest.captureCapabilities.companionPhonePose).isTrue()
        assertThat(manifest.captureCapabilities.companionPhoneCalibration).isTrue()
        assertThat(manifest.captureEvidence.motionAuthority).isEqualTo(CaptureAuthority.DiagnosticOnly)
        assertThat(File(result.rawDirectory, "glasses/stream_metadata.json").exists()).isTrue()
        assertThat(File(result.rawDirectory, "companion_phone/calibration.json").exists()).isTrue()
        val recordingSession = json.decodeFromString<RecordingSessionFile>(
            File(result.rawDirectory, "recording_session.json").readText(),
        )
        assertThat(recordingSession.worldFrameDefinition)
            .isEqualTo("companion_phone_world_tracking_origin_at_session_start")
        assertThat(recordingSession.gravityAligned).isTrue()
    }

    @Test
    fun `bundle builder keeps android xr output contract glasses-compatible while preserving xr profile`() {
        val tempDir = createTempDirectory("android-capture-xr").toFile()
        val sourceVideo = File(tempDir, "walkthrough.mp4").apply { writeBytes(byteArrayOf(0x01, 0x02, 0x03)) }
        val request = AndroidCaptureBundleRequest(
            sceneId = "scene-123",
            captureId = "capture-123",
            creatorId = "tester",
            deviceModel = "Android XR projected glasses",
            osVersion = "Android 16",
            fpsSource = 15.0,
            width = 1280,
            height = 720,
            captureStartEpochMs = 1_700_000_000_000,
            captureSource = AndroidCaptureSource.AndroidXrGlasses,
        )

        val result = AndroidCaptureBundleBuilder().writeBundle(
            outputRoot = tempDir,
            request = request,
            walkthroughSource = sourceVideo,
        )

        val manifest = json.decodeFromString<CaptureManifest>(result.manifestFile.readText())
        assertThat(manifest.captureSource).isEqualTo("glasses")
        assertThat(manifest.captureTierHint).isEqualTo("tier2_glasses")
        assertThat(manifest.captureProfileId).isEqualTo("android_xr_glasses")
        assertThat(manifest.captureModality).isEqualTo("android_xr_video_only")
        assertThat(manifest.sceneMemoryCapture.motionProvenance).isNull()
        assertThat(manifest.sceneMemoryCapture.geometrySource).isNull()
        assertThat(manifest.sceneMemoryCapture.geometryExpectedDownstream).isFalse()
        assertThat(manifest.captureCapabilities.cameraPose).isFalse()
        assertThat(manifest.captureCapabilities.motion).isFalse()
        assertThat(manifest.captureEvidence.poseAuthority).isEqualTo(CaptureAuthority.NotAvailable)
        assertThat(manifest.captureEvidence.motionAuthority).isEqualTo(CaptureAuthority.NotAvailable)

        val recordingSession = json.decodeFromString<RecordingSessionFile>(
            File(result.rawDirectory, "recording_session.json").readText(),
        )
        assertThat(recordingSession.worldFrameDefinition).isEqualTo("unavailable_no_public_world_tracking")
        assertThat(recordingSession.gravityAligned).isFalse()
    }

    @Test
    fun `bundle builder keeps android xr glasses from claiming arcore geospatial or payout proof`() {
        val tempDir = createTempDirectory("android-capture-xr-fail-closed").toFile()
        val sourceVideo = File(tempDir, "walkthrough.mp4").apply { writeBytes(byteArrayOf(0x01, 0x02, 0x03)) }
        val arcoreSource = File(tempDir, "accidental-arcore-source").apply { mkdirs() }
        File(arcoreSource, "depth").mkdirs()
        File(arcoreSource, "confidence").mkdirs()
        File(arcoreSource, "poses.jsonl").writeText("""{"frame_id":"000001","t_capture_sec":0.0,"T_world_camera":[[1,0,0,0],[0,1,0,0],[0,0,1,0],[0,0,0,1]]}
""")
        File(arcoreSource, "frames.jsonl").writeText("""{"frame_id":"000001","t_capture_sec":0.0}
""")
        File(arcoreSource, "tracking_state.jsonl").writeText("""{"frame_id":"000001","t_capture_sec":0.0}
""")
        File(arcoreSource, "session_intrinsics.json").writeText("""{"fx":1,"fy":1,"cx":1,"cy":1,"width":1,"height":1}""")
        File(arcoreSource, "depth_manifest.json").writeText("""{"schema_version":"v1","frames":[{"frame_id":"000001","depth_path":"arcore/depth/000001.png"}]}""")
        File(arcoreSource, "depth/000001.png").writeBytes(byteArrayOf(0x01))
        val imuFile = File(tempDir, "motion.jsonl").apply {
            writeText(canonicalMotionLine("phone_imu_accelerometer_gyroscope"))
        }
        val request = AndroidCaptureBundleRequest(
            sceneId = "scene-123",
            captureId = "capture-123",
            creatorId = "tester",
            deviceModel = "Google Android XR glasses",
            osVersion = "Android 16",
            fpsSource = 15.0,
            width = 1280,
            height = 720,
            captureStartEpochMs = 1_700_000_000_000,
            captureSource = AndroidCaptureSource.AndroidXrGlasses,
            quotedPayoutCents = 750,
        )

        val result = AndroidCaptureBundleBuilder().writeBundle(
            outputRoot = tempDir,
            request = request,
            walkthroughSource = sourceVideo,
            imuSamplesSource = imuFile,
            arcoreEvidenceDirectory = arcoreSource,
        )

        val manifest = json.decodeFromString<CaptureManifest>(result.manifestFile.readText())
        assertThat(manifest.captureProfileId).isEqualTo("android_xr_glasses")
        assertThat(manifest.captureCapabilities.cameraPose).isFalse()
        assertThat(manifest.captureCapabilities.cameraIntrinsics).isFalse()
        assertThat(manifest.captureCapabilities.depth).isFalse()
        assertThat(manifest.captureCapabilities.depthConfidence).isFalse()
        assertThat(manifest.captureCapabilities.geospatial).isFalse()
        assertThat(manifest.captureCapabilities.poseRows).isEqualTo(0)
        assertThat(manifest.captureCapabilities.depthFrames).isEqualTo(0)
        assertThat(manifest.captureCapabilities.geospatialRows).isEqualTo(0)
        assertThat(manifest.captureEvidence.poseAuthority).isEqualTo(CaptureAuthority.NotAvailable)
        assertThat(manifest.captureEvidence.depthAuthority).isEqualTo(CaptureAuthority.NotAvailable)
        assertThat(manifest.captureEvidence.geospatialAuthority).isEqualTo(CaptureAuthority.NotAvailable)
        assertThat(manifest.captureEvidence.motionAuthority).isEqualTo(CaptureAuthority.DiagnosticOnly)
        assertThat(manifest.captureCapabilities.motionAuthoritative).isFalse()
        assertThat(manifest.sceneMemoryCapture.motionProvenance).isEqualTo("phone_imu_diagnostic_only")
        assertThat(manifest.captureRights.payoutEligible).isFalse()
        assertThat(File(result.rawDirectory, "arcore/poses.jsonl").exists()).isFalse()

        val rightsConsent = json.decodeFromString<RightsConsentFile>(result.rightsConsentFile.readText())
        assertThat(rightsConsent.captureContributorPayoutEligible).isFalse()
    }

    private fun sha256Hex(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(file.readBytes())
        return digest.joinToString(separator = "") { byte -> "%02x".format(byte.toInt() and 0xff) }
    }

    private fun canonicalMotionLine(provenance: String): String = """
{"timestamp":1.0,"t_capture_sec":0.0,"t_monotonic_ns":1000000,"wall_time":"2026-03-20T14:00:29.857Z","motion_provenance":"$provenance","attitude":{"roll":0.0,"pitch":0.0,"yaw":0.0,"quaternion":{"x":0.0,"y":0.0,"z":0.0,"w":1.0}},"rotation_rate":{"x":0.0,"y":0.0,"z":0.0},"gravity":{"x":0.0,"y":0.0,"z":-1.0},"user_acceleration":{"x":0.0,"y":0.0,"z":0.0}}
""".trimStart()
}
