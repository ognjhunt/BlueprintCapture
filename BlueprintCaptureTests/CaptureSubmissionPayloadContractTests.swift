import Foundation
import Testing
@testable import BlueprintCapture

/// Serialization-parity guard for the `capture_submissions` client contract.
///
/// `firestore.rules` rejects any create/update whose payload contains a key
/// outside `captureSubmissionClientCreateKeys()`. These tests prove the iOS
/// builders can only emit permitted keys and permitted state values, so a
/// drift fails in CI instead of failing every capture registration in the
/// field. The rules side of the same contract is covered by the emulator
/// suite in `cloud/firestore-rules-tests`; the Android side by
/// `CaptureSubmissionPayloadTest`.
struct CaptureSubmissionPayloadContractTests {

    /// Mirror of `captureSubmissionClientCreateKeys()` in `firestore.rules`.
    private static let clientCreateKeys: Set<String> = [
        "capture_id",
        "scene_id",
        "creator_id",
        "job_id",
        "capture_source",
        "status",
        "requested_outputs",
        "has_site_identity",
        "has_capture_topology",
        "created_at",
        "submitted_at",
        "capture_job_id",
        "buyer_request_id",
        "site_submission_id",
        "region_id",
        "estimated_payout_cents",
        "rights_profile",
        "target_address",
        "site_identity",
        "city_context",
        "target_context",
        "raw_prefix",
        "operational_state",
        "lifecycle",
        "upload_error"
    ]

    /// Mirror of `captureSubmissionClientStatuses()` in `firestore.rules`.
    private static let clientStatuses: Set<String> = [
        "submitted",
        "upload_failed",
        "raw_validation_failed",
        "local_preflight_failed"
    ]

    /// Mirror of `captureSubmissionClientQaStates()` in `firestore.rules`.
    private static let clientQaStates: Set<String> = [
        "queued",
        "not_started",
        "blocked_raw_validation",
        "blocked_local_storage",
        "blocked_local_capture_limits"
    ]

    private static let forbiddenKeys: Set<String> = [
        "payout_cents",
        "paid_at",
        "stats",
        "world_model_candidate",
        "capture_start_epoch_ms",
        "capture_duration_ms",
        "motion_sample_count",
        "motion_provenance",
        "priority_weight",
        "reservation_id",
        "imu_samples_available"
    ]

    private func makeRequest(withSiteIdentity: Bool) -> CaptureUploadRequest {
        let metadata = CaptureUploadMetadata(
            id: UUID(),
            targetId: "scene-123",
            reservationId: "reservation-9",
            jobId: "scene-123",
            captureJobId: "capture-job-scene-123",
            buyerRequestId: "req-scene-123",
            siteSubmissionId: "site-submission-scene-123",
            regionId: "durham-nc",
            creatorId: "tester",
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            uploadedAt: nil,
            captureSource: .iphoneVideo,
            specialTaskType: .buyerRequested,
            priorityWeight: 1.25,
            quotedPayoutCents: 4500,
            rightsProfile: "documented_permission",
            requestedOutputs: ["qualification"],
            intakePacket: QualificationIntakePacket(
                workflowName: "Inbound walk",
                taskSteps: ["Enter aisle", "Walk route"],
                zone: "Aisle 4"
            ),
            intakeMetadata: nil,
            taskHypothesis: nil,
            scaffoldingPacket: nil,
            captureModality: "iphone_arkit_lidar",
            evidenceTier: nil,
            captureContextHint: "Target scene",
            sceneMemory: nil,
            captureRights: nil,
            siteIdentity: withSiteIdentity
                ? SiteIdentity(
                    siteId: "site-1",
                    siteIdSource: "site_submission",
                    placeId: nil,
                    siteName: "Main St Hardware",
                    addressFull: "123 Main St, Durham, NC",
                    geo: nil,
                    buildingId: nil,
                    floorId: nil,
                    roomId: nil,
                    zoneId: nil
                )
                : nil,
            captureTopology: nil,
            captureMode: nil
        )
        let packageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("capture-parity-\(UUID().uuidString)", isDirectory: true)
        return CaptureUploadRequest(packageURL: packageURL, metadata: metadata)
    }

    private func assertWithinContract(_ payload: [String: Any]) {
        let keys = Set(payload.keys)
        let extras = keys.subtracting(Self.clientCreateKeys)
        #expect(extras.isEmpty, "Payload contains keys the security rules reject: \(extras)")
        #expect(keys.intersection(Self.forbiddenKeys).isEmpty)

        if let status = payload["status"] as? String {
            #expect(Self.clientStatuses.contains(status))
        }
        if let operationalState = payload["operational_state"] as? [String: Any] {
            let allowedStateKeys: Set<String> = [
                "assignment_state", "upload_state", "qa_state", "qa_outcome", "repeat_ready"
            ]
            #expect(Set(operationalState.keys).subtracting(allowedStateKeys).isEmpty)
            if let qaState = operationalState["qa_state"] as? String {
                #expect(Self.clientQaStates.contains(qaState))
            }
            if let qaOutcome = operationalState["qa_outcome"] {
                #expect(qaOutcome is NSNull, "Clients may never author a QA outcome")
            }
        }
        if let lifecycle = payload["lifecycle"] as? [String: Any] {
            let allowedLifecycleKeys: Set<String> = [
                "capture_started_at", "upload_started_at", "capture_uploaded_at", "upload_failed_at"
            ]
            #expect(Set(lifecycle.keys).subtracting(allowedLifecycleKeys).isEmpty)
        }
        if let uploadError = payload["upload_error"] as? [String: Any] {
            #expect(Set(uploadError.keys).subtracting(["code", "message", "recorded_at"]).isEmpty)
        }
    }

    @Test
    func submissionPayloadStaysWithinRulesContract() {
        let service = CaptureUploadService()
        for withSiteIdentity in [true, false] {
            let request = makeRequest(withSiteIdentity: withSiteIdentity)
            for (start, completion, submittedAt, uploadState) in [
                (true, false, false, "uploading"),
                (false, true, true, "uploaded")
            ] {
                let payload = service.captureSubmissionPayload(
                    for: request,
                    recordedAt: Date(),
                    uploadState: uploadState,
                    includeUploadStart: start,
                    includeUploadCompletion: completion,
                    includeSubmittedAt: submittedAt
                )
                assertWithinContract(payload)
                #expect(payload["status"] as? String == "submitted")
            }
        }
    }

    @Test
    func failurePayloadsStayWithinRulesContractForEveryUploadError() {
        let service = CaptureUploadService()
        let request = makeRequest(withSiteIdentity: true)
        let errors: [CaptureUploadService.UploadError] = [
            .fileMissing,
            .uploadFailed,
            .authenticationRequired,
            .missingStructuredIntake,
            .rawContractValidationFailed,
            .insufficientDiskSpace,
            .uploadLimitExceeded(reasons: ["duration"]),
            .captureLifecycleRegistrationFailed,
            .submissionRegistrationFailed,
            .invalidBundle(reasons: ["missing manifest"])
        ]
        for error in errors {
            guard error.shouldRecordLifecycleFailure else { continue }
            let payload = service.uploadFailurePayload(
                for: request,
                error: error,
                recordedAt: Date()
            )
            assertWithinContract(payload)
            #expect(Self.clientStatuses.contains(error.lifecycleStatus))
            #expect(Self.clientQaStates.contains(error.lifecycleQaState))
        }
    }
}
