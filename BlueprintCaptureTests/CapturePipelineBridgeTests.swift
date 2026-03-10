import AVFoundation
import Combine
import CoreVideo
import Foundation
import Testing
@testable import BlueprintCapture

struct CapturePipelineBridgeTests {
    @Test func bridgeStagesPipelineArtifactsWithQualificationDefaults() async throws {
        let fixture = try await Self.makeRecordingFixture(includeARKit: false)
        let bridge = CapturePipelineBridge(
            bucketProvider: { "bucket" },
            nowProvider: { Date(timeIntervalSince1970: 1_700_000_600) }
        )

        let output = try bridge.stageArtifacts(
            for: fixture.context,
            recording: fixture.artifacts,
            requestedLanesOverride: nil
        )

        #expect(output.sceneId == fixture.context.siteId)
        #expect(output.captureId == fixture.context.capturePass.capturePassId)
        #expect(output.artifacts.last?.role == .captureDescriptor)
        #expect(output.artifacts.map(\.storagePath).contains("scenes/\(fixture.context.siteId)/captures/\(fixture.context.capturePass.capturePassId)/qa_report.json"))
        #expect(output.artifacts.map(\.storagePath).contains("scenes/\(fixture.context.siteId)/iphone/\(fixture.context.capturePass.capturePassId)/raw/manifest.json"))

        let descriptorArtifact = try #require(output.artifacts.first(where: { $0.role == .captureDescriptor }))
        let descriptor = try Self.loadJSON(from: descriptorArtifact.localFileURL)
        let metadata = try #require(descriptor["metadata"] as? [String: Any])

        #expect(descriptor["scene_id"] as? String == fixture.context.siteId)
        #expect(descriptor["capture_id"] as? String == fixture.context.capturePass.capturePassId)
        #expect(descriptor["capture_source"] as? String == "iphone")
        #expect(descriptor["capture_tier"] as? String == "tier1_iphone")
        #expect(descriptor["nurec_mode"] as? String == "mono_slam")
        #expect(descriptor["requested_lanes"] as? [String] == ["qualification"])
        #expect(metadata["task_statement"] as? String == fixture.context.taskStatement)
        #expect(metadata["site_id"] as? String == fixture.context.siteId)

        let qaArtifact = try #require(output.artifacts.first(where: { $0.role == .qaReport }))
        let qaReport = try Self.loadJSON(from: qaArtifact.localFileURL)
        #expect(qaReport["status"] as? String == "passed")
    }

    @Test func bridgeStagesARKitArtifactsAndRequestedLaneOverride() async throws {
        let fixture = try await Self.makeRecordingFixture(includeARKit: true)
        let bridge = CapturePipelineBridge(bucketProvider: { "bucket" })

        let output = try bridge.stageArtifacts(
            for: fixture.context,
            recording: fixture.artifacts,
            requestedLanesOverride: ["qualification", "advanced_geometry"]
        )

        let descriptorArtifact = try #require(output.artifacts.first(where: { $0.role == .captureDescriptor }))
        let descriptor = try Self.loadJSON(from: descriptorArtifact.localFileURL)

        #expect(descriptor["nurec_mode"] as? String == "mono_pose_assisted")
        #expect(descriptor["requested_lanes"] as? [String] == ["qualification", "advanced_geometry"])
        #expect((descriptor["arkit_poses_uri"] as? String)?.hasSuffix("/raw/arkit/poses.jsonl") == true)
        #expect((descriptor["arkit_intrinsics_uri"] as? String)?.hasSuffix("/raw/arkit/intrinsics.json") == true)
        #expect((descriptor["arkit_depth_prefix_uri"] as? String)?.hasSuffix("/raw/arkit/depth") == true)
        #expect((descriptor["arkit_confidence_prefix_uri"] as? String)?.hasSuffix("/raw/arkit/confidence") == true)

        #expect(output.artifacts.contains(where: { $0.role == .arKitPoses }))
        #expect(output.artifacts.contains(where: { $0.role == .arKitIntrinsics }))
        #expect(output.artifacts.contains(where: { $0.role == .arKitDepth }))
        #expect(output.artifacts.contains(where: { $0.role == .arKitConfidence }))
        #expect(output.artifacts.contains(where: { $0.role == .arKitMesh }))
    }

    @MainActor
    @Test func viewModelEnqueuesBridgedUploadAndKeepsSummaryFlow() async throws {
        let fixture = try await Self.makeRecordingFixture(includeARKit: false)
        let uploadSpy = UploadServiceSpy()
        let bridgeSpy = BridgeSpy(output: CapturePipelineBridge.Output(
            sceneId: fixture.context.siteId,
            captureId: fixture.context.capturePass.capturePassId,
            descriptorURI: "gs://bucket/scenes/\(fixture.context.siteId)/captures/\(fixture.context.capturePass.capturePassId)/capture_descriptor.json",
            qaReportURI: "gs://bucket/scenes/\(fixture.context.siteId)/captures/\(fixture.context.capturePass.capturePassId)/qa_report.json",
            rawManifestURI: "gs://bucket/scenes/\(fixture.context.siteId)/iphone/\(fixture.context.capturePass.capturePassId)/raw/manifest.json",
            framesIndexURI: "gs://bucket/scenes/\(fixture.context.siteId)/captures/\(fixture.context.capturePass.capturePassId)/frames/index.jsonl",
            artifacts: [
                .legacyPackage(
                    localFileURL: fixture.artifacts.packageURL,
                    storagePath: CaptureUploadService.storagePath(
                        forLegacyPackageAt: fixture.artifacts.packageURL,
                        metadata: CaptureUploadMetadata(
                            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                            submissionId: fixture.context.submissionId,
                            siteId: fixture.context.siteId,
                            taskId: fixture.context.taskId,
                            capturePassId: fixture.context.capturePass.capturePassId,
                            creatorId: "creator",
                            capturedAt: fixture.artifacts.startedAt,
                            uploadedAt: nil
                        )
                    )
                ),
                CaptureUploadArtifact(
                    localFileURL: fixture.artifacts.manifestURL,
                    storagePath: "scenes/\(fixture.context.siteId)/captures/\(fixture.context.capturePass.capturePassId)/capture_descriptor.json",
                    contentType: "application/json",
                    role: .captureDescriptor,
                    required: true
                )
            ]
        ))
        let viewModel = CaptureFlowViewModel(uploadService: uploadSpy, pipelineBridge: bridgeSpy)

        viewModel.submissionDraft.siteName = fixture.context.siteName
        viewModel.submissionDraft.siteLocation = fixture.context.siteLocation
        viewModel.submissionDraft.taskStatement = fixture.context.taskStatement
        viewModel.submissionDraft.workflowContext = fixture.context.workflowContext
        viewModel.submissionDraft.operatingConstraints = fixture.context.operatingConstraints
        viewModel.submissionDraft.knownBlockers = fixture.context.knownBlockers
        viewModel.submissionDraft.targetRobotTeam = fixture.context.targetRobotTeam
        viewModel.submissionDraft.taskZoneBoundaryNotes = fixture.context.workcellTaskZoneBoundaries.first?.boundaryNotes ?? ""
        viewModel.currentAddress = fixture.context.siteLocation
        viewModel.captureChecklist = fixture.context.captureChecklist
        viewModel.evidenceCoverageDeclarations = fixture.context.zoneCoverageDeclarations
        viewModel.beginCapture()
        viewModel.handleRecordingFinished(artifacts: fixture.artifacts)

        #expect(viewModel.step == .captureSummary)
        #expect(uploadSpy.enqueuedRequests.count == 1)
        #expect(uploadSpy.enqueuedRequests.first?.artifacts.count == 2)
        #expect(uploadSpy.enqueuedRequests.first?.metadata.capturedAt == fixture.artifacts.startedAt)
        #expect(bridgeSpy.callCount == 1)
    }
}

private extension CapturePipelineBridgeTests {
    struct RecordingFixture {
        let context: TaskCaptureContext
        let artifacts: VideoCaptureManager.RecordingArtifacts
    }

    final class UploadServiceSpy: CaptureUploadServiceProtocol {
        let subject = PassthroughSubject<CaptureUploadService.Event, Never>()
        private(set) var enqueuedRequests: [CaptureUploadRequest] = []

        var events: AnyPublisher<CaptureUploadService.Event, Never> {
            subject.eraseToAnyPublisher()
        }

        func enqueue(_ request: CaptureUploadRequest) {
            enqueuedRequests.append(request)
            subject.send(.queued(request))
        }

        func retryUpload(id: UUID) {}
        func cancelUpload(id: UUID) {}
    }

    final class BridgeSpy: CapturePipelineBridgeProtocol {
        private(set) var callCount = 0
        let output: CapturePipelineBridge.Output

        init(output: CapturePipelineBridge.Output) {
            self.output = output
        }

        func stageArtifacts(
            for context: TaskCaptureContext,
            recording artifacts: VideoCaptureManager.RecordingArtifacts,
            requestedLanesOverride: [String]?
        ) throws -> CapturePipelineBridge.Output {
            callCount += 1
            return output
        }
    }

    static func makeRecordingFixture(includeARKit: Bool) async throws -> RecordingFixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("capture-pipeline-bridge-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let context = SiteSubmissionDraft(
            submissionId: "submission_demo",
            siteId: "site_demo",
            taskId: "task_demo",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            buyerType: .siteOperator,
            siteName: includeARKit ? "Kitchen warehouse hybrid" : "Warehouse demo",
            siteLocation: "Durham, NC",
            taskStatement: "Capture the pallet handoff zone.",
            workflowContext: "Operators move totes between staging and inspection.",
            operatingConstraints: "Aisle traffic stays active during the walkthrough.",
            privacySecurityNotes: "Avoid badge readers.",
            knownBlockers: "Reflective floor near the dock.",
            targetRobotTeam: "Qualification Ops",
            taskZoneName: "Primary task zone",
            taskZoneBoundaryNotes: "From the dock door to the inbound pallet lane.",
            adjacentWorkflowNotes: "Packing line and outbound conveyor."
        ).makeTaskCaptureContext(
            checklist: TaskCaptureContext.defaultChecklist().map {
                var item = $0
                item.isCompleted = true
                return item
            },
            coverage: TaskCaptureContext.defaultCoverageDeclarations().map {
                var item = $0
                item.isCovered = true
                return item
            },
            capturePassId: "capture_pass_demo"
        )

        let packageURL = root.appendingPathComponent("capture.zip")
        let videoURL = root.appendingPathComponent("capture.mov")
        let motionLogURL = root.appendingPathComponent("capture-motion.jsonl")
        let manifestURL = root.appendingPathComponent("capture-package-manifest.json")
        try Data("zip".utf8).write(to: packageURL)
        try Data("{\"sample\":true}\n".utf8).write(to: motionLogURL)
        try await writeVideo(to: videoURL)

        let arKitArtifacts: VideoCaptureManager.RecordingArtifacts.ARKitArtifacts?
        if includeARKit {
            let arkitRoot = root.appendingPathComponent("arkit", isDirectory: true)
            let depthDir = arkitRoot.appendingPathComponent("depth", isDirectory: true)
            let confidenceDir = arkitRoot.appendingPathComponent("confidence", isDirectory: true)
            let meshDir = arkitRoot.appendingPathComponent("meshes", isDirectory: true)
            try FileManager.default.createDirectory(at: depthDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: confidenceDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: meshDir, withIntermediateDirectories: true)
            let frameLogURL = arkitRoot.appendingPathComponent("frames.jsonl")
            try writeARFrameLog(to: frameLogURL)
            try Data([0x00, 0x01]).write(to: depthDir.appendingPathComponent("scene-depth-00000.bin"))
            try Data([0x02]).write(to: confidenceDir.appendingPathComponent("confidence-00000.bin"))
            try Data("o mesh\n".utf8).write(to: meshDir.appendingPathComponent("mesh-demo.obj"))
            arKitArtifacts = .init(
                rootDirectoryURL: arkitRoot,
                frameLogURL: frameLogURL,
                depthDirectoryURL: depthDir,
                confidenceDirectoryURL: confidenceDir,
                meshDirectoryURL: meshDir
            )
        } else {
            arKitArtifacts = nil
        }

        let artifacts = VideoCaptureManager.RecordingArtifacts(
            baseFilename: "capture",
            directoryURL: root,
            videoURL: videoURL,
            motionLogURL: motionLogURL,
            manifestURL: manifestURL,
            arKit: arKitArtifacts,
            packageURL: packageURL,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        try writeCaptureManifest(to: manifestURL, includeARKit: includeARKit)

        return RecordingFixture(context: context, artifacts: artifacts)
    }

    static func writeCaptureManifest(to url: URL, includeARKit: Bool) throws {
        let manifest = VideoCaptureManager.CaptureManifest(
            siteSubmissionId: "submission_demo",
            siteId: "site_demo",
            taskId: "task_demo",
            capturePassId: "capture_pass_demo",
            taskStatement: "Capture the pallet handoff zone.",
            mediaFiles: [
                .init(kind: "video", path: "capture.mov", required: true),
                .init(kind: "motion_log", path: "capture-motion.jsonl", required: true),
                .init(kind: "manifest", path: "capture-package-manifest.json", required: true)
            ],
            deviceFacts: .init(
                captureMode: "phone",
                deviceModel: "iPhone 15 Pro",
                systemName: "iOS",
                systemVersion: "18.0",
                arkitSupported: includeARKit,
                meshReconstructionSupported: includeARKit
            ),
            captureStartedAt: Date(timeIntervalSince1970: 1_700_000_000),
            captureCompletedAt: Date(timeIntervalSince1970: 1_700_000_060),
            arkitAvailable: includeARKit,
            captureChecklist: [
                .init(title: "Task-zone walkthrough", details: "done", isCompleted: true)
            ],
            workcellTaskZoneBoundaries: [
                .init(name: "Primary task zone", boundaryNotes: "dock to lane", adjacentWorkflow: "packing")
            ],
            privacySecurityRestrictions: [
                .init(title: "Privacy", details: "Avoid badge readers.", severity: .medium)
            ],
            zoneCoverageDeclarations: [
                .init(area: "Primary task zone", notes: "visible", isCovered: true)
            ],
            evidenceCoverageMetadata: .init(totalDeclaredAreas: 1, coveredAreas: 1, coverageSummary: "Primary task zone"),
            privacyAnnotations: ["Privacy: Avoid badge readers."],
            preferredGeometryBundleFiles: ["3dgs_compressed.ply", "labels.json"],
            technicalCapture: .init(
                videoFile: "capture.mov",
                motionLogFile: "capture-motion.jsonl",
                manifestFile: "capture-package-manifest.json",
                durationSeconds: 60,
                cameraIntrinsics: .init(
                    resolutionWidth: 64,
                    resolutionHeight: 64,
                    intrinsicMatrix: [1, 0, 0, 0, 1, 0, 0, 0, 1],
                    fieldOfView: 80,
                    lensAperture: 1.8,
                    minimumFocusDistance: 0.1
                ),
                exposureSettings: .init(mode: "continuousAutoExposure", pointOfInterest: [0.5, 0.5], whiteBalanceMode: "continuousAutoWhiteBalance"),
                exposureSamples: [
                    .init(
                        timestamp: Date(timeIntervalSince1970: 1_700_000_010),
                        iso: 25,
                        exposureDurationSeconds: 0.016,
                        exposureTargetBias: 0,
                        whiteBalanceGains: .init(red: 1.0, green: 1.0, blue: 1.0)
                    )
                ],
                arKit: includeARKit ? .init(
                    frameLogFile: "arkit/frames.jsonl",
                    depthDirectory: "arkit/depth",
                    confidenceDirectory: "arkit/confidence",
                    meshDirectory: "arkit/meshes",
                    frameCount: 1
                ) : nil
            )
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(manifest)
        try data.write(to: url, options: .atomic)
    }

    static func writeARFrameLog(to url: URL) throws {
        let entry: [String: Any] = [
            "frameIndex": 0,
            "timestamp": 0.25,
            "capturedAt": "2023-11-14T22:13:30Z",
            "cameraTransform": [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0.1, 0.2, 0.3, 1],
            "intrinsics": [1, 0, 0, 0, 1, 0, 0, 0, 1],
            "imageResolution": [64, 64],
            "sceneDepthFile": "arkit/depth/scene-depth-00000.bin",
            "smoothedSceneDepthFile": NSNull(),
            "confidenceFile": "arkit/confidence/confidence-00000.bin"
        ]
        let line = try JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys])
        var data = line
        data.append(Data("\n".utf8))
        try data.write(to: url, options: .atomic)
    }

    static func loadJSON(from url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "CapturePipelineBridgeTests", code: 4, userInfo: nil)
        }
        return payload
    }

    static func writeVideo(to url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 64,
            AVVideoHeightKey: 64
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
                kCVPixelBufferWidthKey as String: 64,
                kCVPixelBufferHeightKey as String: 64
            ]
        )
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let firstBuffer = try pixelBuffer()
        let secondBuffer = try pixelBuffer()
        while !input.isReadyForMoreMediaData {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        adaptor.append(firstBuffer, withPresentationTime: .zero)
        while !input.isReadyForMoreMediaData {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        adaptor.append(secondBuffer, withPresentationTime: CMTime(value: 1, timescale: 2))
        input.markAsFinished()

        await withCheckedContinuation { continuation in
            writer.finishWriting {
                continuation.resume()
            }
        }

        if writer.status != .completed {
            throw writer.error ?? NSError(domain: "CapturePipelineBridgeTests", code: 1, userInfo: nil)
        }
    }

    static func pixelBuffer() throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            64,
            64,
            kCVPixelFormatType_32ARGB,
            [
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ] as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw NSError(domain: "CapturePipelineBridgeTests", code: 2, userInfo: nil)
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw NSError(domain: "CapturePipelineBridgeTests", code: 3, userInfo: nil)
        }
        memset(baseAddress, 0x66, bytesPerRow * height)
        return pixelBuffer
    }
}
