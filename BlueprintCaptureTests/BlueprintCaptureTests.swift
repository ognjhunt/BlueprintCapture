import Foundation
import Testing
@testable import BlueprintCapture

struct BlueprintCaptureTests {
    @Test func uploadMetadataUsesQualificationIdentifiers() async throws {
        let metadata = CaptureUploadMetadata(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            submissionId: "submission_123",
            siteId: "site_123",
            taskId: "task_123",
            capturePassId: "capture_pass_123",
            creatorId: "creator_123",
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            uploadedAt: nil
        )
        let request = CaptureUploadRequest(
            packageURL: URL(fileURLWithPath: "/tmp/capture-pass.zip"),
            metadata: metadata
        )

        let customMetadata = CaptureUploadService.customMetadata(for: metadata)
        let storagePath = CaptureUploadService.storagePath(for: request)

        #expect(customMetadata["submission_id"] == "submission_123")
        #expect(customMetadata["site_id"] == "site_123")
        #expect(customMetadata["task_id"] == "task_123")
        #expect(customMetadata["capture_pass_id"] == "capture_pass_123")
        #expect(storagePath.contains("site_submissions/submission_123/sites/site_123/tasks/task_123/capture_passes/capture_pass_123/"))
    }

    @Test func captureManifestEncodesQualificationAndTechnicalSections() async throws {
        let manifest = VideoCaptureManager.CaptureManifest(
            siteSubmissionId: "submission_123",
            siteId: "site_123",
            taskId: "task_123",
            capturePassId: "capture_pass_123",
            taskStatement: "Capture the pallet handoff zone.",
            mediaFiles: [
                .init(kind: "video", path: "capture.mov", required: true)
            ],
            deviceFacts: .init(
                captureMode: "phone",
                deviceModel: "iPhone",
                systemName: "iOS",
                systemVersion: "18.0",
                arkitSupported: false,
                meshReconstructionSupported: false
            ),
            captureStartedAt: Date(timeIntervalSince1970: 1_700_000_000),
            captureCompletedAt: Date(timeIntervalSince1970: 1_700_000_060),
            arkitAvailable: false,
            captureChecklist: [
                .init(title: "Task-zone walkthrough", details: "done", isCompleted: true)
            ],
            workcellTaskZoneBoundaries: [
                .init(name: "Primary task zone", boundaryNotes: "Counter to cart", adjacentWorkflow: "Packing line")
            ],
            privacySecurityRestrictions: [
                .init(title: "Privacy", details: "Do not record badge readers.", severity: .high)
            ],
            zoneCoverageDeclarations: [
                .init(area: "Primary task zone", notes: "visible", isCovered: true)
            ],
            evidenceCoverageMetadata: .init(totalDeclaredAreas: 1, coveredAreas: 1, coverageSummary: "Primary task zone"),
            privacyAnnotations: ["Privacy: Do not record badge readers."],
            preferredGeometryBundleFiles: ["3dgs_compressed.ply", "labels.json"],
            technicalCapture: .init(
                videoFile: "capture.mov",
                motionLogFile: "capture-motion.jsonl",
                manifestFile: "capture-package-manifest.json",
                durationSeconds: 60,
                cameraIntrinsics: .init(
                    resolutionWidth: 1920,
                    resolutionHeight: 1080,
                    intrinsicMatrix: nil,
                    fieldOfView: nil,
                    lensAperture: nil,
                    minimumFocusDistance: nil
                ),
                exposureSettings: .init(mode: "continuousAutoExposure", pointOfInterest: nil, whiteBalanceMode: "continuousAutoWhiteBalance"),
                exposureSamples: [],
                arKit: nil
            )
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(manifest)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let technical = try #require(json["technical_capture"] as? [String: Any])

        #expect(json["site_submission_id"] as? String == "submission_123")
        #expect(json["capture_pass_id"] as? String == "capture_pass_123")
        #expect(json["capture_checklist"] != nil)
        #expect(json["evidence_coverage_metadata"] != nil)
        #expect(json["privacy_security_restrictions"] != nil)
        #expect(technical["video_file"] as? String == "capture.mov")
        #expect(technical["camera_intrinsics"] != nil)
        #expect(technical["ar_kit"] == nil)
    }

    @Test func workflowRequiresChecklistAndStartsPhoneCapture() async throws {
        let viewModel = await MainActor.run { CaptureFlowViewModel() }

        await MainActor.run {
            viewModel.submissionDraft.siteName = "Packaging line"
            viewModel.submissionDraft.taskStatement = "Capture the box handoff zone."
            viewModel.submissionDraft.workflowContext = "Operators seal cartons and place them on a conveyor."
            viewModel.submissionDraft.taskZoneBoundaryNotes = "From sealer exit to outbound belt."
            viewModel.currentAddress = "123 Factory Way, Durham, NC"
            viewModel.captureChecklist = viewModel.captureChecklist.map {
                var item = $0
                item.isCompleted = true
                return item
            }
            viewModel.evidenceCoverageDeclarations = viewModel.evidenceCoverageDeclarations.map {
                var item = $0
                item.isCovered = true
                return item
            }
            viewModel.beginCapture()
        }

        let step = await MainActor.run { viewModel.step }
        let activeContext = await MainActor.run { viewModel.activeCaptureContext }

        #expect(step == .readyToCapture)
        #expect(activeContext?.capturePass.captureMode == .phone)
        #expect(activeContext?.siteLocation == "123 Factory Way, Durham, NC")
    }

    @Test func workflowBlocksCaptureWhenChecklistIncomplete() async throws {
        let viewModel = await MainActor.run { CaptureFlowViewModel() }

        await MainActor.run {
            viewModel.submissionDraft.siteName = "Packaging line"
            viewModel.submissionDraft.taskStatement = "Capture the box handoff zone."
            viewModel.submissionDraft.workflowContext = "Operators seal cartons and place them on a conveyor."
            viewModel.submissionDraft.taskZoneBoundaryNotes = "From sealer exit to outbound belt."
            viewModel.currentAddress = "123 Factory Way, Durham, NC"
            viewModel.evidenceCoverageDeclarations = viewModel.evidenceCoverageDeclarations.map {
                var item = $0
                item.isCovered = true
                return item
            }
            viewModel.beginCapture()
        }

        let step = await MainActor.run { viewModel.step }
        let activeContext = await MainActor.run { viewModel.activeCaptureContext }

        #expect(step != .readyToCapture)
        #expect(activeContext == nil)
    }
}
