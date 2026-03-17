package app.blueprint.capture.data.capture

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class AndroidCaptureBundleRequest(
    @SerialName("scene_id") val sceneId: String,
    @SerialName("capture_id") val captureId: String,
    @SerialName("creator_id") val creatorId: String,
    @SerialName("job_id") val jobId: String? = null,
    @SerialName("site_submission_id") val siteSubmissionId: String? = null,
    @SerialName("device_model") val deviceModel: String,
    @SerialName("os_version") val osVersion: String,
    @SerialName("fps_source") val fpsSource: Double,
    val width: Int,
    val height: Int,
    @SerialName("capture_start_epoch_ms") val captureStartEpochMs: Long,
    @SerialName("capture_duration_ms") val captureDurationMs: Long? = null,
    @SerialName("has_lidar") val hasLiDAR: Boolean = false,
    @SerialName("capture_context_hint") val captureContextHint: String? = null,
    @SerialName("workflow_name") val workflowName: String? = null,
    @SerialName("task_steps") val taskSteps: List<String> = emptyList(),
    val zone: String? = null,
    val owner: String? = null,
    @SerialName("operator_notes") val operatorNotes: List<String> = emptyList(),
    @SerialName("intake_packet") val intakePacket: QualificationIntakePacket? = null,
    @SerialName("intake_metadata") val intakeMetadata: CaptureIntakeMetadata? = null,
    @SerialName("quoted_payout_cents") val quotedPayoutCents: Int? = null,
    @SerialName("rights_profile") val rightsProfile: String? = null,
    @SerialName("requested_outputs") val requestedOutputs: List<String> = listOf("qualification", "review_intake"),
)

@Serializable
data class QualificationIntakePacket(
    @SerialName("schema_version") val schemaVersion: String = "v1",
    @SerialName("workflow_name") val workflowName: String? = null,
    @SerialName("task_steps") val taskSteps: List<String> = emptyList(),
    val zone: String? = null,
    val owner: String? = null,
)

val QualificationIntakePacket.isComplete: Boolean
    get() {
        val hasWorkflow = !workflowName.isNullOrBlank()
        val hasSteps = taskSteps.any { it.isNotBlank() }
        val hasZoneOrOwner = !zone.isNullOrBlank() || !owner.isNullOrBlank()
        return hasWorkflow && hasSteps && hasZoneOrOwner
    }

@Serializable
data class CaptureIntakeMetadata(
    val source: String = "human_manual",
    val confidence: Double? = null,
    val warnings: List<String> = emptyList(),
)

@Serializable
data class CaptureManifest(
    @SerialName("scene_id") val sceneId: String,
    @SerialName("video_uri") val videoUri: String,
    @SerialName("device_model") val deviceModel: String,
    @SerialName("os_version") val osVersion: String,
    @SerialName("fps_source") val fpsSource: Double,
    val width: Int,
    val height: Int,
    @SerialName("capture_start_epoch_ms") val captureStartEpochMs: Long,
    @SerialName("has_lidar") val hasLiDAR: Boolean,
    @SerialName("capture_schema_version") val captureSchemaVersion: String = "2.0.0",
    @SerialName("capture_source") val captureSource: String = "android_phone",
    @SerialName("capture_tier_hint") val captureTierHint: String = "tier2_android_phone",
    @SerialName("capture_modality") val captureModality: String = "android_video_only",
    @SerialName("evidence_tier") val evidenceTier: String = "pre_screen_video",
    @SerialName("requested_outputs") val requestedOutputs: List<String>,
    @SerialName("task_text_hint") val taskTextHint: String? = null,
    @SerialName("task_steps") val taskSteps: List<String>,
    val zone: String? = null,
    val owner: String? = null,
    @SerialName("scene_memory_capture") val sceneMemoryCapture: SceneMemoryCapture,
    @SerialName("capture_rights") val captureRights: CaptureRights,
    @SerialName("capture_evidence") val captureEvidence: CaptureEvidence,
)

@Serializable
data class SceneMemoryCapture(
    @SerialName("continuity_score") val continuityScore: Double? = null,
    @SerialName("lighting_consistency") val lightingConsistency: String = "unknown",
    @SerialName("dynamic_object_density") val dynamicObjectDensity: String = "unknown",
    @SerialName("sensor_availability") val sensorAvailability: SensorAvailability = SensorAvailability(),
    @SerialName("operator_notes") val operatorNotes: List<String> = emptyList(),
    @SerialName("inaccessible_areas") val inaccessibleAreas: List<String> = emptyList(),
    @SerialName("world_model_candidate") val worldModelCandidate: Boolean = false,
    @SerialName("motion_provenance") val motionProvenance: String? = "phone_imu_diagnostic_only",
    @SerialName("motion_timestamps_capture_relative") val motionTimestampsCaptureRelative: Boolean = true,
)

@Serializable
data class SensorAvailability(
    @SerialName("arkit_poses") val arkitPoses: Boolean = false,
    @SerialName("arkit_intrinsics") val arkitIntrinsics: Boolean = false,
    @SerialName("arkit_depth") val arkitDepth: Boolean = false,
    @SerialName("arkit_confidence") val arkitConfidence: Boolean = false,
    @SerialName("arkit_meshes") val arkitMeshes: Boolean = false,
    val motion: Boolean = true,
)

@Serializable
data class CaptureRights(
    @SerialName("derived_scene_generation_allowed") val derivedSceneGenerationAllowed: Boolean = false,
    @SerialName("data_licensing_allowed") val dataLicensingAllowed: Boolean = false,
    @SerialName("capture_contributor_payout_eligible") val payoutEligible: Boolean = false,
    @SerialName("consent_status") val consentStatus: String = "unknown",
    @SerialName("permission_document_uri") val permissionDocumentUri: String? = null,
    @SerialName("consent_scope") val consentScope: List<String> = emptyList(),
    @SerialName("consent_notes") val consentNotes: List<String> = emptyList(),
)

@Serializable
data class CaptureEvidence(
    @SerialName("arkit_frame_rows") val arkitFrameRows: Int = 0,
    @SerialName("arkit_pose_rows") val arkitPoseRows: Int = 0,
    @SerialName("arkit_intrinsics_valid") val arkitIntrinsicsValid: Boolean = false,
    @SerialName("arkit_depth_frames") val arkitDepthFrames: Int = 0,
    @SerialName("arkit_confidence_frames") val arkitConfidenceFrames: Int = 0,
    @SerialName("arkit_mesh_files") val arkitMeshFiles: Int = 0,
    @SerialName("motion_samples") val motionSamples: Int = 0,
    @SerialName("motion_provenance") val motionProvenance: String? = "phone_imu_diagnostic_only",
    @SerialName("motion_timestamps_capture_relative") val motionTimestampsCaptureRelative: Boolean = true,
)

@Serializable
data class CaptureContext(
    @SerialName("site_submission_id") val siteSubmissionId: String? = null,
    @SerialName("task_text_hint") val taskTextHint: String? = null,
    @SerialName("task_steps") val taskSteps: List<String>,
    val zone: String? = null,
    val owner: String? = null,
    @SerialName("operator_notes") val operatorNotes: List<String> = emptyList(),
    @SerialName("world_model_candidate") val worldModelCandidate: Boolean = false,
    @SerialName("capture_evidence") val captureEvidence: CaptureEvidence = CaptureEvidence(),
    @SerialName("capture_rights") val captureRights: CaptureRights = CaptureRights(),
)

@Serializable
data class TaskHypothesis(
    @SerialName("schema_version") val schemaVersion: String = "v1",
    @SerialName("workflow_name") val workflowName: String? = null,
    @SerialName("task_steps") val taskSteps: List<String>,
    val zone: String? = null,
    val owner: String? = null,
    val source: String = "human_manual",
    val status: String = "accepted",
)

@Serializable
data class UploadComplete(
    @SerialName("scene_id") val sceneId: String,
    @SerialName("capture_id") val captureId: String,
    @SerialName("raw_prefix") val rawPrefix: String = "raw",
)
