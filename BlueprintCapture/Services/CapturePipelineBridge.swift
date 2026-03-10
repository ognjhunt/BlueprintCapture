import AVFoundation
import Foundation
import UIKit

protocol CapturePipelineBridgeProtocol {
    func stageArtifacts(
        for context: TaskCaptureContext,
        recording artifacts: VideoCaptureManager.RecordingArtifacts,
        requestedLanesOverride: [String]?
    ) throws -> CapturePipelineBridge.Output
}

final class CapturePipelineBridge: CapturePipelineBridgeProtocol {
    struct Output: Equatable {
        let sceneId: String
        let captureId: String
        let descriptorURI: String
        let qaReportURI: String
        let rawManifestURI: String
        let framesIndexURI: String
        let artifacts: [CaptureUploadArtifact]
    }

    private struct ARFrameSample: Decodable {
        let frameIndex: Int
        let timestamp: TimeInterval
        let capturedAt: Date
        let cameraTransform: [Double]
        let intrinsics: [Double]
        let imageResolution: [Int]
        let sceneDepthFile: String?
        let smoothedSceneDepthFile: String?
        let confidenceFile: String?
    }

    enum BridgeError: LocalizedError {
        case missingStorageBucket
        case missingCaptureManifest
        case invalidCaptureManifest
        case missingVideoTrack
        case keyframeExtractionFailed
        case qaPreflightFailed

        var errorDescription: String? {
            switch self {
            case .missingStorageBucket:
                return "The Firebase storage bucket is not configured."
            case .missingCaptureManifest:
                return "The capture package manifest could not be found."
            case .invalidCaptureManifest:
                return "The capture package manifest could not be decoded."
            case .missingVideoTrack:
                return "The recorded video does not contain a video track."
            case .keyframeExtractionFailed:
                return "The bridge could not extract a representative keyframe."
            case .qaPreflightFailed:
                return "The bridge could not produce a passing QA report."
            }
        }
    }

    private let bucketProvider: () -> String?
    private let nowProvider: () -> Date
    private let requestedLanesDefault: [String]

    init(
        bucketProvider: @escaping () -> String? = { AppConfig.storageBucket() },
        nowProvider: @escaping () -> Date = { Date() },
        requestedLanesDefault: [String] = ["qualification"]
    ) {
        self.bucketProvider = bucketProvider
        self.nowProvider = nowProvider
        self.requestedLanesDefault = requestedLanesDefault
    }

    func stageArtifacts(
        for context: TaskCaptureContext,
        recording artifacts: VideoCaptureManager.RecordingArtifacts,
        requestedLanesOverride: [String]? = nil
    ) throws -> Output {
        guard let bucket = bucketProvider()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !bucket.isEmpty else {
            throw BridgeError.missingStorageBucket
        }

        guard FileManager.default.fileExists(atPath: artifacts.manifestURL.path) else {
            throw BridgeError.missingCaptureManifest
        }

        let manifest = try decodeCaptureManifest(from: artifacts.manifestURL)
        let sceneId = context.siteId
        let captureId = context.capturePass.capturePassId
        let requestedLanes = normalizeRequestedLanes(requestedLanesOverride ?? requestedLanesDefault)
        let capturePrefix = "scenes/\(sceneId)/captures/\(captureId)"
        let rawPrefix = "scenes/\(sceneId)/iphone/\(captureId)/raw"
        let imagePath = "scenes/\(sceneId)/images/\(captureId)_keyframe.jpg"
        let descriptorPath = "\(capturePrefix)/capture_descriptor.json"
        let qaPath = "\(capturePrefix)/qa_report.json"
        let framesIndexPath = "\(capturePrefix)/frames/index.jsonl"

        let stageDirectory = artifacts.directoryURL.appendingPathComponent("pipeline-bridge", isDirectory: true)
        try prepareStageDirectory(stageDirectory)

        let videoDetails = try inspectVideo(at: artifacts.videoURL, fallback: manifest.technicalCapture.cameraIntrinsics)
        let environmentHint = inferEnvironmentTypeHint(from: context)
        let keyframeLocalURL = stageDirectory.appendingPathComponent("\(captureId)_keyframe.jpg")
        try extractKeyframe(from: artifacts.videoURL, durationSeconds: videoDetails.durationSeconds, to: keyframeLocalURL)

        let rawVideoURI = gsURI(bucket: bucket, path: "\(rawPrefix)/video.mov")
        let keyframeURI = gsURI(bucket: bucket, path: imagePath)
        let descriptorURI = gsURI(bucket: bucket, path: descriptorPath)
        let qaReportURI = gsURI(bucket: bucket, path: qaPath)
        let rawManifestURI = gsURI(bucket: bucket, path: "\(rawPrefix)/manifest.json")
        let framesIndexURI = gsURI(bucket: bucket, path: framesIndexPath)

        let arFrameSamples = try loadARFrameSamples(from: artifacts.arKit?.frameLogURL)
        let hasARPoses = !arFrameSamples.isEmpty

        let posesLocalURL = stageDirectory.appendingPathComponent("poses.jsonl")
        let intrinsicsLocalURL = stageDirectory.appendingPathComponent("intrinsics.json")
        let framesIndexLocalURL = stageDirectory.appendingPathComponent("frames-index.jsonl")
        let rawManifestLocalURL = stageDirectory.appendingPathComponent("manifest.json")
        let qaLocalURL = stageDirectory.appendingPathComponent("qa_report.json")
        let descriptorLocalURL = stageDirectory.appendingPathComponent("capture_descriptor.json")

        var artifactsToUpload: [CaptureUploadArtifact] = [
            .legacyPackage(
                localFileURL: artifacts.packageURL,
                storagePath: CaptureUploadService.storagePath(
                    forLegacyPackageAt: artifacts.packageURL,
                    metadata: buildMetadata(for: context, capturedAt: artifacts.startedAt)
                )
            )
        ]

        let capturePackageManifestPath = "\(rawPrefix)/capture_package_manifest.json"
        artifactsToUpload.append(
            CaptureUploadArtifact(
                localFileURL: artifacts.manifestURL,
                storagePath: capturePackageManifestPath,
                contentType: "application/json",
                role: .capturePackageManifest,
                required: true
            )
        )
        artifactsToUpload.append(
            CaptureUploadArtifact(
                localFileURL: artifacts.videoURL,
                storagePath: "\(rawPrefix)/video.mov",
                contentType: "video/quicktime",
                role: .rawVideo,
                required: true
            )
        )
        artifactsToUpload.append(
            CaptureUploadArtifact(
                localFileURL: artifacts.motionLogURL,
                storagePath: "\(rawPrefix)/motion.jsonl",
                contentType: "application/x-ndjson",
                role: .motionLog,
                required: true
            )
        )

        if let arKit = artifacts.arKit {
            artifactsToUpload.append(
                CaptureUploadArtifact(
                    localFileURL: arKit.frameLogURL,
                    storagePath: "\(rawPrefix)/arkit/frames.jsonl",
                    contentType: "application/x-ndjson",
                    role: .arKitFrameLog,
                    required: false
                )
            )
        }

        let depthFiles = enumerateFiles(in: artifacts.arKit?.depthDirectoryURL)
        let confidenceFiles = enumerateFiles(in: artifacts.arKit?.confidenceDirectoryURL)
        let meshFiles = enumerateFiles(in: artifacts.arKit?.meshDirectoryURL)

        let arkitPosesURI: String?
        let arkitIntrinsicsURI: String?
        let arkitDepthPrefixURI: String?
        let arkitConfidencePrefixURI: String?

        if hasARPoses {
            try writeJSONLines(buildARPoseLines(sceneId: sceneId, captureId: captureId, samples: arFrameSamples), to: posesLocalURL)
            try writeJSONObject(buildIntrinsicsPayload(sceneId: sceneId, captureId: captureId, manifest: manifest, samples: arFrameSamples), to: intrinsicsLocalURL)
            artifactsToUpload.append(
                CaptureUploadArtifact(
                    localFileURL: posesLocalURL,
                    storagePath: "\(rawPrefix)/arkit/poses.jsonl",
                    contentType: "application/x-ndjson",
                    role: .arKitPoses,
                    required: false
                )
            )
            artifactsToUpload.append(
                CaptureUploadArtifact(
                    localFileURL: intrinsicsLocalURL,
                    storagePath: "\(rawPrefix)/arkit/intrinsics.json",
                    contentType: "application/json",
                    role: .arKitIntrinsics,
                    required: false
                )
            )
            arkitPosesURI = gsURI(bucket: bucket, path: "\(rawPrefix)/arkit/poses.jsonl")
            arkitIntrinsicsURI = gsURI(bucket: bucket, path: "\(rawPrefix)/arkit/intrinsics.json")
        } else {
            arkitPosesURI = nil
            arkitIntrinsicsURI = nil
        }

        if depthFiles.isEmpty {
            arkitDepthPrefixURI = nil
        } else {
            arkitDepthPrefixURI = gsURI(bucket: bucket, path: "\(rawPrefix)/arkit/depth")
            artifactsToUpload.append(contentsOf: uploadArtifacts(for: depthFiles, rootDirectory: artifacts.arKit?.depthDirectoryURL, remotePrefix: "\(rawPrefix)/arkit/depth", role: .arKitDepth))
        }

        if confidenceFiles.isEmpty {
            arkitConfidencePrefixURI = nil
        } else {
            arkitConfidencePrefixURI = gsURI(bucket: bucket, path: "\(rawPrefix)/arkit/confidence")
            artifactsToUpload.append(contentsOf: uploadArtifacts(for: confidenceFiles, rootDirectory: artifacts.arKit?.confidenceDirectoryURL, remotePrefix: "\(rawPrefix)/arkit/confidence", role: .arKitConfidence))
        }

        if !meshFiles.isEmpty {
            artifactsToUpload.append(contentsOf: uploadArtifacts(for: meshFiles, rootDirectory: artifacts.arKit?.meshDirectoryURL, remotePrefix: "\(rawPrefix)/arkit/meshes", role: .arKitMesh))
        }

        try writeJSONObject(
            buildRawManifest(
                sceneId: sceneId,
                rawVideoURI: rawVideoURI,
                manifest: manifest,
                environmentHint: environmentHint,
                videoDetails: videoDetails,
                hasLidar: artifacts.arKit != nil
            ),
            to: rawManifestLocalURL
        )
        artifactsToUpload.append(
            CaptureUploadArtifact(
                localFileURL: rawManifestLocalURL,
                storagePath: "\(rawPrefix)/manifest.json",
                contentType: "application/json",
                role: .rawManifest,
                required: true
            )
        )

        try writeJSONLines(
            buildFramesIndexLines(
                sceneId: sceneId,
                captureId: captureId,
                rawVideoURI: rawVideoURI,
                keyframeURI: keyframeURI,
                arFrameSamples: arFrameSamples,
                startedAt: manifest.captureStartedAt,
                durationSeconds: videoDetails.durationSeconds
            ),
            to: framesIndexLocalURL
        )
        artifactsToUpload.append(
            CaptureUploadArtifact(
                localFileURL: keyframeLocalURL,
                storagePath: imagePath,
                contentType: "image/jpeg",
                role: .keyframe,
                required: true
            )
        )
        artifactsToUpload.append(
            CaptureUploadArtifact(
                localFileURL: framesIndexLocalURL,
                storagePath: framesIndexPath,
                contentType: "application/x-ndjson",
                role: .framesIndex,
                required: true
            )
        )

        let preflightChecks = buildPreflightChecks(
            rawManifestExists: true,
            rawVideoExists: true,
            framesIndexExists: true,
            keyframeExists: true,
            arkitPosesExists: hasARPoses
        )
        let qaStatus = preflightChecks.allSatisfy { $0.passed } ? "passed" : "failed"
        guard qaStatus == "passed" else {
            throw BridgeError.qaPreflightFailed
        }

        try writeJSONObject(
            buildQAReport(
                sceneId: sceneId,
                captureId: captureId,
                status: qaStatus,
                requestedLanes: requestedLanes,
                checks: preflightChecks
            ),
            to: qaLocalURL
        )
        artifactsToUpload.append(
            CaptureUploadArtifact(
                localFileURL: qaLocalURL,
                storagePath: qaPath,
                contentType: "application/json",
                role: .qaReport,
                required: true
            )
        )

        try writeJSONObject(
            buildDescriptor(
                sceneId: sceneId,
                captureId: captureId,
                rawPrefixURI: gsURI(bucket: bucket, path: rawPrefix),
                framesIndexURI: framesIndexURI,
                rawVideoURI: rawVideoURI,
                keyframeURI: keyframeURI,
                qaReportURI: qaReportURI,
                qaStatus: qaStatus,
                requestedLanes: requestedLanes,
                environmentHint: environmentHint,
                nurecMode: hasARPoses ? "mono_pose_assisted" : "mono_slam",
                quality: buildQualitySummary(manifest: manifest, durationSeconds: videoDetails.durationSeconds, arFrameCount: arFrameSamples.count),
                context: context,
                arkitPosesURI: arkitPosesURI,
                arkitIntrinsicsURI: arkitIntrinsicsURI,
                arkitDepthPrefixURI: arkitDepthPrefixURI,
                arkitConfidencePrefixURI: arkitConfidencePrefixURI
            ),
            to: descriptorLocalURL
        )
        artifactsToUpload.append(
            CaptureUploadArtifact(
                localFileURL: descriptorLocalURL,
                storagePath: descriptorPath,
                contentType: "application/json",
                role: .captureDescriptor,
                required: true
            )
        )

        return Output(
            sceneId: sceneId,
            captureId: captureId,
            descriptorURI: descriptorURI,
            qaReportURI: qaReportURI,
            rawManifestURI: rawManifestURI,
            framesIndexURI: framesIndexURI,
            artifacts: artifactsToUpload
        )
    }
}

private extension CapturePipelineBridge {
    struct VideoDetails {
        let width: Int
        let height: Int
        let fps: Double
        let durationSeconds: Double
    }

    struct PreflightCheck {
        let name: String
        let passed: Bool
        let detail: String

        var asDictionary: [String: Any] {
            [
                "name": name,
                "passed": passed,
                "detail": detail
            ]
        }
    }

    func decodeCaptureManifest(from url: URL) throws -> VideoCaptureManager.CaptureManifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(VideoCaptureManager.CaptureManifest.self, from: Data(contentsOf: url))
        } catch {
            throw BridgeError.invalidCaptureManifest
        }
    }

    func prepareStageDirectory(_ url: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func inspectVideo(at url: URL, fallback: VideoCaptureManager.CaptureManifest.CameraIntrinsics) throws -> VideoDetails {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else {
            throw BridgeError.missingVideoTrack
        }

        let naturalSize = track.naturalSize.applying(track.preferredTransform)
        let width = max(Int(abs(naturalSize.width.rounded())), fallback.resolutionWidth)
        let height = max(Int(abs(naturalSize.height.rounded())), fallback.resolutionHeight)
        let fps = track.nominalFrameRate > 0 ? Double(track.nominalFrameRate) : 30.0
        let seconds = CMTimeGetSeconds(asset.duration)
        let duration = seconds.isFinite ? seconds : 0
        return VideoDetails(width: width, height: height, fps: fps, durationSeconds: max(duration, 0))
    }

    func extractKeyframe(from videoURL: URL, durationSeconds: Double, to destinationURL: URL) throws {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1920, height: 1920)
        let midpoint = max(durationSeconds * 0.5, 0.0)
        let preferredTime = CMTime(seconds: midpoint, preferredTimescale: 600)

        do {
            let cgImage = try generator.copyCGImage(at: preferredTime, actualTime: nil)
            guard let data = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.82) else {
                throw BridgeError.keyframeExtractionFailed
            }
            try data.write(to: destinationURL, options: .atomic)
        } catch {
            let fallbackTime = CMTime(seconds: 0, preferredTimescale: 600)
            do {
                let cgImage = try generator.copyCGImage(at: fallbackTime, actualTime: nil)
                guard let data = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.82) else {
                    throw BridgeError.keyframeExtractionFailed
                }
                try data.write(to: destinationURL, options: .atomic)
            } catch {
                throw BridgeError.keyframeExtractionFailed
            }
        }
    }

    private func loadARFrameSamples(from url: URL?) throws -> [ARFrameSample] {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return [] }
        let contents = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return contents
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                let data = Data(line.utf8)
                return try? decoder.decode(ARFrameSample.self, from: data)
            }
    }

    func normalizeRequestedLanes(_ lanes: [String]) -> [String] {
        let allowed = ["qualification", "advanced_geometry"]
        var normalized: [String] = []
        for lane in lanes {
            let lowered = lane.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if lowered == "all" {
                for allowedLane in allowed where !normalized.contains(allowedLane) {
                    normalized.append(allowedLane)
                }
                continue
            }
            if allowed.contains(lowered) && !normalized.contains(lowered) {
                normalized.append(lowered)
            }
        }
        return normalized.isEmpty ? ["qualification"] : normalized
    }

    func inferEnvironmentTypeHint(from context: TaskCaptureContext) -> String {
        let corpus = [
            context.siteName,
            context.taskStatement,
            context.workflowContext,
            context.siteLocation,
            context.targetRobotTeam,
        ]
            .joined(separator: " ")
            .lowercased()

        if corpus.contains("kitchen") {
            return "kitchen"
        }
        if corpus.contains("warehouse") || corpus.contains("pallet") || corpus.contains("dock") {
            return "warehouse"
        }
        if corpus.contains("bedroom") || corpus.contains("bed room") {
            return "bedroom"
        }
        return "default"
    }

    func buildQualitySummary(
        manifest: VideoCaptureManager.CaptureManifest,
        durationSeconds: Double,
        arFrameCount: Int
    ) -> [String: Any] {
        [
            "pose_match_rate": arFrameCount > 0 ? 1.0 : 0.0,
            "video_duration_seconds": durationSeconds,
            "arkit_frame_count": arFrameCount,
            "covered_area_count": manifest.evidenceCoverageMetadata.coveredAreas,
            "declared_area_count": manifest.evidenceCoverageMetadata.totalDeclaredAreas
        ]
    }

    func buildMetadataPayload(from context: TaskCaptureContext) -> [String: Any] {
        let taskZone = context.workcellTaskZoneBoundaries.first
        return [
            "submission_id": context.submissionId,
            "site_id": context.siteId,
            "task_id": context.taskId,
            "capture_pass_id": context.capturePass.capturePassId,
            "buyer_type": context.buyerType.rawValue,
            "site_name": context.siteName,
            "site_location": context.siteLocation,
            "task_statement": context.taskStatement,
            "workflow_context": context.workflowContext,
            "operating_constraints": context.operatingConstraints,
            "known_blockers": splitTextList(context.knownBlockers),
            "target_robot_team": context.targetRobotTeam,
            "workcell_task_zone_boundaries": context.workcellTaskZoneBoundaries.map(boundaryDictionary),
            "task_zone": taskZone.map(boundaryDictionary) ?? [:],
            "privacy_security_restrictions": context.privacySecurityRestrictions.map(restrictionDictionary),
            "privacy_restrictions": context.privacySecurityRestrictions.map(restrictionDictionary),
            "security_restrictions": context.privacySecurityRestrictions.map(restrictionDictionary),
            "capture_checklist": context.captureChecklist.map(checklistDictionary),
            "zone_coverage_declarations": context.zoneCoverageDeclarations.map(coverageDictionary),
            "evidence_coverage_metadata": evidenceCoverageDictionary(context.evidenceCoverageMetadata),
            "privacy_annotations": context.privacyAnnotations,
            "preferred_geometry_bundle_files": context.preferredGeometryBundleFiles,
            "capture_mode": context.capturePass.captureMode.rawValue
        ]
    }

    func buildRawManifest(
        sceneId: String,
        rawVideoURI: String,
        manifest: VideoCaptureManager.CaptureManifest,
        environmentHint: String,
        videoDetails: VideoDetails,
        hasLidar: Bool
    ) -> [String: Any] {
        [
            "scene_id": sceneId,
            "video_uri": rawVideoURI,
            "device_model": manifest.deviceFacts.deviceModel,
            "os_version": manifest.deviceFacts.systemVersion,
            "fps_source": videoDetails.fps,
            "width": videoDetails.width,
            "height": videoDetails.height,
            "capture_start_epoch_ms": Int(manifest.captureStartedAt.timeIntervalSince1970 * 1000),
            "has_lidar": hasLidar,
            "scale_hint_m_per_unit": 1.0,
            "intended_space_type": environmentHint,
            "exposure_samples": manifest.technicalCapture.exposureSamples.map(exposureSampleDictionary),
            "object_point_cloud_count": 0,
            "capture_schema_version": "v1",
            "capture_source": "iphone",
            "capture_tier_hint": "tier1_iphone"
        ]
    }

    private func buildFramesIndexLines(
        sceneId: String,
        captureId: String,
        rawVideoURI: String,
        keyframeURI: String,
        arFrameSamples: [ARFrameSample],
        startedAt: Date,
        durationSeconds: Double
    ) -> [[String: Any]] {
        guard !arFrameSamples.isEmpty else {
            return [[
                "frame_id": "\(captureId)_keyframe_0000",
                "frame_index": 0,
                "timestamp_sec": max(durationSeconds * 0.5, 0.0),
                "captured_at": iso8601String(from: startedAt.addingTimeInterval(max(durationSeconds * 0.5, 0.0))),
                "scene_id": sceneId,
                "capture_id": captureId,
                "image_uri": keyframeURI,
                "video_uri": rawVideoURI,
                "kind": "keyframe"
            ]]
        }

        return arFrameSamples.map { sample in
            [
                "frame_id": "\(captureId)_frame_\(String(format: "%05d", sample.frameIndex))",
                "frame_index": sample.frameIndex,
                "timestamp_sec": sample.timestamp,
                "captured_at": iso8601String(from: sample.capturedAt),
                "scene_id": sceneId,
                "capture_id": captureId,
                "image_uri": keyframeURI,
                "video_uri": rawVideoURI,
                "camera_transform": sample.cameraTransform,
                "intrinsics": sample.intrinsics,
                "image_resolution": sample.imageResolution
            ]
        }
    }

    private func buildARPoseLines(sceneId: String, captureId: String, samples: [ARFrameSample]) -> [[String: Any]] {
        samples.map { sample in
            [
                "scene_id": sceneId,
                "capture_id": captureId,
                "frame_id": "\(captureId)_frame_\(String(format: "%05d", sample.frameIndex))",
                "frame_index": sample.frameIndex,
                "timestamp_sec": sample.timestamp,
                "captured_at": iso8601String(from: sample.capturedAt),
                "camera_transform": sample.cameraTransform
            ]
        }
    }

    private func buildIntrinsicsPayload(
        sceneId: String,
        captureId: String,
        manifest: VideoCaptureManager.CaptureManifest,
        samples: [ARFrameSample]
    ) -> [String: Any] {
        let firstSample = samples.first
        return [
            "schema_version": "v1",
            "scene_id": sceneId,
            "capture_id": captureId,
            "camera_intrinsics": cameraIntrinsicsDictionary(manifest.technicalCapture.cameraIntrinsics),
            "sample_intrinsics": firstSample?.intrinsics ?? [],
            "image_resolution": firstSample?.imageResolution ?? [
                manifest.technicalCapture.cameraIntrinsics.resolutionWidth,
                manifest.technicalCapture.cameraIntrinsics.resolutionHeight
            ]
        ]
    }

    func buildDescriptor(
        sceneId: String,
        captureId: String,
        rawPrefixURI: String,
        framesIndexURI: String,
        rawVideoURI: String,
        keyframeURI: String,
        qaReportURI: String,
        qaStatus: String,
        requestedLanes: [String],
        environmentHint: String,
        nurecMode: String,
        quality: [String: Any],
        context: TaskCaptureContext,
        arkitPosesURI: String?,
        arkitIntrinsicsURI: String?,
        arkitDepthPrefixURI: String?,
        arkitConfidencePrefixURI: String?
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "schema_version": "v1",
            "scene_id": sceneId,
            "capture_id": captureId,
            "capture_source": "iphone",
            "capture_tier": "tier1_iphone",
            "raw_prefix_uri": rawPrefixURI,
            "frames_index_uri": framesIndexURI,
            "raw_video_uri": rawVideoURI,
            "keyframe_uri": keyframeURI,
            "nurec_mode": nurecMode,
            "qa_report_uri": qaReportURI,
            "qa_status": qaStatus,
            "requested_lanes": requestedLanes,
            "environment_type_hint": environmentHint,
            "swap_focus": environmentHint == "default" ? [] : [environmentHint],
            "quality": quality,
            "metadata": buildMetadataPayload(from: context)
        ]

        var captureBundle: [String: Any] = [:]
        if let arkitPosesURI {
            payload["arkit_poses_uri"] = arkitPosesURI
            captureBundle["arkit_poses_uri"] = arkitPosesURI
        }
        if let arkitIntrinsicsURI {
            payload["arkit_intrinsics_uri"] = arkitIntrinsicsURI
            captureBundle["arkit_intrinsics_uri"] = arkitIntrinsicsURI
        }
        if let arkitDepthPrefixURI {
            payload["arkit_depth_prefix_uri"] = arkitDepthPrefixURI
            captureBundle["arkit_depth_prefix_uri"] = arkitDepthPrefixURI
        }
        if let arkitConfidencePrefixURI {
            payload["arkit_confidence_prefix_uri"] = arkitConfidencePrefixURI
            captureBundle["arkit_confidence_prefix_uri"] = arkitConfidencePrefixURI
        }
        if !captureBundle.isEmpty {
            payload["capture_bundle"] = captureBundle
        }

        return payload
    }

    func buildPreflightChecks(
        rawManifestExists: Bool,
        rawVideoExists: Bool,
        framesIndexExists: Bool,
        keyframeExists: Bool,
        arkitPosesExists: Bool
    ) -> [PreflightCheck] {
        [
            PreflightCheck(name: "raw_manifest_ready", passed: rawManifestExists, detail: rawManifestExists ? "staged raw manifest" : "missing raw manifest"),
            PreflightCheck(name: "raw_video_ready", passed: rawVideoExists, detail: rawVideoExists ? "staged raw video" : "missing raw video"),
            PreflightCheck(name: "frames_index_ready", passed: framesIndexExists, detail: framesIndexExists ? "staged frames index" : "missing frames index"),
            PreflightCheck(name: "keyframe_ready", passed: keyframeExists, detail: keyframeExists ? "staged keyframe" : "missing keyframe"),
            PreflightCheck(name: "arkit_pose_bundle", passed: true, detail: arkitPosesExists ? "ARKit poses staged" : "ARKit poses unavailable; mono_slam fallback applies")
        ]
    }

    func buildQAReport(
        sceneId: String,
        captureId: String,
        status: String,
        requestedLanes: [String],
        checks: [PreflightCheck]
    ) -> [String: Any] {
        [
            "schema_version": "v1",
            "scene_id": sceneId,
            "capture_id": captureId,
            "lane": "qualification",
            "status": status,
            "requested_lanes": requestedLanes,
            "generated_at": iso8601String(from: nowProvider()),
            "checks": checks.map(\.asDictionary)
        ]
    }

    func uploadArtifacts(
        for files: [URL],
        rootDirectory: URL?,
        remotePrefix: String,
        role: CaptureUploadArtifact.Role
    ) -> [CaptureUploadArtifact] {
        guard let rootDirectory else { return [] }
        return files.map { fileURL in
            let relativePath = relativePath(for: fileURL, rootDirectory: rootDirectory)
            return CaptureUploadArtifact(
                localFileURL: fileURL,
                storagePath: "\(remotePrefix)/\(relativePath)",
                contentType: contentType(for: fileURL),
                role: role,
                required: false
            )
        }
    }

    func enumerateFiles(in directoryURL: URL?) -> [URL] {
        guard let directoryURL, FileManager.default.fileExists(atPath: directoryURL.path) else { return [] }
        let enumerator = FileManager.default.enumerator(at: directoryURL, includingPropertiesForKeys: [.isRegularFileKey])
        return (enumerator?.allObjects as? [URL] ?? [])
            .filter { url in
                (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            }
            .sorted { $0.path < $1.path }
    }

    func relativePath(for url: URL, rootDirectory: URL) -> String {
        let path = url.standardizedFileURL.path
        let basePath = rootDirectory.standardizedFileURL.path
        guard path.hasPrefix(basePath) else { return url.lastPathComponent }
        var relative = String(path.dropFirst(basePath.count))
        while relative.hasPrefix("/") {
            relative.removeFirst()
        }
        return relative.isEmpty ? url.lastPathComponent : relative
    }

    func buildMetadata(for context: TaskCaptureContext, capturedAt: Date) -> CaptureUploadMetadata {
        CaptureUploadMetadata(
            id: UUID(),
            submissionId: context.submissionId,
            siteId: context.siteId,
            taskId: context.taskId,
            capturePassId: context.capturePass.capturePassId,
            creatorId: "bridge",
            capturedAt: capturedAt,
            uploadedAt: nil
        )
    }

    func gsURI(bucket: String, path: String) -> String {
        "gs://\(bucket)/\(path)"
    }

    func writeJSONObject(_ payload: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    func writeJSONLines(_ payloads: [[String: Any]], to url: URL) throws {
        var data = Data()
        for payload in payloads {
            data.append(try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]))
            data.append(Data("\n".utf8))
        }
        try data.write(to: url, options: .atomic)
    }

    func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    func splitTextList(_ text: String) -> [String] {
        text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func boundaryDictionary(_ boundary: TaskZoneBoundary) -> [String: Any] {
        [
            "id": boundary.id,
            "name": boundary.name,
            "boundary_notes": boundary.boundaryNotes,
            "adjacent_workflow": boundary.adjacentWorkflow
        ]
    }

    func restrictionDictionary(_ restriction: PrivacySecurityRestriction) -> [String: Any] {
        [
            "id": restriction.id,
            "title": restriction.title,
            "details": restriction.details,
            "severity": restriction.severity.rawValue
        ]
    }

    func checklistDictionary(_ item: CaptureChecklistItem) -> [String: Any] {
        [
            "id": item.id,
            "title": item.title,
            "details": item.details,
            "is_completed": item.isCompleted
        ]
    }

    func coverageDictionary(_ item: EvidenceCoverageDeclaration) -> [String: Any] {
        [
            "id": item.id,
            "area": item.area,
            "notes": item.notes,
            "is_covered": item.isCovered
        ]
    }

    func evidenceCoverageDictionary(_ metadata: EvidenceCoverageMetadata) -> [String: Any] {
        [
            "total_declared_areas": metadata.totalDeclaredAreas,
            "covered_areas": metadata.coveredAreas,
            "coverage_summary": metadata.coverageSummary
        ]
    }

    func exposureSampleDictionary(_ sample: VideoCaptureManager.CaptureManifest.ExposureSample) -> [String: Any] {
        [
            "timestamp": iso8601String(from: sample.timestamp),
            "iso": sample.iso,
            "exposure_duration_seconds": sample.exposureDurationSeconds,
            "exposure_target_bias": sample.exposureTargetBias,
            "white_balance_gains": [
                "red": sample.whiteBalanceGains.red,
                "green": sample.whiteBalanceGains.green,
                "blue": sample.whiteBalanceGains.blue
            ]
        ]
    }

    func cameraIntrinsicsDictionary(_ intrinsics: VideoCaptureManager.CaptureManifest.CameraIntrinsics) -> [String: Any] {
        var payload: [String: Any] = [
            "resolution_width": intrinsics.resolutionWidth,
            "resolution_height": intrinsics.resolutionHeight
        ]
        if let intrinsicMatrix = intrinsics.intrinsicMatrix {
            payload["intrinsic_matrix"] = intrinsicMatrix
        }
        if let fieldOfView = intrinsics.fieldOfView {
            payload["field_of_view"] = fieldOfView
        }
        if let lensAperture = intrinsics.lensAperture {
            payload["lens_aperture"] = lensAperture
        }
        if let minimumFocusDistance = intrinsics.minimumFocusDistance {
            payload["minimum_focus_distance"] = minimumFocusDistance
        }
        return payload
    }

    func contentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "json":
            return "application/json"
        case "jsonl":
            return "application/x-ndjson"
        case "mov":
            return "video/quicktime"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "obj":
            return "text/plain"
        case "bin":
            return "application/octet-stream"
        case "zip":
            return "application/zip"
        default:
            return "application/octet-stream"
        }
    }
}
