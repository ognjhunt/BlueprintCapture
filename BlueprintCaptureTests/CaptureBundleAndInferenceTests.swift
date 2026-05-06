import Foundation
import Testing
@testable import BlueprintCapture

private func makeRawManifestData(
    sceneId: String,
    captureId: String,
    videoUri: String,
    captureProfileId: String,
    captureCapabilities: [String: Any]
) throws -> Data {
    let manifest: [String: Any] = [
        "schema_version": "v3",
        "capture_schema_version": "3.1.0",
        "scene_id": sceneId,
        "capture_id": captureId,
        "capture_source": "iphone",
        "capture_tier_hint": "tier1_iphone",
        "coordinate_frame_session_id": "cfs-1",
        "video_uri": videoUri,
        "capture_start_epoch_ms": 1_700_000_000_000,
        "app_version": "1.0.0",
        "app_build": "100",
        "ios_version": "18.3.1",
        "ios_build": "22D68",
        "hardware_model_identifier": "iPhone16,2",
        "device_model_marketing": "iPhone 15 Pro",
        "capture_profile_id": captureProfileId,
        "capture_capabilities": captureCapabilities,
        "has_lidar": true,
        "depth_supported": true,
        "fps_source": 30.0,
        "width": 1920,
        "height": 1440,
    ]
    return try JSONSerialization.data(withJSONObject: manifest)
}

struct CaptureBundleAndInferenceTests {

    @Test
    func finalizerAndExportProducePipelineReadyBundle() async throws {
        let fileManager = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("capture-bundle-\(UUID().uuidString)", isDirectory: true)
        let raw = root.appendingPathComponent("raw-source", isDirectory: true)
        let arkit = raw.appendingPathComponent("arkit", isDirectory: true)
        try fileManager.createDirectory(at: arkit, withIntermediateDirectories: true)

        try Data("video".utf8).write(to: raw.appendingPathComponent("walkthrough.mov"))
        try makeRawManifestData(
            sceneId: "scene-123",
            captureId: "capture-123",
            videoUri: "raw/walkthrough.mov",
            captureProfileId: "iphone_arkit_non_lidar",
            captureCapabilities: [
                "camera_pose": false,
                "depth": false,
                "motion": false
            ]
        ).write(to: raw.appendingPathComponent("manifest.json"))
        try Data("{}".utf8).write(to: arkit.appendingPathComponent("intrinsics.json"))
        try Data("".utf8).write(to: raw.appendingPathComponent("motion.jsonl"))

        let metadata = CaptureUploadMetadata(
            id: UUID(),
            targetId: "scene-123",
            reservationId: nil,
            jobId: "scene-123",
            captureJobId: "scene-123",
            buyerRequestId: "req-scene-123",
            siteSubmissionId: "scene-123",
            regionId: "bay-area",
            creatorId: "tester",
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            uploadedAt: nil,
            captureSource: .iphoneVideo,
            specialTaskType: .buyerRequested,
            priorityWeight: 1.25,
            quotedPayoutCents: 4500,
            rightsProfile: "documented_permission",
            requestedOutputs: ["qualification", "preview_simulation"],
            intakePacket: QualificationIntakePacket(
                workflowName: "Inbound walk",
                taskSteps: ["Enter aisle", "Walk route"],
                zone: "Aisle 4"
            ),
            intakeMetadata: CaptureIntakeMetadata(source: .aiInferred, model: "gemini-3-flash-preview", fps: 3, confidence: 0.72),
            taskHypothesis: nil,
            scaffoldingPacket: CaptureScaffoldingPacket(scaffoldingUsed: ["arkit_depth"]),
            captureModality: "iphone_arkit_lidar",
            evidenceTier: nil,
            captureContextHint: "Target scene",
            sceneMemory: SceneMemoryCaptureMetadata(
                continuityScore: 0.88,
                lightingConsistency: "stable",
                dynamicObjectDensity: "low",
                operatorNotes: ["Kept camera height steady"],
                inaccessibleAreas: ["Locked mezzanine"]
            ),
            captureRights: CaptureRightsMetadata(
                derivedSceneGenerationAllowed: false,
                dataLicensingAllowed: true,
                payoutEligible: true,
                consentStatus: .documented,
                permissionDocumentURI: "https://example.com/permission.pdf",
                consentScope: ["Sales floor", "Entry"],
                consentNotes: ["Site owner approved downstream preview generation"]
            ),
            siteIdentity: nil,
            captureTopology: nil,
            captureMode: nil
        )
        let request = CaptureUploadRequest(packageURL: raw, metadata: metadata)

        let finalizer = CaptureBundleFinalizer()
        _ = try finalizer.finalize(request: request, mode: .localExport())
        #expect(finalizer.validateRawBundle(in: raw).isEmpty)

        let manifestObject = try JSONSerialization.jsonObject(with: Data(contentsOf: raw.appendingPathComponent("manifest.json")))
        let manifest = try #require(manifestObject as? [String: Any])
        #expect(manifest["scene_id"] as? String == "scene-123")
        #expect(manifest["site_submission_id"] as? String == "scene-123")
        #expect(manifest["video_uri"] as? String == "raw/walkthrough.mov")
        #expect(manifest["capture_modality"] as? String == "iphone_video_only")
        #expect(manifest["capture_profile_id"] as? String == "iphone_arkit_non_lidar")
        #expect(manifest["evidence_tier"] as? String == "pre_screen_video")
        #expect(manifest["task_text_hint"] as? String == "Inbound walk")
        #expect((manifest["task_steps"] as? [String]) == ["Enter aisle", "Walk route"])
        #expect(manifest["target_kpi"] as? String == nil)
        #expect(manifest["zone"] as? String == "Aisle 4")
        #expect(manifest["shift"] as? String == nil)
        #expect(manifest["owner"] as? String == nil)
        #expect((manifest["scaffolding_used"] as? [String]) == [])
        let captureProfile = try #require(manifest["capture_profile"] as? [String: Any])
        #expect(captureProfile["facility_template"] as? String == nil)
        #expect((captureProfile["benchmark_stations"] as? [String]) == [])
        #expect((captureProfile["adjacent_systems"] as? [String]) == [])
        #expect((captureProfile["capture_restrictions"] as? [String]) == [])
        let sceneMemory = try #require(manifest["scene_memory_capture"] as? [String: Any])
        #expect(sceneMemory["world_model_candidate"] as? Bool == false)
        let sensorAvailability = try #require(sceneMemory["sensor_availability"] as? [String: Any])
        #expect(sensorAvailability["arkit_intrinsics"] as? Bool == false)
        #expect(sensorAvailability["arkit_poses"] as? Bool == false)
        #expect(sensorAvailability["arkit_meshes"] as? Bool == false)
        #expect(sensorAvailability["motion"] as? Bool == false)
        let captureEvidence = try #require(manifest["capture_evidence"] as? [String: Any])
        #expect(captureEvidence["arkit_intrinsics_valid"] as? Bool == false)
        #expect(captureEvidence["arkit_pose_rows"] as? Int == 0)
        #expect(captureEvidence["depth_authority"] as? String == "not_available")
        let captureCapabilities = try #require(manifest["capture_capabilities"] as? [String: Any])
        #expect(captureCapabilities["camera_pose"] as? Bool == false)
        #expect(captureCapabilities["depth"] as? Bool == false)
        #expect(captureCapabilities["geometry_expected_downstream"] as? Bool == false)
        let captureRights = try #require(manifest["capture_rights"] as? [String: Any])
        #expect(captureRights["data_licensing_allowed"] as? Bool == true)
        #expect(captureRights["derived_scene_generation_allowed"] as? Bool == false)
        #expect(captureRights["consent_status"] as? String == "documented")
        #expect(captureRights["permission_document_uri"] as? String == "https://example.com/permission.pdf")
        #expect((captureRights["consent_scope"] as? [String]) == ["Sales floor", "Entry"])
        #expect(manifest["object_point_cloud_index"] == nil)
        #expect(manifest["object_point_cloud_count"] == nil)

        let completionObject = try JSONSerialization.jsonObject(with: Data(contentsOf: raw.appendingPathComponent("capture_upload_complete.json")))
        let completion = try #require(completionObject as? [String: Any])
        #expect(completion["raw_prefix"] as? String == "raw")

        let contextObject = try JSONSerialization.jsonObject(with: Data(contentsOf: raw.appendingPathComponent("capture_context.json")))
        let context = try #require(contextObject as? [String: Any])
        #expect(context["site_submission_id"] as? String == "scene-123")
        #expect(context["intake_source"] as? String == "ai_inferred")
        #expect(context["intake_inference_model"] as? String == "gemini-3-flash-preview")
        #expect(context["task_hypothesis_status"] as? String == "accepted")
        #expect(context["task_text_hint"] as? String == "Inbound walk")
        #expect((context["task_steps"] as? [String]) == ["Enter aisle", "Walk route"])
        #expect(context["world_model_candidate"] as? Bool == false)
        let contextCaptureRights = try #require(context["capture_rights"] as? [String: Any])
        #expect(contextCaptureRights["consent_status"] as? String == "documented")
        #expect(contextCaptureRights["permission_document_uri"] as? String == "https://example.com/permission.pdf")
        #expect((contextCaptureRights["consent_scope"] as? [String]) == ["Sales floor", "Entry"])
        let contextEvidence = try #require(context["capture_evidence"] as? [String: Any])
        #expect(contextEvidence["arkit_intrinsics_valid"] as? Bool == false)
        #expect(contextEvidence["motion_samples"] as? Int == 0)
        #expect(context["capture_profile_id"] as? String == "iphone_arkit_non_lidar")
        let contextCapabilities = try #require(context["capture_capabilities"] as? [String: Any])
        #expect(contextCapabilities["camera_intrinsics"] as? Bool == false)

        let hypothesisObject = try JSONSerialization.jsonObject(with: Data(contentsOf: raw.appendingPathComponent("task_hypothesis.json")))
        let hypothesis = try #require(hypothesisObject as? [String: Any])
        #expect(hypothesis["workflow_name"] as? String == "Inbound walk")
        #expect(hypothesis["status"] as? String == "accepted")
        #expect(hypothesis["source"] as? String == "ai_inferred")

        let exporter = CaptureExportService(finalizer: finalizer)
        let bundle = try await exporter.exportCapture(request: request)
        #expect(bundle.captureRootURL.path.contains("/scenes/scene-123/captures/"))
        #expect(fileManager.fileExists(atPath: bundle.rawDirectoryURL.appendingPathComponent("manifest.json").path))
        #expect(fileManager.fileExists(atPath: bundle.rawDirectoryURL.appendingPathComponent("walkthrough.mov").path))
        #expect(fileManager.fileExists(atPath: bundle.rawDirectoryURL.appendingPathComponent("arkit/intrinsics.json").path))
        #expect(fileManager.fileExists(atPath: bundle.rawDirectoryURL.appendingPathComponent("rights_consent.json").path))
        #expect(fileManager.fileExists(atPath: bundle.rawDirectoryURL.appendingPathComponent("provenance.json").path))
        #expect(fileManager.fileExists(atPath: bundle.rawDirectoryURL.appendingPathComponent("sync_map.jsonl").path))
        #expect(fileManager.fileExists(atPath: (bundle.shareURL ?? bundle.captureRootURL).path))
    }

    @Test
    func finalizerPreservesValidARKitEvidenceAndManualHypothesisSource() throws {
        let fileManager = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("capture-evidence-\(UUID().uuidString)", isDirectory: true)
        let raw = root.appendingPathComponent("raw-source", isDirectory: true)
        let arkit = raw.appendingPathComponent("arkit", isDirectory: true)
        try fileManager.createDirectory(at: arkit.appendingPathComponent("depth", isDirectory: true), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: arkit.appendingPathComponent("confidence", isDirectory: true), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: arkit.appendingPathComponent("meshes", isDirectory: true), withIntermediateDirectories: true)

        try Data("video".utf8).write(to: raw.appendingPathComponent("walkthrough.mov"))
        try makeRawManifestData(
            sceneId: "scene-sidecars",
            captureId: "capture-sidecars",
            videoUri: "raw/walkthrough.mov",
            captureProfileId: "iphone_arkit_lidar",
            captureCapabilities: [
                "camera_pose": true,
                "depth": true,
                "motion": true
            ]
        ).write(to: raw.appendingPathComponent("manifest.json"))
        try Data("{\"fx\":1200,\"fy\":1195,\"cx\":640,\"cy\":360,\"width\":1280,\"height\":720}".utf8)
            .write(to: arkit.appendingPathComponent("intrinsics.json"))
        try Data("{\"frame_id\":\"000001\",\"t_device_sec\":0.0,\"T_world_camera\":[[1,0,0,0],[0,1,0,0],[0,0,1,0],[0,0,0,1]]}\n".utf8)
            .write(to: arkit.appendingPathComponent("poses.jsonl"))
        try Data("{\"frame_index\":0}\n".utf8).write(to: arkit.appendingPathComponent("frames.jsonl"))
        try Data([0x01]).write(to: arkit.appendingPathComponent("depth/000001.png"))
        try Data([0x01]).write(to: arkit.appendingPathComponent("confidence/000001.png"))
        try Data("v 0 0 0\n".utf8).write(to: arkit.appendingPathComponent("meshes/mesh-1.obj"))
        try Data("{\"timestamp\":1.0,\"t_capture_sec\":0.1,\"motion_provenance\":\"phone_imu_diagnostic_only\"}\n".utf8)
            .write(to: raw.appendingPathComponent("motion.jsonl"))

        let baseRequest = CaptureUploadRequest(packageURL: raw, metadata: CaptureUploadMetadata(
            id: UUID(),
            targetId: "scene-arkit",
            reservationId: nil,
            jobId: "scene-arkit",
            captureJobId: "scene-arkit",
            buyerRequestId: nil,
            siteSubmissionId: "scene-arkit",
            regionId: nil,
            creatorId: "tester",
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            uploadedAt: nil,
            captureSource: .iphoneVideo,
            specialTaskType: .curatedNearby,
            priorityWeight: 1.0,
            quotedPayoutCents: nil,
            rightsProfile: nil,
            requestedOutputs: ["qualification"],
            intakePacket: nil,
            intakeMetadata: nil,
            taskHypothesis: nil,
            scaffoldingPacket: CaptureScaffoldingPacket(coveragePlan: ["Cover dock turns"]),
            captureModality: nil,
            evidenceTier: nil,
            captureContextHint: nil,
            sceneMemory: SceneMemoryCaptureMetadata(continuityScore: 0.9),
            captureRights: nil,
            siteIdentity: nil,
            captureTopology: nil,
            captureMode: nil
        )).withManualIntake(QualificationIntakePacket(
            workflowName: "Inbound walk",
            taskSteps: ["Enter aisle", "Walk route"],
            zone: "Aisle 4"
        ))

        let finalizer = CaptureBundleFinalizer()
        _ = try finalizer.finalize(request: baseRequest, mode: .localExport())

        let manifestObject = try JSONSerialization.jsonObject(with: Data(contentsOf: raw.appendingPathComponent("manifest.json")))
        let manifest = try #require(manifestObject as? [String: Any])
        #expect(manifest["capture_modality"] as? String == "iphone_arkit_lidar")
        #expect(manifest["capture_profile_id"] as? String == "iphone_arkit_lidar")
        #expect(manifest["evidence_tier"] as? String == "qualified_metric_capture")
        #expect((manifest["scaffolding_used"] as? [String]) == ["arkit_depth", "arkit_meshes", "arkit_pose_log"])

        let sceneMemory = try #require(manifest["scene_memory_capture"] as? [String: Any])
        let sensorAvailability = try #require(sceneMemory["sensor_availability"] as? [String: Any])
        #expect(sensorAvailability["arkit_poses"] as? Bool == true)
        #expect(sensorAvailability["arkit_intrinsics"] as? Bool == true)
        #expect(sensorAvailability["arkit_depth"] as? Bool == true)
        #expect(sceneMemory["geometry_source"] as? String == "arkit")
        #expect(sceneMemory["geometry_expected_downstream"] as? Bool == false)
        #expect(sceneMemory["motion_provenance"] as? String == "phone_imu_diagnostic_only")
        #expect(sceneMemory["motion_timestamps_capture_relative"] as? Bool == true)

        let contextObject = try JSONSerialization.jsonObject(with: Data(contentsOf: raw.appendingPathComponent("capture_context.json")))
        let context = try #require(contextObject as? [String: Any])
        let contextEvidence = try #require(context["capture_evidence"] as? [String: Any])
        #expect(contextEvidence["motion_provenance"] as? String == "phone_imu_diagnostic_only")
        #expect(contextEvidence["motion_timestamps_capture_relative"] as? Bool == true)
        #expect(contextEvidence["arkit_pose_rows"] as? Int == 1)
        #expect(contextEvidence["pose_authority"] as? String == "authoritative_raw")
        let contextCapabilities = try #require(context["capture_capabilities"] as? [String: Any])
        #expect(contextCapabilities["camera_pose"] as? Bool == true)
        #expect(contextCapabilities["depth_authority"] as? String == "authoritative_raw")

        let hypothesisObject = try JSONSerialization.jsonObject(with: Data(contentsOf: raw.appendingPathComponent("task_hypothesis.json")))
        let hypothesis = try #require(hypothesisObject as? [String: Any])
        #expect(hypothesis["source"] as? String == "human_manual")
        #expect(hypothesis["status"] as? String == "accepted")
    }

    @Test
    func finalizerWritesRecordingSessionAndARKitDerivedSidecars() throws {
        let fileManager = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("capture-sidecars-\(UUID().uuidString)", isDirectory: true)
        let raw = root.appendingPathComponent("raw-source", isDirectory: true)
        let arkit = raw.appendingPathComponent("arkit", isDirectory: true)
        try fileManager.createDirectory(at: arkit.appendingPathComponent("depth", isDirectory: true), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: arkit.appendingPathComponent("confidence", isDirectory: true), withIntermediateDirectories: true)

        try Data("video".utf8).write(to: raw.appendingPathComponent("walkthrough.mov"))
        try makeRawManifestData(
            sceneId: "scene-sidecars",
            captureId: "capture-sidecars",
            videoUri: "raw/walkthrough.mov",
            captureProfileId: "iphone_arkit_lidar",
            captureCapabilities: [
                "camera_pose": true,
                "depth": true,
                "motion": true
            ]
        ).write(to: raw.appendingPathComponent("manifest.json"))
        try Data("{\"fx\":1200,\"fy\":1195,\"cx\":640,\"cy\":360,\"width\":1280,\"height\":720}".utf8)
            .write(to: arkit.appendingPathComponent("intrinsics.json"))
        try Data("{\"frame_id\":\"000001\",\"t_device_sec\":0.0,\"T_world_camera\":[[1,0,0,0],[0,1,0,0],[0,0,1,0],[0,0,0,1]]}\n".utf8)
            .write(to: arkit.appendingPathComponent("poses.jsonl"))
        try Data("""
{"frameId":"000001","tCaptureSec":0.0,"sceneDepthFile":"arkit/depth/000001.png","confidenceFile":"arkit/confidence/000001.png","trackingState":"normal","worldMappingStatus":"mapped","relocalizationEvent":false,"sharpnessScore":123.4,"depthValidFraction":0.84,"missingDepthFraction":0.16,"anchorObservations":["anchor_entry","semantic_doorway"],"coordinateFrameSessionId":"arkit-session-1"}
""".utf8).write(to: arkit.appendingPathComponent("frames.jsonl"))
        try Data([0x01]).write(to: arkit.appendingPathComponent("depth/000001.png"))
        try Data([0x01]).write(to: arkit.appendingPathComponent("confidence/000001.png"))
        try Data("{\"timestamp\":1.0,\"t_capture_sec\":0.1,\"motion_provenance\":\"phone_imu\"}\n".utf8)
            .write(to: raw.appendingPathComponent("motion.jsonl"))

        let metadata = CaptureUploadMetadata(
            id: UUID(),
            targetId: "scene-sidecars",
            reservationId: nil,
            jobId: "scene-sidecars",
            captureJobId: "scene-sidecars",
            buyerRequestId: nil,
            siteSubmissionId: "scene-sidecars",
            regionId: nil,
            creatorId: "tester",
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            uploadedAt: nil,
            captureSource: .iphoneVideo,
            specialTaskType: .curatedNearby,
            priorityWeight: 1.0,
            quotedPayoutCents: nil,
            rightsProfile: nil,
            requestedOutputs: ["qualification", "preview_simulation"],
            intakePacket: QualificationIntakePacket(workflowName: "Loop route", taskSteps: ["Entry"], zone: "Dock"),
            intakeMetadata: nil,
            taskHypothesis: nil,
            scaffoldingPacket: nil,
            captureModality: nil,
            evidenceTier: nil,
            captureContextHint: nil,
            sceneMemory: SceneMemoryCaptureMetadata(semanticAnchorsObserved: ["doorway"]),
            captureRights: CaptureRightsMetadata(derivedSceneGenerationAllowed: true),
            siteIdentity: SiteIdentity(
                siteId: "site-123",
                siteIdSource: "buyer_request",
                placeId: "place-123",
                siteName: "Warehouse A",
                addressFull: "100 Example St",
                geo: SiteGeoPoint(latitude: 1.0, longitude: 2.0, accuracyM: 12.0),
                buildingId: nil,
                floorId: nil,
                roomId: nil,
                zoneId: "dock_a"
            ),
            captureTopology: CaptureTopologyMetadata(
                captureSessionId: "visit-1",
                routeId: "route-1",
                passId: "pass-1",
                passIndex: 2,
                intendedPassRole: "loop_closure",
                entryAnchorId: "anchor_entry",
                returnAnchorId: nil,
                entryAnchorTCaptureSec: 0.0,
                entryAnchorHoldDurationSec: 2.1,
                siteVisitId: "visit-1",
                coordinateFrameSessionId: "arkit-session-1",
                arkitSessionId: "arkit-session-1"
            ),
            captureMode: CaptureModeMetadata(
                requestedMode: "site_world_candidate",
                resolvedMode: "site_world_candidate",
                downgradeReason: nil
            ),
            semanticAnchors: [
                CaptureSemanticAnchorEvent(
                    anchorType: .doorway,
                    label: "Doorway",
                    frameId: "000001",
                    tCaptureSec: 0.0,
                    coordinateFrameSessionId: "arkit-session-1"
                )
            ]
        )
        let request = CaptureUploadRequest(packageURL: raw, metadata: metadata)

        let finalizer = CaptureBundleFinalizer()
        _ = try finalizer.finalize(request: request, mode: .localExport())

        #expect(fileManager.fileExists(atPath: raw.appendingPathComponent("capture_mode.json").path))
        #expect(fileManager.fileExists(atPath: raw.appendingPathComponent("recording_session.json").path))
        #expect(fileManager.fileExists(atPath: raw.appendingPathComponent("relocalization_events.json").path))
        #expect(fileManager.fileExists(atPath: raw.appendingPathComponent("overlap_graph.json").path))
        #expect(fileManager.fileExists(atPath: raw.appendingPathComponent("semantic_anchors.json").path))
        #expect(fileManager.fileExists(atPath: raw.appendingPathComponent("arkit/frame_quality.jsonl").path))
        #expect(fileManager.fileExists(atPath: raw.appendingPathComponent("arkit/depth_manifest.json").path))
        #expect(fileManager.fileExists(atPath: raw.appendingPathComponent("arkit/confidence_manifest.json").path))
        #expect(fileManager.fileExists(atPath: raw.appendingPathComponent("arkit/session_intrinsics.json").path))

        let topologyObject = try JSONSerialization.jsonObject(with: Data(contentsOf: raw.appendingPathComponent("capture_topology.json")))
        let topology = try #require(topologyObject as? [String: Any])
        #expect(topology["site_visit_id"] as? String == "visit-1")
        #expect(topology["coordinate_frame_session_id"] as? String == "arkit-session-1")

        let recordingObject = try JSONSerialization.jsonObject(with: Data(contentsOf: raw.appendingPathComponent("recording_session.json")))
        let recording = try #require(recordingObject as? [String: Any])
        #expect(recording["coordinate_frame_session_id"] as? String == "arkit-session-1")
        #expect(recording["world_frame_definition"] as? String == "arkit_world_origin_at_session_start")
        #expect(recording["units"] as? String == "meters")
        #expect(recording["handedness"] as? String == "right_handed")
        #expect(recording["gravity_aligned"] as? Bool == true)
        #expect((recording["session_reset_count"] as? NSNumber)?.intValue == 0)

        let depthManifestObject = try JSONSerialization.jsonObject(with: Data(contentsOf: raw.appendingPathComponent("arkit/depth_manifest.json")))
        let depthManifest = try #require(depthManifestObject as? [String: Any])
        let depthFrames = try #require(depthManifest["frames"] as? [[String: Any]])
        #expect(depthFrames.count == 1)

        let confidenceManifestObject = try JSONSerialization.jsonObject(with: Data(contentsOf: raw.appendingPathComponent("arkit/confidence_manifest.json")))
        let confidenceManifest = try #require(confidenceManifestObject as? [String: Any])
        let confidenceFrames = try #require(confidenceManifest["frames"] as? [[String: Any]])
        #expect(confidenceFrames.count == 1)
    }

    @Test
    func intakeResolutionUsesAuthoritativeIntakeBeforeAI() async throws {
        let service = IntakeResolutionService(inferenceService: FailingInferenceService())
        let request = CaptureUploadRequest(packageURL: URL(fileURLWithPath: "/tmp/fake"), metadata: CaptureUploadMetadata(
            id: UUID(),
            targetId: "job-1",
            reservationId: nil,
            jobId: "job-1",
            captureJobId: "job-1",
            buyerRequestId: nil,
            siteSubmissionId: "job-1",
            regionId: nil,
            creatorId: "tester",
            capturedAt: Date(),
            uploadedAt: nil,
            captureSource: .metaGlasses,
            specialTaskType: .curatedNearby,
            priorityWeight: 1.0,
            quotedPayoutCents: nil,
            rightsProfile: nil,
            requestedOutputs: ["qualification"],
            intakePacket: QualificationIntakePacket(workflowName: "Job flow", taskSteps: ["Walk"], zone: "Dock"),
            intakeMetadata: nil,
            taskHypothesis: nil,
            scaffoldingPacket: nil,
            captureModality: nil,
            evidenceTier: nil,
            captureContextHint: nil,
            sceneMemory: nil,
            captureRights: nil,
            siteIdentity: nil,
            captureTopology: nil,
            captureMode: nil
        ))

        let outcome = await service.resolve(request: request)
        switch outcome {
        case .resolved(let resolved):
            #expect(resolved.metadata.intakeMetadata?.source == .authoritative)
        case .needsManualEntry:
            Issue.record("Authoritative intake should not require manual entry")
        }
    }

    @Test
    func intakeResolutionShowsSpecificGeminiFailureReasonInManualFallback() async throws {
        let service = IntakeResolutionService(inferenceService: FailingInferenceService())
        let request = CaptureUploadRequest(packageURL: URL(fileURLWithPath: "/tmp/fake"), metadata: CaptureUploadMetadata(
            id: UUID(),
            targetId: "job-error",
            reservationId: nil,
            jobId: "job-error",
            captureJobId: "job-error",
            buyerRequestId: nil,
            siteSubmissionId: "job-error",
            regionId: nil,
            creatorId: "tester",
            capturedAt: Date(),
            uploadedAt: nil,
            captureSource: .iphoneVideo,
            specialTaskType: .curatedNearby,
            priorityWeight: 1.0,
            quotedPayoutCents: nil,
            rightsProfile: nil,
            requestedOutputs: ["qualification"],
            intakePacket: nil,
            intakeMetadata: nil,
            taskHypothesis: nil,
            scaffoldingPacket: nil,
            captureModality: nil,
            evidenceTier: nil,
            captureContextHint: "Test capture",
            sceneMemory: nil,
            captureRights: nil,
            siteIdentity: nil,
            captureTopology: nil,
            captureMode: nil
        ))

        let outcome = await service.resolve(request: request)
        switch outcome {
        case .resolved:
            Issue.record("Inference failure should require manual entry")
        case .needsManualEntry(_, let draft):
            #expect(draft.helperText.contains("Gemini API key is not configured"))
        }
    }

    @Test
    func intakeResolutionRequiresConfirmationForLowConfidenceAIHypothesis() async throws {
        let service = IntakeResolutionService(
            inferenceService: LowConfidenceInferenceService(),
            autoAcceptConfidenceThreshold: 0.8
        )
        let request = CaptureUploadRequest(packageURL: URL(fileURLWithPath: "/tmp/fake"), metadata: CaptureUploadMetadata(
            id: UUID(),
            targetId: "job-low",
            reservationId: nil,
            jobId: "job-low",
            captureJobId: "job-low",
            buyerRequestId: nil,
            siteSubmissionId: "job-low",
            regionId: nil,
            creatorId: "tester",
            capturedAt: Date(),
            uploadedAt: nil,
            captureSource: .iphoneVideo,
            specialTaskType: .curatedNearby,
            priorityWeight: 1.0,
            quotedPayoutCents: nil,
            rightsProfile: nil,
            requestedOutputs: ["qualification"],
            intakePacket: nil,
            intakeMetadata: nil,
            taskHypothesis: nil,
            scaffoldingPacket: nil,
            captureModality: nil,
            evidenceTier: nil,
            captureContextHint: "Packing area",
            sceneMemory: nil,
            captureRights: nil,
            siteIdentity: nil,
            captureTopology: nil,
            captureMode: nil
        ))

        let outcome = await service.resolve(request: request)
        switch outcome {
        case .resolved:
            Issue.record("Low-confidence AI hypothesis should require manual confirmation")
        case .needsManualEntry(let unresolved, let draft):
            #expect(unresolved.metadata.intakeMetadata?.source == .aiInferred)
            #expect(unresolved.metadata.taskHypothesis?.status == .needsConfirmation)
            #expect(draft.reviewTitle == "Review AI Task Guess")
            #expect(draft.helperText.contains("We think this task is"))
            #expect(draft.workflowName == "Walkthrough")
        }
    }

    @Test
    func captureFlowPromptsForManualIntakeInsteadOfSkippingResolution() async throws {
        let upload = MockCaptureUploadService()
        let viewModel = await MainActor.run {
            CaptureFlowViewModel(
                uploadService: upload,
                targetStateService: MockTargetStateService(),
                intakeResolutionService: ManualEntryResolutionService(),
                exportService: StubCaptureExportService()
            )
        }

        let baseDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("iphone-manual-intake-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)

        let artifacts = VideoCaptureManager.RecordingArtifacts(
            baseFilename: "test",
            directoryURL: baseDir,
            videoURL: baseDir.appendingPathComponent("walkthrough.mov"),
            motionLogURL: baseDir.appendingPathComponent("motion.jsonl"),
            manifestURL: baseDir.appendingPathComponent("manifest.json"),
            arKit: nil,
            packageURL: baseDir,
            startedAt: Date()
        )

        await MainActor.run {
            viewModel.handleRecordingFinished(artifacts: artifacts, targetId: "target-123", reservationId: nil)
            viewModel.startPendingCaptureUpload()
        }

        for _ in 0..<20 {
            let draft = await MainActor.run { viewModel.manualIntakeDraft }
            if draft != nil { break }
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        let draft = await MainActor.run { viewModel.manualIntakeDraft }
        #expect(draft?.reviewTitle == "Complete Intake")
        #expect(upload.enqueued.isEmpty)
    }

    @Test
    func captureFlowUsesSeedIntakeForApprovedPhoneCapture() async throws {
        let intake = QualificationIntakePacket(
            workflowName: "Approved launch target",
            taskSteps: ["Start at public entry", "Capture common circulation"],
            zone: "public common area",
            owner: "city-launch"
        )
        let rights = CaptureRightsMetadata(
            derivedSceneGenerationAllowed: true,
            dataLicensingAllowed: true,
            payoutEligible: true,
            consentStatus: .policyOnly,
            consentScope: ["public common area"],
            consentNotes: ["Backend-approved launch target scope."]
        )
        let seed = SpaceReviewSeed(
            title: "CCB Plaza",
            address: "201 Corcoran St, Durham, NC",
            payoutRange: 35...45,
            captureJobId: "city-launch-durham-nc-ccb-plaza",
            buyerRequestId: nil,
            siteSubmissionId: "durham-nc-ccb-plaza",
            regionId: "durham-nc",
            rightsProfile: "approved_launch_target",
            requestedOutputs: ["qualification", "preview_simulation", "deeper_evaluation"],
            suggestedContext: "public plaza common access",
            intakePacket: intake,
            captureRights: rights,
            requestedCaptureMode: "site_world_candidate"
        )
        let viewModel = await MainActor.run {
            CaptureFlowViewModel(
                flowMode: .spaceReview(seed: seed),
                uploadService: MockCaptureUploadService(),
                targetStateService: MockTargetStateService(),
                intakeResolutionService: StubIntakeResolutionService(outcome: nil),
                exportService: StubCaptureExportService()
            )
        }

        let baseDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("iphone-approved-intake-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)

        let artifacts = VideoCaptureManager.RecordingArtifacts(
            baseFilename: "test",
            directoryURL: baseDir,
            videoURL: baseDir.appendingPathComponent("walkthrough.mov"),
            motionLogURL: baseDir.appendingPathComponent("motion.jsonl"),
            manifestURL: baseDir.appendingPathComponent("manifest.json"),
            arKit: nil,
            packageURL: baseDir,
            startedAt: Date()
        )

        await MainActor.run {
            viewModel.handleRecordingFinished(artifacts: artifacts, targetId: nil, reservationId: nil)
        }

        let maybePending = await MainActor.run { viewModel.pendingCaptureRequest }
        let pending = try #require(maybePending)
        #expect(pending.metadata.intakePacket == intake)
        #expect(pending.metadata.intakeMetadata?.source == .authoritative)
        #expect(pending.metadata.taskHypothesis?.workflowName == "Approved launch target")
        #expect(pending.metadata.taskHypothesis?.status == .accepted)
        #expect(pending.metadata.captureRights == rights)
        #expect(pending.metadata.captureMode?.requestedMode == "site_world_candidate")
        #expect(pending.metadata.rightsProfile == "approved_launch_target")
        #expect(pending.metadata.specialTaskType == .curatedNearby)
    }

    @Test
    func openCaptureSeedStaysReviewGatedZeroPayoutAndQualificationOnly() async throws {
        let seed = SpaceReviewSeed(title: "Open capture review")
        let viewModel = await MainActor.run {
            CaptureFlowViewModel(
                flowMode: .spaceReview(seed: seed),
                uploadService: MockCaptureUploadService(),
                targetStateService: MockTargetStateService(),
                intakeResolutionService: StubIntakeResolutionService(outcome: nil),
                exportService: StubCaptureExportService()
            )
        }

        let baseDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("iphone-open-capture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)

        let artifacts = VideoCaptureManager.RecordingArtifacts(
            baseFilename: "test",
            directoryURL: baseDir,
            videoURL: baseDir.appendingPathComponent("walkthrough.mov"),
            motionLogURL: baseDir.appendingPathComponent("motion.jsonl"),
            manifestURL: baseDir.appendingPathComponent("manifest.json"),
            arKit: nil,
            packageURL: baseDir,
            startedAt: Date()
        )

        await MainActor.run {
            viewModel.handleRecordingFinished(artifacts: artifacts, targetId: nil, reservationId: nil)
        }

        let maybePending = await MainActor.run { viewModel.pendingCaptureRequest }
        let pending = try #require(maybePending)
        #expect(pending.metadata.quotedPayoutCents == nil)
        #expect(pending.metadata.requestedOutputs == ["qualification", "review_intake"])
        #expect(pending.metadata.captureRights?.payoutEligible == false)
        #expect(pending.metadata.captureRights?.derivedSceneGenerationAllowed == false)
        #expect(pending.metadata.captureMode?.requestedMode == "qualification_only")
        #expect(pending.metadata.rightsProfile == "review_required")
        #expect(pending.metadata.specialTaskType == .openCapture)
    }

    @Test
    func captureFlowRecordingFinishDoesNotAutoUpload() async throws {
        let upload = MockCaptureUploadService()
        let viewModel = await MainActor.run {
            CaptureFlowViewModel(
                uploadService: upload,
                targetStateService: MockTargetStateService(),
                intakeResolutionService: StubIntakeResolutionService(outcome: nil),
                exportService: StubCaptureExportService()
            )
        }

        let baseDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("iphone-artifacts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)

        let artifacts = VideoCaptureManager.RecordingArtifacts(
            baseFilename: "test",
            directoryURL: baseDir,
            videoURL: baseDir.appendingPathComponent("walkthrough.mov"),
            motionLogURL: baseDir.appendingPathComponent("motion.jsonl"),
            manifestURL: baseDir.appendingPathComponent("manifest.json"),
            arKit: nil,
            packageURL: baseDir,
            startedAt: Date()
        )

        await MainActor.run {
            viewModel.handleRecordingFinished(artifacts: artifacts, targetId: "target-123", reservationId: nil)
        }

        #expect(upload.enqueued.isEmpty)
        let pendingRequest = await MainActor.run { viewModel.pendingCaptureRequest }
        #expect(pendingRequest?.metadata.targetId == "target-123")
    }

    @Test
    func captureFlowAddsSiteWorldWorkflowMetadataToPendingRequest() async throws {
        let viewModel = await MainActor.run {
            CaptureFlowViewModel(
                uploadService: MockCaptureUploadService(),
                targetStateService: MockTargetStateService(),
                intakeResolutionService: StubIntakeResolutionService(outcome: nil),
                exportService: StubCaptureExportService()
            )
        }

        let baseDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("site-world-artifacts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)

        let artifacts = VideoCaptureManager.RecordingArtifacts(
            baseFilename: "test",
            directoryURL: baseDir,
            videoURL: baseDir.appendingPathComponent("walkthrough.mov"),
            motionLogURL: baseDir.appendingPathComponent("motion.jsonl"),
            manifestURL: baseDir.appendingPathComponent("manifest.json"),
            arKit: nil,
            packageURL: baseDir,
            startedAt: Date()
        )

        await MainActor.run {
            viewModel.siteWorldSiteScale = .multiZone
            viewModel.setCriticalZone(.restrictedBoundary, enabled: true)
            viewModel.handleRecordingFinished(artifacts: artifacts, targetId: "target-123", reservationId: nil)
        }

        let pendingRequest = await MainActor.run { viewModel.pendingCaptureRequest }
        let review = await MainActor.run { viewModel.pendingSiteWorldPassReview }
        let scaffolding = pendingRequest?.metadata.scaffoldingPacket?.scaffoldingUsed ?? []
        let coveragePlan = pendingRequest?.metadata.scaffoldingPacket?.coveragePlan ?? []

        #expect(scaffolding.contains("site_world_candidate"))
        #expect(scaffolding.contains("hub_return_plan"))
        #expect(scaffolding.contains("critical_zone_revisits"))
        #expect(coveragePlan.contains(where: { $0.contains("hub") || $0.contains("Hub") }))
        #expect(review?.nextActionLabel == "Retake primary route")
        #expect(review?.missingItems.contains(where: { $0.contains("Entrance localization hold") }) == true)
        #expect(pendingRequest?.metadata.sceneMemory?.continuityScore == review.map { Double($0.score) / 100.0 })
    }

    @Test
    func finalizerDowngradesSiteWorldCandidateWithSpecificMissingIntakeReason() throws {
        let fileManager = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("site-world-missing-intake-\(UUID().uuidString)", isDirectory: true)
        let raw = root.appendingPathComponent("raw-source", isDirectory: true)
        let arkit = raw.appendingPathComponent("arkit", isDirectory: true)
        try fileManager.createDirectory(at: arkit.appendingPathComponent("depth", isDirectory: true), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: arkit.appendingPathComponent("confidence", isDirectory: true), withIntermediateDirectories: true)

        try Data("video".utf8).write(to: raw.appendingPathComponent("walkthrough.mov"))
        try makeRawManifestData(
            sceneId: "site-world",
            captureId: "capture-missing-intake",
            videoUri: "raw/walkthrough.mov",
            captureProfileId: "iphone_arkit_lidar",
            captureCapabilities: [
                "camera_pose": true,
                "depth": true,
                "motion": true
            ]
        ).write(to: raw.appendingPathComponent("manifest.json"))
        try Data("{\"fx\":1200,\"fy\":1195,\"cx\":640,\"cy\":360,\"width\":1280,\"height\":720}".utf8)
            .write(to: arkit.appendingPathComponent("intrinsics.json"))
        try Data("{\"frame_id\":\"000001\",\"t_device_sec\":0.0,\"T_world_camera\":[[1,0,0,0],[0,1,0,0],[0,0,1,0],[0,0,0,1]]}\n".utf8)
            .write(to: arkit.appendingPathComponent("poses.jsonl"))
        try Data("{\"frame_id\":\"000001\",\"t_device_sec\":0.0,\"trackingState\":\"normal\"}\n".utf8)
            .write(to: arkit.appendingPathComponent("frames.jsonl"))
        try Data([0x01]).write(to: arkit.appendingPathComponent("depth/000001.png"))
        try Data([0x01]).write(to: arkit.appendingPathComponent("confidence/000001.png"))
        try Data("{\"timestamp\":1.0,\"t_capture_sec\":0.1,\"motion_provenance\":\"iphone_device_imu\"}\n".utf8)
            .write(to: raw.appendingPathComponent("motion.jsonl"))

        let metadata = CaptureUploadMetadata(
            id: UUID(),
            targetId: "site-world",
            reservationId: nil,
            jobId: "site-world",
            captureJobId: "site-world",
            buyerRequestId: nil,
            siteSubmissionId: "site-world",
            regionId: nil,
            creatorId: "tester",
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            uploadedAt: nil,
            captureSource: .iphoneVideo,
            specialTaskType: .curatedNearby,
            priorityWeight: 1.0,
            quotedPayoutCents: nil,
            rightsProfile: "approved_launch_target",
            requestedOutputs: ["qualification", "preview_simulation"],
            intakePacket: nil,
            intakeMetadata: nil,
            taskHypothesis: nil,
            scaffoldingPacket: nil,
            captureModality: nil,
            evidenceTier: nil,
            captureContextHint: nil,
            sceneMemory: nil,
            captureRights: CaptureRightsMetadata(derivedSceneGenerationAllowed: true),
            siteIdentity: nil,
            captureTopology: nil,
            captureMode: CaptureModeMetadata(
                requestedMode: "site_world_candidate",
                resolvedMode: "site_world_candidate",
                downgradeReason: nil
            )
        )

        let request = CaptureUploadRequest(packageURL: raw, metadata: metadata)
        let finalizer = CaptureBundleFinalizer()
        _ = try finalizer.finalize(request: request, mode: .localExport())

        let modeObject = try JSONSerialization.jsonObject(with: Data(contentsOf: raw.appendingPathComponent("capture_mode.json")))
        let captureMode = try #require(modeObject as? [String: Any])
        #expect(captureMode["requested_mode"] as? String == "site_world_candidate")
        #expect(captureMode["resolved_mode"] as? String == "qualification_only")
        #expect(captureMode["downgrade_reason"] as? String == "missing_complete_intake")

        let hypothesisObject = try JSONSerialization.jsonObject(with: Data(contentsOf: raw.appendingPathComponent("task_hypothesis.json")))
        let hypothesis = try #require(hypothesisObject as? [String: Any])
        #expect(hypothesis["source"] as? String == "ai_inferred")
        #expect(hypothesis["status"] as? String == "needs_confirmation")
        #expect((hypothesis["warnings"] as? [String])?.contains("missing_complete_intake") == true)
    }

    @Test
    func resetSiteWorldWorkflowSessionRestoresDefaultPlan() async throws {
        let viewModel = await MainActor.run {
            CaptureFlowViewModel(
                uploadService: MockCaptureUploadService(),
                targetStateService: MockTargetStateService(),
                intakeResolutionService: StubIntakeResolutionService(outcome: nil),
                exportService: StubCaptureExportService()
            )
        }

        await MainActor.run {
            viewModel.siteWorldSiteScale = .multiZone
            viewModel.configureSiteWorldWorkflow()
            viewModel.setCriticalZone(.handoffPoint, enabled: true)
            viewModel.resetSiteWorldWorkflowSession()
        }

        let currentRole = await MainActor.run { viewModel.currentPlannedPassRole }
        let scale = await MainActor.run { viewModel.siteWorldSiteScale }
        let configured = await MainActor.run { viewModel.siteWorldWorkflowConfigured }
        let criticalZones = await MainActor.run { viewModel.selectedCriticalZoneAnchors }

        #expect(currentRole == "primary")
        #expect(scale == .medium)
        #expect(configured == false)
        #expect(criticalZones.isEmpty)
    }

    @Test
    func inferenceFallsBackToPreviewModelAndRetriesHigherFPS() async throws {
        let session = URLSession(configuration: {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [InferenceURLProtocol.self]
            return config
        }())

        InferenceURLProtocol.reset()
        InferenceURLProtocol.handler = { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }
            if url.absoluteString.contains("/upload/v1beta/files") {
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["X-Goog-Upload-URL": "https://upload.example/mock"])!
                return (response, Data())
            }
            if url.host == "upload.example" {
                let data = """
                {"file":{"name":"files/mock-video","uri":"https://files.example/mock-video","mimeType":"video/quicktime","state":"ACTIVE"}}
                """.data(using: .utf8)!
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, data)
            }
            if url.absoluteString.contains("gemini-3.1-flash-lite-preview") {
                let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
                return (response, Data("model not found".utf8))
            }
            if url.absoluteString.contains("gemini-3-flash-preview") {
                let body = String(data: request.bodyData ?? Data(), encoding: .utf8) ?? ""
                InferenceURLProtocol.capturedBodies.append(body)
                let isFirstAttempt = InferenceURLProtocol.capturedBodies.count == 1
                let json = isFirstAttempt
                    ? #"{"workflowName":"Walkthrough","taskSteps":["Step one"],"warnings":["Need zone"],"confidence":0.42}"#
                    : #"{"workflowName":"Walkthrough","taskSteps":["Step one","Step two"],"zone":"Packing","confidence":0.82}"#
                let responsePayload = try JSONSerialization.data(withJSONObject: [
                    "candidates": [
                        [
                            "content": [
                                "parts": [
                                    ["text": json]
                                ]
                            ]
                        ]
                    ]
                ])
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, responsePayload)
            }
            throw URLError(.badServerResponse)
        }

        let videoDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("inference-video-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: videoDir, withIntermediateDirectories: true)
        try Data("video".utf8).write(to: videoDir.appendingPathComponent("walkthrough.mov"))

        let request = CaptureUploadRequest(packageURL: videoDir, metadata: CaptureUploadMetadata(
            id: UUID(),
            targetId: nil,
            reservationId: nil,
            jobId: "job-fallback",
            captureJobId: "job-fallback",
            buyerRequestId: nil,
            siteSubmissionId: "job-fallback",
            regionId: nil,
            creatorId: "tester",
            capturedAt: Date(),
            uploadedAt: nil,
            captureSource: .iphoneVideo,
            specialTaskType: .operatorApproved,
            priorityWeight: 1.0,
            quotedPayoutCents: nil,
            rightsProfile: nil,
            requestedOutputs: ["qualification"],
            intakePacket: nil,
            intakeMetadata: nil,
            taskHypothesis: nil,
            scaffoldingPacket: nil,
            captureModality: nil,
            evidenceTier: nil,
            captureContextHint: "Packing area",
            sceneMemory: nil,
            captureRights: nil,
            siteIdentity: nil,
            captureTopology: nil,
            captureMode: nil
        ))

        let service = CaptureIntakeInferenceService(
            session: session,
            runtimeConfigProvider: {
                RuntimeConfig(
                    backendBaseURL: nil,
                    demandBackendBaseURL: nil,
                    isUITesting: false,
                    uiTestScenario: .disabled,
                    allowOffsiteCheckIn: false,
                    maxReservationDriveMinutes: 60,
                    fallbackMaxReservationAirMiles: 35.0,
                    enableNearbyDiscovery: true,
                    nearbyDiscoveryProvider: .placesNearby,
                    enableGeminiMapsGroundingFallback: false,
                    enableDirectProviderFeatures: true,
                    allowMockJobsFallback: false,
                    enableRemoteNotifications: false
                )
            },
            apiKeyProvider: { "test-key" }
        )
        let result = try await service.inferIntake(for: request)

        #expect(result.metadata.model == "gemini-3-flash-preview")
        #expect(result.metadata.fps == 5)
        #expect(result.intakePacket.zone == "Packing")
        #expect(InferenceURLProtocol.capturedBodies.contains(where: { $0.contains("\"fps\":3") }))
        #expect(InferenceURLProtocol.capturedBodies.contains(where: { $0.contains("\"fps\":5") }))
        #expect(InferenceURLProtocol.capturedBodies.contains(where: { $0.contains("responseSchema") }))
    }

    @Test
    func validateRawBundleFailsForIncompleteBundle() throws {
        let fileManager = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("incomplete-bundle-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        // Only write a partial manifest — no walkthrough, no sidecars
        try Data("{\"scene_id\":\"\",\"video_uri\":\"\"}".utf8).write(to: root.appendingPathComponent("manifest.json"))

        let finalizer = CaptureBundleFinalizer()
        let reasons = finalizer.validateRawBundle(in: root)

        #expect(reasons.contains("missing_walkthrough_video"))
        #expect(reasons.contains("missing_rights_consent"))
        #expect(reasons.contains("missing_capture_start_epoch_ms"))
    }

    @Test
    func validateRawBundleAcceptsCompleteBundle() throws {
        let fileManager = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("complete-bundle-\(UUID().uuidString)", isDirectory: true)
        let arkitDir = root.appendingPathComponent("arkit", isDirectory: true)
        try fileManager.createDirectory(at: arkitDir, withIntermediateDirectories: true)

        try Data("video-content".utf8).write(to: root.appendingPathComponent("walkthrough.mov"))
        let manifest: [String: Any] = [
            "schema_version": "v3",
            "scene_id": "scene-valid",
            "capture_id": "cap-valid",
            "video_uri": "raw/walkthrough.mov",
            "capture_start_epoch_ms": 1_700_000_000,
            "fps_source": 30.0,
            "width": 1920,
            "height": 1080
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(to: root.appendingPathComponent("manifest.json"))

        // Write all required sidecars (empty objects)
        let sidecars = ["rights_consent.json", "provenance.json", "capture_context.json",
                        "intake_packet.json", "task_hypothesis.json", "recording_session.json",
                        "capture_topology.json", "route_anchors.json", "checkpoint_events.json",
                        "relocalization_events.json", "overlap_graph.json", "video_track.json",
                        "hashes.json", "sync_map.jsonl", "motion.jsonl", "semantic_anchor_observations.jsonl"]
        for sidecar in sidecars {
            try Data("{}".utf8).write(to: root.appendingPathComponent(sidecar))
        }

        let finalizer = CaptureBundleFinalizer()
        let reasons = finalizer.validateRawBundle(in: root)
        #expect(reasons.isEmpty, "Complete bundle should pass raw validation")
    }

    @Test
    func validateRawBundleAcceptsMP4FallbackVideo() throws {
        let fileManager = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mp4-bundle-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        // .mp4 video instead of .mov
        try Data("mp4-video-content".utf8).write(to: root.appendingPathComponent("walkthrough.mp4"))
        let manifest: [String: Any] = [
            "schema_version": "v3",
            "scene_id": "scene-mp4",
            "capture_id": "cap-mp4",
            "video_uri": "walkthrough.mp4",
            "capture_start_epoch_ms": 1_700_000_000,
            "fps_source": 30.0,
            "width": 1920,
            "height": 1080
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(to: root.appendingPathComponent("manifest.json"))

        // Required sidecars
        let sidecars = ["rights_consent.json", "provenance.json", "capture_context.json",
                        "intake_packet.json", "task_hypothesis.json", "recording_session.json",
                        "capture_topology.json", "route_anchors.json", "checkpoint_events.json",
                        "relocalization_events.json", "overlap_graph.json", "video_track.json",
                        "hashes.json", "sync_map.jsonl", "motion.jsonl", "semantic_anchor_observations.jsonl"]
        for sidecar in sidecars {
            try Data("{}".utf8).write(to: root.appendingPathComponent(sidecar))
        }

        let finalizer = CaptureBundleFinalizer()
        let reasons = finalizer.validateRawBundle(in: root)
        #expect(reasons.isEmpty, "Bundle with .mp4 video should pass raw validation")
    }

    @Test
    func validateRawBundleFailsWhenNeitherMovNorMP4Present() throws {
        let fileManager = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("no-video-bundle-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        // No walkthrough.mov or walkthrough.mp4 — only an unrelated file
        try Data("not-a-video".utf8).write(to: root.appendingPathComponent("other.mp4"))
        try Data("{}".utf8).write(to: root.appendingPathComponent("manifest.json"))

        let finalizer = CaptureBundleFinalizer()
        let reasons = finalizer.validateRawBundle(in: root)
        #expect(reasons.contains("missing_walkthrough_video"))
    }
}

private struct FailingInferenceService: CaptureIntakeInferenceServiceProtocol {
    func inferIntake(for request: CaptureUploadRequest) async throws -> CaptureIntakeInferenceResult {
        throw CaptureIntakeInferenceService.ServiceError.missingAPIKey
    }
}

private struct LowConfidenceInferenceService: CaptureIntakeInferenceServiceProtocol {
    func inferIntake(for request: CaptureUploadRequest) async throws -> CaptureIntakeInferenceResult {
        let packet = QualificationIntakePacket(
            workflowName: "Walkthrough",
            taskSteps: ["Step one", "Step two"],
            zone: "Packing"
        )
        let metadata = CaptureIntakeMetadata(
            source: .aiInferred,
            model: "gemini-3-flash-preview",
            fps: 3,
            confidence: 0.62,
            warnings: ["Task is generic and should be confirmed."]
        )
        return CaptureIntakeInferenceResult(
            intakePacket: packet,
            metadata: metadata,
            taskHypothesis: CaptureTaskHypothesis(packet: packet, metadata: metadata, status: .accepted)
        )
    }
}

private struct StubCaptureExportService: CaptureExportServiceProtocol {
    func exportCapture(request: CaptureUploadRequest) async throws -> FinalizedCaptureBundle {
        FinalizedCaptureBundle(
            sceneId: "scene",
            captureId: "capture",
            rawDirectoryURL: request.packageURL,
            captureRootURL: request.packageURL,
            shareURL: request.packageURL
        )
    }
}

private struct StubIntakeResolutionService: IntakeResolutionServiceProtocol {
    let outcome: IntakeResolutionOutcome?

    func resolve(request: CaptureUploadRequest) async -> IntakeResolutionOutcome {
        outcome ?? .resolved(request)
    }
}

private struct ManualEntryResolutionService: IntakeResolutionServiceProtocol {
    func resolve(request: CaptureUploadRequest) async -> IntakeResolutionOutcome {
        .needsManualEntry(
            request: request,
            draft: CaptureManualIntakeDraft(
                helperText: "No complete authoritative intake was available for this capture."
            )
        )
    }
}

private final class InferenceURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    static var capturedBodies: [String] = []

    static func reset() {
        handler = nil
        capturedBodies = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private extension URLRequest {
    var bodyData: Data? {
        if let httpBody {
            return httpBody
        }
        guard let stream = httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }

        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        var data = Data()
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 {
                break
            }
            data.append(buffer, count: read)
        }
        return data
    }
}

// MARK: - Video Resolution Support Tests

extension CaptureBundleAndInferenceTests {

    /// Verify that a bundle using `.mp4` instead of `.mov` passes validation and
    /// patching. The manifest `video_uri` and `video_track.json` should reference
    /// the actual on-disk `.mp4` file, not a hardcoded `.mov` path.
    @Test
    func finalizerSupportsMp4VideoFallback() throws {
        let fileManager = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("capture-mp4-fallback-\(UUID().uuidString)", isDirectory: true)
        let raw = root.appendingPathComponent("raw-source", isDirectory: true)
        try fileManager.createDirectory(at: raw, withIntermediateDirectories: true)

        // Use walkthrough.mp4 instead of walkthrough.mov
        try Data("video".utf8).write(to: raw.appendingPathComponent("walkthrough.mp4"))
        try makeRawManifestData(
            sceneId: "mp4-scene",
            captureId: "capture-mp4",
            videoUri: "raw/walkthrough.mov",
            captureProfileId: "iphone_arkit_non_lidar",
            captureCapabilities: [
                "camera_pose": false,
                "depth": false,
                "motion": false
            ]
        ).write(to: raw.appendingPathComponent("manifest.json"))
        try Data("{\"rights_consent_given\":true,\"version\":\"v3\"}".utf8).write(to: raw.appendingPathComponent("rights_consent.json"))
        try Data("".utf8).write(to: raw.appendingPathComponent("motion.jsonl"))

        let metadata = CaptureUploadMetadata(
            id: UUID(),
            targetId: "mp4-scene",
            reservationId: nil,
            jobId: "mp4-scene",
            captureJobId: "mp4-scene",
            buyerRequestId: nil,
            siteSubmissionId: "mp4-scene",
            regionId: nil,
            creatorId: "tester",
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            uploadedAt: nil,
            captureSource: .iphoneVideo,
            specialTaskType: .curatedNearby,
            priorityWeight: 1.0,
            quotedPayoutCents: nil,
            rightsProfile: nil,
            requestedOutputs: ["qualification"],
            intakePacket: QualificationIntakePacket(workflowName: "MP4 walk"),
            intakeMetadata: nil,
            taskHypothesis: nil,
            scaffoldingPacket: nil,
            captureModality: nil,
            evidenceTier: nil,
            captureContextHint: nil,
            sceneMemory: nil,
            captureRights: nil,
            siteIdentity: nil,
            captureTopology: nil,
            captureMode: nil
        )
        let request = CaptureUploadRequest(packageURL: raw, metadata: metadata)

        let finalizer = CaptureBundleFinalizer()
        // The default mode uses .mov, but the finalizer should auto-detect .mp4
        _ = try finalizer.finalize(request: request, mode: .localExport())

        let manifestObject = try JSONSerialization.jsonObject(with: Data(contentsOf: raw.appendingPathComponent("manifest.json")))
        let manifest = try #require(manifestObject as? [String: Any])

        // The video_uri must reference the .mp4 file, not .mov
        #expect(manifest["video_uri"] as? String == "raw/walkthrough.mp4")
        #expect(manifest["scene_id"] as? String == "mp4-scene")

        // Both .mov and .mp4 paths should not coexist — only .mp4 should be on disk
        let movURL = raw.appendingPathComponent("walkthrough.mov")
        let mp4URL = raw.appendingPathComponent("walkthrough.mp4")
        #expect(!fileManager.fileExists(atPath: movURL.path))
        #expect(fileManager.fileExists(atPath: mp4URL.path))
    }
}
