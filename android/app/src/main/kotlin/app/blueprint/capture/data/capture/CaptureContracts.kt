package app.blueprint.capture.data.capture

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
enum class CaptureIntakeSource {
    @SerialName("authoritative")
    Authoritative,

    @SerialName("human_manual")
    HumanManual,

    @SerialName("ai_inferred")
    AiInferred,
}

@Serializable
enum class CaptureTaskHypothesisStatus {
    @SerialName("accepted")
    Accepted,

    @SerialName("needs_confirmation")
    NeedsConfirmation,

    @SerialName("rejected")
    Rejected,
}

@Serializable
enum class AndroidCaptureSource {
    @SerialName("android") AndroidPhone,
    @SerialName("glasses") MetaGlasses,
}

@Serializable
data class AndroidCaptureBundleRequest(
    @SerialName("scene_id") val sceneId: String,
    @SerialName("capture_id") val captureId: String,
    @SerialName("creator_id") val creatorId: String,
    @SerialName("job_id") val jobId: String? = null,
    @SerialName("reservation_id") val reservationId: String? = null,
    @SerialName("site_submission_id") val siteSubmissionId: String? = null,
    @SerialName("device_model") val deviceModel: String,
    @SerialName("os_version") val osVersion: String,
    @SerialName("fps_source") val fpsSource: Double,
    val width: Int,
    val height: Int,
    @SerialName("capture_start_epoch_ms") val captureStartEpochMs: Long,
    @SerialName("capture_duration_ms") val captureDurationMs: Long? = null,
    @SerialName("has_lidar") val hasLiDAR: Boolean = false,
    @SerialName("capture_source") val captureSource: AndroidCaptureSource = AndroidCaptureSource.AndroidPhone,
    @SerialName("priority_weight") val priorityWeight: Double = 0.0,
    @SerialName("capture_context_hint") val captureContextHint: String? = null,
    @SerialName("workflow_name") val workflowName: String? = null,
    @SerialName("task_steps") val taskSteps: List<String> = emptyList(),
    val zone: String? = null,
    val owner: String? = null,
    @SerialName("operator_notes") val operatorNotes: List<String> = emptyList(),
    @SerialName("intake_packet") val intakePacket: QualificationIntakePacket? = null,
    @SerialName("intake_metadata") val intakeMetadata: CaptureIntakeMetadata? = null,
    @SerialName("task_hypothesis") val taskHypothesis: TaskHypothesis? = null,
    @SerialName("quoted_payout_cents") val quotedPayoutCents: Int? = null,
    @SerialName("rights_profile") val rightsProfile: String? = null,
    @SerialName("requested_outputs") val requestedOutputs: List<String> = listOf("qualification", "review_intake"),
    // Phase 2 world-model fields
    @SerialName("site_identity") val siteIdentity: SiteIdentity? = null,
    @SerialName("capture_topology") val captureTopology: CaptureTopologyMetadata? = null,
    @SerialName("capture_mode") val captureMode: CaptureModeMetadata? = null,
    @SerialName("scaffolding_packet") val scaffoldingPacket: CaptureScaffoldingPacket? = null,
    // IMU motion sample count (from CaptureIMUSampler)
    @SerialName("motion_sample_count") val motionSampleCount: Int = 0,
)

@Serializable
data class QualificationIntakePacket(
    @SerialName("schema_version") val schemaVersion: String = "v1",
    @SerialName("workflow_name") val workflowName: String? = null,
    @SerialName("task_steps") val taskSteps: List<String> = emptyList(),
    @SerialName("target_kpi") val targetKPI: String? = null,
    val zone: String? = null,
    val shift: String? = null,
    val owner: String? = null,
    @SerialName("facility_template") val facilityTemplate: String? = null,
    @SerialName("required_coverage_areas") val requiredCoverageAreas: List<String> = emptyList(),
    @SerialName("benchmark_stations") val benchmarkStations: List<String> = emptyList(),
    @SerialName("adjacent_systems") val adjacentSystems: List<String> = emptyList(),
    @SerialName("privacy_security_limits") val privacySecurityLimits: List<String> = emptyList(),
    @SerialName("known_blockers") val knownBlockers: List<String> = emptyList(),
    @SerialName("non_routine_modes") val nonRoutineModes: List<String> = emptyList(),
    @SerialName("people_traffic_notes") val peopleTrafficNotes: List<String> = emptyList(),
    @SerialName("capture_restrictions") val captureRestrictions: List<String> = emptyList(),
    @SerialName("lighting_windows") val lightingWindows: List<String> = emptyList(),
    @SerialName("shift_traffic_windows") val shiftTrafficWindows: List<String> = emptyList(),
    @SerialName("movable_obstacles") val movableObstacles: List<String> = emptyList(),
    @SerialName("floor_condition_notes") val floorConditionNotes: List<String> = emptyList(),
    @SerialName("reflective_surface_notes") val reflectiveSurfaceNotes: List<String> = emptyList(),
    @SerialName("access_rules") val accessRules: List<String> = emptyList(),
)

@Serializable
data class SiteGeoPoint(
    val latitude: Double,
    val longitude: Double,
    @SerialName("accuracy_m") val accuracyM: Double = 0.0,
)

@Serializable
data class SiteIdentity(
    @SerialName("site_id") val siteId: String,
    @SerialName("site_id_source") val siteIdSource: String, // "buyer_request" | "site_submission" | "open_capture"
    @SerialName("place_id") val placeId: String? = null,
    @SerialName("site_name") val siteName: String? = null,
    @SerialName("address_full") val addressFull: String? = null,
    val geo: SiteGeoPoint? = null,
    @SerialName("building_id") val buildingId: String? = null,
    @SerialName("floor_id") val floorId: String? = null,
    @SerialName("room_id") val roomId: String? = null,
    @SerialName("zone_id") val zoneId: String? = null,
)

@Serializable
data class CaptureTopologyMetadata(
    @SerialName("capture_session_id") val captureSessionId: String,
    @SerialName("route_id") val routeId: String,
    @SerialName("pass_id") val passId: String,
    @SerialName("pass_index") val passIndex: Int = 0,
    // "primary" | "revisit" | "loop_closure" | "critical_zone_revisit"
    @SerialName("intended_pass_role") val intendedPassRole: String = "primary",
    @SerialName("entry_anchor_id") val entryAnchorId: String? = null,
    @SerialName("return_anchor_id") val returnAnchorId: String? = null,
    @SerialName("entry_anchor_t_capture_sec") val entryAnchorTCaptureSec: Double? = null,
    @SerialName("entry_anchor_hold_duration_sec") val entryAnchorHoldDurationSec: Double? = null,
)

@Serializable
data class CaptureModeMetadata(
    // "qualification_only" | "site_world_candidate"
    @SerialName("requested_mode") val requestedMode: String,
    @SerialName("resolved_mode") val resolvedMode: String,
    @SerialName("downgrade_reason") val downgradeReason: String? = null,
)

@Serializable
data class CaptureScaffoldingPacket(
    @SerialName("schema_version") val schemaVersion: String = "v1",
    @SerialName("scaffolding_used") val scaffoldingUsed: List<String> = emptyList(),
    @SerialName("coverage_plan") val coveragePlan: List<String> = emptyList(),
    @SerialName("calibration_assets") val calibrationAssets: List<String> = emptyList(),
    @SerialName("scale_anchor_assets") val scaleAnchorAssets: List<String> = emptyList(),
    @SerialName("checkpoint_assets") val checkpointAssets: List<String> = emptyList(),
    @SerialName("validated_scale_meters") val validatedScaleMeters: Double? = null,
    @SerialName("validated_pose_coverage") val validatedPoseCoverage: Double? = null,
    @SerialName("hidden_zone_bound") val hiddenZoneBound: Double? = null,
    @SerialName("uncertainty_priors") val uncertaintyPriors: Map<String, Double> = emptyMap(),
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
    val source: CaptureIntakeSource,
    val model: String? = null,
    val fps: Int? = null,
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
    @SerialName("capture_source") val captureSource: String = "android",
    @SerialName("capture_tier_hint") val captureTierHint: String = "tier2_android",
    @SerialName("capture_modality") val captureModality: String = "android_video_only",
    @SerialName("evidence_tier") val evidenceTier: String = "pre_screen_video",
    @SerialName("requested_outputs") val requestedOutputs: List<String>,
    @SerialName("site_identity") val siteIdentity: SiteIdentity? = null,
    @SerialName("capture_topology") val captureTopology: CaptureTopologyMetadata? = null,
    @SerialName("capture_mode") val captureMode: CaptureModeMetadata? = null,
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
    @SerialName("site_identity") val siteIdentity: SiteIdentity? = null,
    @SerialName("capture_topology") val captureTopology: CaptureTopologyMetadata? = null,
    @SerialName("capture_mode") val captureMode: CaptureModeMetadata? = null,
)

@Serializable
data class TaskHypothesis(
    @SerialName("schema_version") val schemaVersion: String = "v1",
    @SerialName("workflow_name") val workflowName: String? = null,
    @SerialName("task_steps") val taskSteps: List<String> = emptyList(),
    val zone: String? = null,
    val owner: String? = null,
    val confidence: Double? = null,
    val source: CaptureIntakeSource = CaptureIntakeSource.HumanManual,
    val model: String? = null,
    val fps: Int? = null,
    val warnings: List<String> = emptyList(),
    val status: CaptureTaskHypothesisStatus = CaptureTaskHypothesisStatus.Accepted,
)

@Serializable
data class UploadComplete(
    @SerialName("scene_id") val sceneId: String,
    @SerialName("capture_id") val captureId: String,
    @SerialName("raw_prefix") val rawPrefix: String = "raw",
)
