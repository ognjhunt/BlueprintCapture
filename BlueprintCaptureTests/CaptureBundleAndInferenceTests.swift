import Foundation
import Testing
@testable import BlueprintCapture

struct CaptureBundleAndInferenceTests {

    @Test
    func finalizerAndExportProducePipelineReadyBundle() async throws {
        let fileManager = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("capture-bundle-\(UUID().uuidString)", isDirectory: true)
        let raw = root.appendingPathComponent("raw-source", isDirectory: true)
        let arkit = raw.appendingPathComponent("arkit", isDirectory: true)
        try fileManager.createDirectory(at: arkit, withIntermediateDirectories: true)

        try Data("video".utf8).write(to: raw.appendingPathComponent("walkthrough.mov"))
        try Data("{\"scene_id\":\"\",\"video_uri\":\"\"}".utf8).write(to: raw.appendingPathComponent("manifest.json"))
        try Data("{}".utf8).write(to: arkit.appendingPathComponent("intrinsics.json"))

        let metadata = CaptureUploadMetadata(
            id: UUID(),
            targetId: "scene-123",
            reservationId: nil,
            jobId: "scene-123",
            creatorId: "tester",
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            uploadedAt: nil,
            captureSource: .iphoneVideo,
            intakePacket: QualificationIntakePacket(
                workflowName: "Inbound walk",
                taskSteps: ["Enter aisle", "Walk route"],
                zone: "Aisle 4"
            ),
            intakeMetadata: CaptureIntakeMetadata(source: .aiInferred, model: "gemini-3-flash-preview", fps: 3, confidence: 0.72),
            taskHypothesis: CaptureTaskHypothesis(
                workflowName: "Inbound walk",
                taskSteps: ["Enter aisle", "Walk route"],
                zone: "Aisle 4",
                confidence: 0.72,
                source: .aiInferred,
                model: "gemini-3-flash-preview",
                fps: 3,
                warnings: [],
                status: .accepted
            ),
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
                derivedSceneGenerationAllowed: true,
                dataLicensingAllowed: true,
                payoutEligible: true,
                consentNotes: ["Site owner approved downstream preview generation"]
            )
        )
        let request = CaptureUploadRequest(packageURL: raw, metadata: metadata)

        let finalizer = CaptureBundleFinalizer()
        _ = try finalizer.finalize(request: request, mode: .localExport())

        let manifestObject = try JSONSerialization.jsonObject(with: Data(contentsOf: raw.appendingPathComponent("manifest.json")))
        let manifest = try #require(manifestObject as? [String: Any])
        #expect(manifest["scene_id"] as? String == "scene-123")
        #expect(manifest["video_uri"] as? String == "raw/walkthrough.mov")
        #expect(manifest["capture_modality"] as? String == "iphone_arkit_lidar")
        let sceneMemory = try #require(manifest["scene_memory_capture"] as? [String: Any])
        #expect(sceneMemory["world_model_candidate"] as? Bool == true)
        let captureRights = try #require(manifest["capture_rights"] as? [String: Any])
        #expect(captureRights["data_licensing_allowed"] as? Bool == true)

        let completionObject = try JSONSerialization.jsonObject(with: Data(contentsOf: raw.appendingPathComponent("capture_upload_complete.json")))
        let completion = try #require(completionObject as? [String: Any])
        #expect(completion["rawPrefix"] as? String == "raw")

        let contextObject = try JSONSerialization.jsonObject(with: Data(contentsOf: raw.appendingPathComponent("capture_context.json")))
        let context = try #require(contextObject as? [String: Any])
        #expect(context["intakeSource"] as? String == "ai_inferred")
        #expect(context["intakeInferenceModel"] as? String == "gemini-3-flash-preview")
        #expect(context["taskHypothesisStatus"] as? String == "accepted")
        #expect(context["worldModelCandidate"] as? Bool == true)

        let hypothesisObject = try JSONSerialization.jsonObject(with: Data(contentsOf: raw.appendingPathComponent("task_hypothesis.json")))
        let hypothesis = try #require(hypothesisObject as? [String: Any])
        #expect(hypothesis["workflow_name"] as? String == "Inbound walk")
        #expect(hypothesis["status"] as? String == "accepted")

        let exporter = CaptureExportService(finalizer: finalizer)
        let bundle = try await exporter.exportCapture(request: request)
        #expect(bundle.captureRootURL.path.contains("/scenes/scene-123/captures/"))
        #expect(fileManager.fileExists(atPath: bundle.rawDirectoryURL.appendingPathComponent("manifest.json").path))
        #expect(fileManager.fileExists(atPath: bundle.rawDirectoryURL.appendingPathComponent("walkthrough.mov").path))
        #expect(fileManager.fileExists(atPath: bundle.rawDirectoryURL.appendingPathComponent("arkit/intrinsics.json").path))
        #expect(fileManager.fileExists(atPath: (bundle.shareURL ?? bundle.captureRootURL).path))
    }

    @Test
    func intakeResolutionUsesAuthoritativeIntakeBeforeAI() async throws {
        let service = IntakeResolutionService(inferenceService: FailingInferenceService())
        let request = CaptureUploadRequest(packageURL: URL(fileURLWithPath: "/tmp/fake"), metadata: CaptureUploadMetadata(
            id: UUID(),
            targetId: "job-1",
            reservationId: nil,
            jobId: "job-1",
            creatorId: "tester",
            capturedAt: Date(),
            uploadedAt: nil,
            captureSource: .metaGlasses,
            intakePacket: QualificationIntakePacket(workflowName: "Job flow", taskSteps: ["Walk"], zone: "Dock"),
            intakeMetadata: nil,
            taskHypothesis: nil,
            scaffoldingPacket: nil,
            captureModality: nil,
            evidenceTier: nil,
            captureContextHint: nil
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
            creatorId: "tester",
            capturedAt: Date(),
            uploadedAt: nil,
            captureSource: .iphoneVideo,
            intakePacket: nil,
            intakeMetadata: nil,
            taskHypothesis: nil,
            scaffoldingPacket: nil,
            captureModality: nil,
            evidenceTier: nil,
            captureContextHint: "Test capture"
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
            creatorId: "tester",
            capturedAt: Date(),
            uploadedAt: nil,
            captureSource: .iphoneVideo,
            intakePacket: nil,
            intakeMetadata: nil,
            taskHypothesis: nil,
            scaffoldingPacket: nil,
            captureModality: nil,
            evidenceTier: nil,
            captureContextHint: "Packing area"
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
                let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
                InferenceURLProtocol.capturedBodies.append(body)
                let isFirstAttempt = InferenceURLProtocol.capturedBodies.count == 1
                let json = isFirstAttempt
                    ? #"{"workflowName":"Walkthrough","taskSteps":["Step one"],"warnings":["Need zone"],"confidence":0.42}"#
                    : #"{"workflowName":"Walkthrough","taskSteps":["Step one","Step two"],"zone":"Packing","confidence":0.82}"#
                let responsePayload = #"{"candidates":[{"content":{"parts":[{"text":"\#(json)"}]}}]}"#
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(responsePayload.utf8))
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
            creatorId: "tester",
            capturedAt: Date(),
            uploadedAt: nil,
            captureSource: .iphoneVideo,
            intakePacket: nil,
            intakeMetadata: nil,
            taskHypothesis: nil,
            scaffoldingPacket: nil,
            captureModality: nil,
            evidenceTier: nil,
            captureContextHint: "Packing area"
        ))

        let service = CaptureIntakeInferenceService(session: session, apiKeyProvider: { "test-key" })
        let result = try await service.inferIntake(for: request)

        #expect(result.metadata.model == "gemini-3-flash-preview")
        #expect(result.metadata.fps == 5)
        #expect(result.intakePacket.zone == "Packing")
        #expect(InferenceURLProtocol.capturedBodies.contains(where: { $0.contains("\"fps\":3") }))
        #expect(InferenceURLProtocol.capturedBodies.contains(where: { $0.contains("\"fps\":5") }))
        #expect(InferenceURLProtocol.capturedBodies.contains(where: { $0.contains("responseSchema") }))
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
