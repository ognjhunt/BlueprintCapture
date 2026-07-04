import Testing
import Foundation
@testable import BlueprintCapture

// CAP-06: regression guards for the SHIPPING capture→upload wiring.
//
// The redesign shipping path is: BPHomeTab (real ScanHomeViewModel discovery) →
// reserve a job → RedesignCoordinator.startCapture(seed:) → BPRootView presents
// AnywhereCaptureFlowView(seed:) → CaptureFlowViewModel(flowMode: .spaceReview(seed))
// → handleRecordingFinished(...) → CaptureUploadService.enqueue.
//
// These tests exercise that real engine seam (not the old UITestRootView/MainTabView
// tree the rest of the suite covers) and assert the two invariants that were broken
// before remediation:
//   - CAP-01/CAP-04: a reserved job's capture_job_id must thread into the upload
//     metadata (the shipping flow used to produce no capture_job_id at all).
//   - CAP-03: creatorId must be the Firebase auth uid via resolvedUserId(), never a
//     random profile UUID (which the Storage/Firestore rules would deny).
@Suite struct CaptureFlowShippingWiringTests {

    @MainActor
    private func makeViewModel(seed: SpaceReviewSeed, upload: MockCaptureUploadService) -> CaptureFlowViewModel {
        // handleRecordingFinished only builds + stores pendingCaptureRequest, so the
        // default target/intake/export services are fine; only the upload service is
        // overridden with the module-visible mock.
        CaptureFlowViewModel(
            flowMode: .spaceReview(seed: seed),
            uploadService: upload
        )
    }

    @MainActor
    private func makeArtifacts() throws -> VideoCaptureManager.RecordingArtifacts {
        let baseDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cap06-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        return VideoCaptureManager.RecordingArtifacts(
            baseFilename: "test",
            directoryURL: baseDir,
            videoURL: baseDir.appendingPathComponent("walkthrough.mov"),
            motionLogURL: baseDir.appendingPathComponent("motion.jsonl"),
            manifestURL: baseDir.appendingPathComponent("manifest.json"),
            arKit: nil,
            packageURL: baseDir,
            startedAt: Date()
        )
    }

    @Test @MainActor
    func reservedJobCapture_threadsCaptureJobId_andUsesResolvedCreatorId() throws {
        let seed = SpaceReviewSeed(
            id: "job_test_123",
            title: "Test Warehouse",
            address: "1 Test Way",
            payoutRange: 20...40,
            captureJobId: "job_test_123",
            buyerRequestId: "buyer_req_9",
            siteSubmissionId: "site_sub_9",
            regionId: nil,
            rightsProfile: nil,
            requestedOutputs: CaptureRequestedOutputs.robotEvaluation,
            suggestedContext: nil,
            intakePacket: nil,
            captureRights: nil,
            requestedCaptureMode: nil
        )
        let upload = MockCaptureUploadService()
        let viewModel = makeViewModel(seed: seed, upload: upload)
        let artifacts = try makeArtifacts()

        viewModel.handleRecordingFinished(artifacts: artifacts, targetId: "job_test_123", reservationId: nil)

        let request = try #require(viewModel.pendingCaptureRequest)
        // CAP-01/CAP-04: the reserved capture_job_id threads into the upload metadata.
        #expect(request.metadata.captureJobId == "job_test_123")
        #expect(request.metadata.siteSubmissionId == "site_sub_9")
        #expect(request.metadata.buyerRequestId == "buyer_req_9")
        // CAP-03: creatorId is the auth uid (resolvedUserId), NOT a random profile UUID.
        #expect(request.metadata.creatorId == UserDeviceService.resolvedUserId())
        #expect(!request.metadata.creatorId.isEmpty)
    }

    @Test @MainActor
    func capture_creatorId_isNeverTheRandomProfileUUID() throws {
        let seed = SpaceReviewSeed(
            id: "job_open",
            title: "Open Capture",
            address: nil,
            payoutRange: nil,
            captureJobId: nil,
            buyerRequestId: nil,
            siteSubmissionId: nil,
            regionId: nil,
            rightsProfile: nil,
            requestedOutputs: CaptureRequestedOutputs.reviewIntake,
            suggestedContext: nil,
            intakePacket: nil,
            captureRights: nil,
            requestedCaptureMode: nil
        )
        let viewModel = makeViewModel(seed: seed, upload: MockCaptureUploadService())
        let artifacts = try makeArtifacts()

        viewModel.handleRecordingFinished(artifacts: artifacts, targetId: nil, reservationId: nil)

        let request = try #require(viewModel.pendingCaptureRequest)
        // The pre-remediation bug stamped profile.id.uuidString (a fresh random UUID
        // per instance) that the security rules reject. Guard that it is the resolved
        // user id and not a stray UUID unrelated to the account.
        #expect(request.metadata.creatorId == UserDeviceService.resolvedUserId())
    }
}
