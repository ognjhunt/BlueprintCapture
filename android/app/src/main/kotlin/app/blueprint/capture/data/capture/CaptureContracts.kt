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
    @SerialName("android_xr_glasses") AndroidXrGlasses,
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
    @SerialName("schema_version") val schemaVersion: String = "v3",
    @SerialName("scene_id") val sceneId: String,
    @SerialName("capture_id") val captureId: String,
    @SerialName("video_uri") val videoUri: String,
    @SerialName("device_model") val deviceModel: String,
    @SerialName("device_model_marketing") val deviceModelMarketing: String = deviceModel,
    @SerialName("hardware_model_identifier") val hardwareModelIdentifier: String = deviceModel,
    @SerialName("os_version") val osVersion: String,
    @SerialName("app_version") val appVersion: String = "unknown",
    @SerialName("app_build") val appBuild: String = "unknown",
    @SerialName("fps_source") val fpsSource: Double,
    val width: Int,
    val height: Int,
    @SerialName("capture_start_epoch_ms") val captureStartEpochMs: Long,
    @SerialName("has_lidar") val hasLiDAR: Boolean,
    @SerialName("depth_supported") val depthSupported: Boolean = hasLiDAR,
    @SerialName("capture_schema_version") val captureSchemaVersion: String = "3.1.0",
    @SerialName("capture_source") val captureSource: String = "android",
    @SerialName("capture_tier_hint") val captureTierHint: String = "tier2_android",
    @SerialName("coordinate_frame_session_id") val coordinateFrameSessionId: String,
    @SerialName("capture_modality") val captureModality: String = "android_video_only",
    @SerialName("capture_profile_id") val captureProfileId: String = "android_camera_only",
    @SerialName("evidence_tier") val evidenceTier: String = "pre_screen_video",
    @SerialName("rights_profile") val rightsProfile: String = "unknown",
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
    @SerialName("capture_capabilities") val captureCapabilities: CaptureCapabilities = CaptureCapabilities(),
)

@Serializable
enum class CaptureAuthority {
    @SerialName("authoritative_raw")
    AuthoritativeRaw,

    @SerialName("raw_tracking_only")
    RawTrackingOnly,

    @SerialName("diagnostic_only")
    DiagnosticOnly,

    @SerialName("not_available")
    NotAvailable,

    @SerialName("derived_later_expected")
    DerivedLaterExpected,
}

@Serializable
data class SceneMemoryCapture(
    @SerialName("continuity_score") val continuityScore: Double? = null,
    @SerialName("lighting_consistency") val lightingConsistency: String = "unknown",
    @SerialName("dynamic_object_density") val dynamicObjectDensity: String = "unknown",
    @SerialName("sensor_availability") val sensorAvailability: SensorAvailability = SensorAvailability(),
    @SerialName("operator_notes") val operatorNotes: List<String> = emptyList(),
    @SerialName("inaccessible_areas") val inaccessibleAreas: List<String> = emptyList(),
    @SerialName("world_model_candidate") val worldModelCandidate: Boolean = false,
    @SerialName("motion_provenance") val motionProvenance: String? = null,
    @SerialName("motion_timestamps_capture_relative") val motionTimestampsCaptureRelative: Boolean = true,
    @SerialName("geometry_source") val geometrySource: String? = null,
    @SerialName("geometry_expected_downstream") val geometryExpectedDownstream: Boolean = true,
)

@Serializable
data class SensorAvailability(
    @SerialName("arkit_poses") val arkitPoses: Boolean = false,
    @SerialName("arkit_intrinsics") val arkitIntrinsics: Boolean = false,
    @SerialName("arkit_depth") val arkitDepth: Boolean = false,
    @SerialName("arkit_confidence") val arkitConfidence: Boolean = false,
    @SerialName("arkit_meshes") val arkitMeshes: Boolean = false,
    @SerialName("camera_pose") val cameraPose: Boolean = false,
    @SerialName("camera_intrinsics") val cameraIntrinsics: Boolean = false,
    val depth: Boolean = false,
    @SerialName("depth_confidence") val depthConfidence: Boolean = false,
    val mesh: Boolean = false,
    @SerialName("point_cloud") val pointCloud: Boolean = false,
    val planes: Boolean = false,
    @SerialName("feature_points") val featurePoints: Boolean = false,
    @SerialName("tracking_state") val trackingState: Boolean = false,
    @SerialName("relocalization_events") val relocalizationEvents: Boolean = false,
    @SerialName("light_estimate") val lightEstimate: Boolean = false,
    val motion: Boolean = true,
    @SerialName("motion_authoritative") val motionAuthoritative: Boolean = false,
    @SerialName("companion_phone_pose") val companionPhonePose: Boolean = false,
    @SerialName("companion_phone_intrinsics") val companionPhoneIntrinsics: Boolean = false,
    @SerialName("companion_phone_calibration") val companionPhoneCalibration: Boolean = false,
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
    @SerialName("pose_rows") val poseRows: Int = 0,
    @SerialName("intrinsics_valid") val intrinsicsValid: Boolean = false,
    @SerialName("depth_frames") val depthFrames: Int = 0,
    @SerialName("confidence_frames") val confidenceFrames: Int = 0,
    @SerialName("mesh_files") val meshFiles: Int = 0,
    @SerialName("point_cloud_samples") val pointCloudSamples: Int = 0,
    @SerialName("plane_rows") val planeRows: Int = 0,
    @SerialName("feature_point_rows") val featurePointRows: Int = 0,
    @SerialName("tracking_state_rows") val trackingStateRows: Int = 0,
    @SerialName("relocalization_event_rows") val relocalizationEventRows: Int = 0,
    @SerialName("light_estimate_rows") val lightEstimateRows: Int = 0,
    @SerialName("motion_samples") val motionSamples: Int = 0,
    @SerialName("pose_authority") val poseAuthority: CaptureAuthority = CaptureAuthority.NotAvailable,
    @SerialName("intrinsics_authority") val intrinsicsAuthority: CaptureAuthority = CaptureAuthority.NotAvailable,
    @SerialName("depth_authority") val depthAuthority: CaptureAuthority = CaptureAuthority.NotAvailable,
    @SerialName("motion_authority") val motionAuthority: CaptureAuthority = CaptureAuthority.DiagnosticOnly,
    @SerialName("motion_provenance") val motionProvenance: String? = null,
    @SerialName("motion_timestamps_capture_relative") val motionTimestampsCaptureRelative: Boolean = true,
    @SerialName("geometry_source") val geometrySource: String? = null,
    @SerialName("geometry_expected_downstream") val geometryExpectedDownstream: Boolean = true,
)

@Serializable
data class CaptureCapabilities(
    @SerialName("camera_pose") val cameraPose: Boolean = false,
    @SerialName("camera_intrinsics") val cameraIntrinsics: Boolean = false,
    val depth: Boolean = false,
    @SerialName("depth_confidence") val depthConfidence: Boolean = false,
    val mesh: Boolean = false,
    @SerialName("point_cloud") val pointCloud: Boolean = false,
    val planes: Boolean = false,
    @SerialName("feature_points") val featurePoints: Boolean = false,
    @SerialName("tracking_state") val trackingState: Boolean = false,
    @SerialName("relocalization_events") val relocalizationEvents: Boolean = false,
    @SerialName("light_estimate") val lightEstimate: Boolean = false,
    val motion: Boolean = true,
    @SerialName("motion_authoritative") val motionAuthoritative: Boolean = false,
    @SerialName("companion_phone_pose") val companionPhonePose: Boolean = false,
    @SerialName("companion_phone_intrinsics") val companionPhoneIntrinsics: Boolean = false,
    @SerialName("companion_phone_calibration") val companionPhoneCalibration: Boolean = false,
    @SerialName("pose_rows") val poseRows: Int = 0,
    @SerialName("intrinsics_valid") val intrinsicsValid: Boolean = false,
    @SerialName("depth_frames") val depthFrames: Int = 0,
    @SerialName("confidence_frames") val confidenceFrames: Int = 0,
    @SerialName("mesh_files") val meshFiles: Int = 0,
    @SerialName("point_cloud_samples") val pointCloudSamples: Int = 0,
    @SerialName("plane_rows") val planeRows: Int = 0,
    @SerialName("feature_point_rows") val featurePointRows: Int = 0,
    @SerialName("tracking_state_rows") val trackingStateRows: Int = 0,
    @SerialName("relocalization_event_rows") val relocalizationEventRows: Int = 0,
    @SerialName("light_estimate_rows") val lightEstimateRows: Int = 0,
    @SerialName("motion_samples") val motionSamples: Int = 0,
    @SerialName("pose_authority") val poseAuthority: CaptureAuthority = CaptureAuthority.NotAvailable,
    @SerialName("intrinsics_authority") val intrinsicsAuthority: CaptureAuthority = CaptureAuthority.NotAvailable,
    @SerialName("depth_authority") val depthAuthority: CaptureAuthority = CaptureAuthority.NotAvailable,
    @SerialName("motion_authority") val motionAuthority: CaptureAuthority = CaptureAuthority.DiagnosticOnly,
    @SerialName("motion_provenance") val motionProvenance: String? = null,
    @SerialName("geometry_source") val geometrySource: String? = null,
    @SerialName("geometry_expected_downstream") val geometryExpectedDownstream: Boolean = true,
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
    @SerialName("capture_profile_id") val captureProfileId: String = "android_camera_only",
    @SerialName("capture_capabilities") val captureCapabilities: CaptureCapabilities = CaptureCapabilities(),
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
    @SerialName("schema_version") val schemaVersion: String = "v1",
    @SerialName("scene_id") val sceneId: String,
    @SerialName("capture_id") val captureId: String,
    @SerialName("raw_prefix") val rawPrefix: String = "raw",
)

@Serializable
data class RightsConsentFile(
    @SerialName("schema_version") val schemaVersion: String = "v1",
    @SerialName("scene_id") val sceneId: String,
    @SerialName("capture_id") val captureId: String,
    @SerialName("consent_status") val consentStatus: String = "unknown",
    @SerialName("capture_basis") val captureBasis: String = "unknown",
    @SerialName("derived_scene_generation_allowed") val derivedSceneGenerationAllowed: Boolean = false,
    @SerialName("data_licensing_allowed") val dataLicensingAllowed: Boolean = false,
    @SerialName("capture_contributor_payout_eligible") val captureContributorPayoutEligible: Boolean = false,
    @SerialName("permission_document_uri") val permissionDocumentUri: String? = null,
    @SerialName("permission_document_sha256") val permissionDocumentSha256: String? = null,
    @SerialName("consent_scope") val consentScope: List<String> = emptyList(),
    @SerialName("consent_notes") val consentNotes: List<String> = emptyList(),
    @SerialName("redaction_required") val redactionRequired: Boolean = true,
)

@Serializable
data class ProvenanceFile(
    @SerialName("schema_version") val schemaVersion: String = "v1",
    @SerialName("scene_id") val sceneId: String,
    @SerialName("capture_id") val captureId: String,
    @SerialName("capture_source") val captureSource: String,
    @SerialName("captured_by_user_id") val capturedByUserId: String,
    @SerialName("uploaded_by_user_id") val uploadedByUserId: String,
    @SerialName("capture_app_build") val captureAppBuild: String = "unknown",
    @SerialName("capture_app_version") val captureAppVersion: String = "unknown",
    @SerialName("device_installation_id") val deviceInstallationId: String,
    @SerialName("bundle_created_at") val bundleCreatedAt: String,
    @SerialName("upload_completed_at") val uploadCompletedAt: String,
    @SerialName("bundle_sha256") val bundleSha256: String,
)

@Serializable
data class VideoTrackFile(
    @SerialName("schema_version") val schemaVersion: String = "v1",
    @SerialName("video_file") val videoFile: String,
    @SerialName("duration_sec") val durationSec: Double,
    @SerialName("frame_count") val frameCount: Int,
    @SerialName("nominal_fps") val nominalFps: Double,
    @SerialName("contains_vfr") val containsVfr: Boolean = false,
    @SerialName("video_start_pts_sec") val videoStartPtsSec: Double = 0.0,
    val width: Int,
    val height: Int,
    val orientation: String = "portrait",
    val codec: String = "mp4",
    @SerialName("color_space") val colorSpace: String = "unknown",
)

@Serializable
data class HashesFile(
    @SerialName("schema_version") val schemaVersion: String = "v1",
    @SerialName("bundle_sha256") val bundleSha256: String,
    val artifacts: Map<String, String>,
)

@Serializable
data class RecordingSessionFile(
    @SerialName("schema_version") val schemaVersion: String = "v1",
    @SerialName("scene_id") val sceneId: String,
    @SerialName("capture_id") val captureId: String,
    @SerialName("site_visit_id") val siteVisitId: String,
    @SerialName("route_id") val routeId: String,
    @SerialName("pass_id") val passId: String,
    @SerialName("pass_index") val passIndex: Int,
    @SerialName("pass_role") val passRole: String,
    @SerialName("coordinate_frame_session_id") val coordinateFrameSessionId: String,
    @SerialName("arkit_session_id") val arkitSessionId: String,
    @SerialName("world_frame_definition") val worldFrameDefinition: String,
    val units: String,
    val handedness: String,
    @SerialName("gravity_aligned") val gravityAligned: Boolean,
    @SerialName("session_reset_count") val sessionResetCount: Int,
    @SerialName("captured_at") val capturedAt: String,
)

@Serializable
data class RelocalizationEventRecord(
    @SerialName("start_frame_id") val startFrameId: String? = null,
    @SerialName("end_frame_id") val endFrameId: String? = null,
    @SerialName("start_t_capture_sec") val startTCaptureSec: Double? = null,
    @SerialName("end_t_capture_sec") val endTCaptureSec: Double? = null,
    @SerialName("frame_count") val frameCount: Int = 0,
    val recovered: Boolean = false,
    val source: String = "tracking_state_transition",
)

@Serializable
data class RouteAnchorsFile(
    @SerialName("schema_version") val schemaVersion: String = "v1",
    @SerialName("route_anchors") val routeAnchors: List<Map<String, String>> = emptyList(),
)

@Serializable
data class CheckpointEventsFile(
    @SerialName("schema_version") val schemaVersion: String = "v1",
    @SerialName("checkpoint_events") val checkpointEvents: List<Map<String, String>> = emptyList(),
)

@Serializable
data class RelocalizationEventsFile(
    @SerialName("schema_version") val schemaVersion: String = "v1",
    @SerialName("relocalization_events") val relocalizationEvents: List<RelocalizationEventRecord> = emptyList(),
)

@Serializable
data class SyncMapRow(
    @SerialName("frame_id") val frameId: String,
    @SerialName("t_video_sec") val tVideoSec: Double,
    @SerialName("t_capture_sec") val tCaptureSec: Double,
    @SerialName("pose_frame_id") val poseFrameId: String? = null,
    @SerialName("sync_status") val syncStatus: String,
    @SerialName("delta_ms") val deltaMs: Double? = null,
    @SerialName("t_monotonic_ns") val tMonotonicNs: Long? = null,
    @SerialName("coordinate_frame_session_id") val coordinateFrameSessionId: String? = null,
)

@Serializable
data class OverlapGraphFile(
    @SerialName("schema_version") val schemaVersion: String = "v1",
    @SerialName("site_visit_id") val siteVisitId: String,
    @SerialName("route_id") val routeId: String,
    @SerialName("pass_id") val passId: String,
    @SerialName("pass_role") val passRole: String,
    @SerialName("coordinate_frame_session_id") val coordinateFrameSessionId: String,
    @SerialName("observed_anchor_ids") val observedAnchorIds: List<String> = emptyList(),
    @SerialName("semantic_anchor_ids") val semanticAnchorIds: List<String> = emptyList(),
    @SerialName("relocalization_event_count") val relocalizationEventCount: Int = 0,
)
