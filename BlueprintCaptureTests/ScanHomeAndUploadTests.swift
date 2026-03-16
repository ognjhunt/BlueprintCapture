import Foundation
import CoreLocation
import Combine
import Testing
@testable import BlueprintCapture

struct ScanHomeAndUploadTests {

    @Test @MainActor func scanHome_filtersJobsByTargetStateOwnershipAndCompletion() async throws {
        let currentUserId = "user_current"

        let jobA = makeJob(id: "a", title: "A", address: "A", lat: 0, lng: 0, updatedAt: Date())
        let jobB = makeJob(id: "b", title: "B", address: "B", lat: 0, lng: 0, updatedAt: Date())
        let jobC = makeJob(id: "c", title: "C", address: "C", lat: 0, lng: 0, updatedAt: Date())
        let jobD = makeJob(id: "d", title: "D", address: "D", lat: 0, lng: 0, updatedAt: Date())
        let jobE = makeJob(id: "e", title: "E", address: "E", lat: 0, lng: 0, updatedAt: Date())

        let ranked: [ScanHomeViewModel.RankedJob] = [
            .init(job: jobA, distanceMeters: 10),
            .init(job: jobB, distanceMeters: 20),
            .init(job: jobC, distanceMeters: 30),
            .init(job: jobD, distanceMeters: 40),
            .init(job: jobE, distanceMeters: 50)
        ]

        let states: [String: TargetState] = [
            "a": TargetState(status: .completed, reservedBy: nil, reservedUntil: nil, checkedInBy: nil, completedAt: Date(), lat: nil, lng: nil, geohash: nil, updatedAt: Date()),
            "b": TargetState(status: .reserved, reservedBy: "someone_else", reservedUntil: Date().addingTimeInterval(3600), checkedInBy: nil, completedAt: nil, lat: nil, lng: nil, geohash: nil, updatedAt: Date()),
            "c": TargetState(status: .reserved, reservedBy: currentUserId, reservedUntil: Date().addingTimeInterval(3600), checkedInBy: nil, completedAt: nil, lat: nil, lng: nil, geohash: nil, updatedAt: Date()),
            "d": TargetState(status: .in_progress, reservedBy: currentUserId, reservedUntil: Date().addingTimeInterval(3600), checkedInBy: currentUserId, completedAt: nil, lat: nil, lng: nil, geohash: nil, updatedAt: Date()),
            "e": TargetState(status: .reserved, reservedBy: nil, reservedUntil: Date().addingTimeInterval(3600), checkedInBy: nil, completedAt: nil, lat: nil, lng: nil, geohash: nil, updatedAt: Date())
        ]

        let visible = ScanHomeViewModel.filterVisibleItems(rankedJobs: ranked, statesByJobId: states, currentUserId: currentUserId)
        let visibleIds = Set(visible.map(\.job.id))

        #expect(!visibleIds.contains("a"))
        #expect(!visibleIds.contains("b"))
        #expect(visibleIds.contains("c"))
        #expect(visibleIds.contains("d"))
        #expect(!visibleIds.contains("e"))
    }

    @Test @MainActor func scanHome_ranksReadyNowFirst() async throws {
        let user = CLLocation(latitude: 0, longitude: 0)
        let now = Date()

        let ready = makeJob(id: "ready", title: "Ready", address: "R", lat: 0, lng: 0, updatedAt: now)
        let far = makeJob(id: "far", title: "Far", address: "F", lat: 0.01, lng: 0.0, payoutCents: 999999, priority: 10, updatedAt: now)

        let ranked = ScanHomeViewModel.rankJobsForFeed(jobs: [far, ready], userLocation: user, feedRadiusMeters: 10 * 1609.34)
        #expect(ranked.first?.job.id == "ready")
    }

    @Test @MainActor func scanHome_derivesPermissionTierFromRightsSignals() async throws {
        let now = Date()

        let approved = makeJob(id: "approved", title: "Approved", address: "A", lat: 0, lng: 0, updatedAt: now)
        let review = ScanJob(
            id: "review",
            title: "Review",
            address: "B",
            lat: 0,
            lng: 0,
            payoutCents: 1000,
            estMinutes: 10,
            active: true,
            updatedAt: now,
            thumbnailURL: nil,
            heroImageURL: nil,
            category: nil,
            instructions: [],
            allowedAreas: [],
            restrictedAreas: [],
            permissionDocURL: nil,
            checkinRadiusM: 150,
            alertRadiusM: 200,
            priority: 0,
            priorityWeight: 1.0,
            regionId: nil,
            jobType: .operatorApprovedOnDemand,
            buyerRequestId: nil,
            siteSubmissionId: nil,
            quotedPayoutCents: nil,
            dueWindow: nil,
            approvalRequirements: [],
            recaptureReason: nil,
            rightsChecklist: [],
            rightsProfile: "review_required",
            requestedOutputs: [],
            workflowName: nil,
            workflowSteps: [],
            targetKPI: nil,
            zone: nil,
            shift: nil,
            owner: nil,
            facilityTemplate: nil,
            benchmarkStations: [],
            lightingWindows: [],
            movableObstacles: [],
            floorConditionNotes: [],
            reflectiveSurfaceNotes: [],
            accessRules: [],
            adjacentSystems: [],
            privacyRestrictions: [],
            securityRestrictions: [],
            knownBlockers: [],
            nonRoutineModes: [],
            peopleTrafficNotes: [],
            captureRestrictions: []
        )
        let permission = ScanJob(
            id: "permission",
            title: "Permission",
            address: "C",
            lat: 0,
            lng: 0,
            payoutCents: 1000,
            estMinutes: 10,
            active: true,
            updatedAt: now,
            thumbnailURL: nil,
            heroImageURL: nil,
            category: nil,
            instructions: [],
            allowedAreas: ["Lobby"],
            restrictedAreas: ["Office"],
            permissionDocURL: nil,
            checkinRadiusM: 150,
            alertRadiusM: 200,
            priority: 0,
            priorityWeight: 1.0,
            regionId: nil,
            jobType: .curatedNearby,
            buyerRequestId: nil,
            siteSubmissionId: nil,
            quotedPayoutCents: nil,
            dueWindow: nil,
            approvalRequirements: [],
            recaptureReason: nil,
            rightsChecklist: ["Manager approval"],
            rightsProfile: "policy_only",
            requestedOutputs: [],
            workflowName: nil,
            workflowSteps: [],
            targetKPI: nil,
            zone: nil,
            shift: nil,
            owner: nil,
            facilityTemplate: nil,
            benchmarkStations: [],
            lightingWindows: [],
            movableObstacles: [],
            floorConditionNotes: [],
            reflectiveSurfaceNotes: [],
            accessRules: [],
            adjacentSystems: [],
            privacyRestrictions: [],
            securityRestrictions: [],
            knownBlockers: [],
            nonRoutineModes: [],
            peopleTrafficNotes: [],
            captureRestrictions: []
        )
        let blocked = ScanJob(
            id: "blocked",
            title: "Blocked",
            address: "D",
            lat: 0,
            lng: 0,
            payoutCents: 1000,
            estMinutes: 10,
            active: true,
            updatedAt: now,
            thumbnailURL: nil,
            heroImageURL: nil,
            category: nil,
            instructions: [],
            allowedAreas: [],
            restrictedAreas: ["No capture beyond gate"],
            permissionDocURL: nil,
            checkinRadiusM: 150,
            alertRadiusM: 200,
            priority: 0,
            priorityWeight: 1.0,
            regionId: nil,
            jobType: .curatedNearby,
            buyerRequestId: nil,
            siteSubmissionId: nil,
            quotedPayoutCents: nil,
            dueWindow: nil,
            approvalRequirements: ["strictly prohibited"],
            recaptureReason: nil,
            rightsChecklist: [],
            rightsProfile: "blocked",
            requestedOutputs: [],
            workflowName: nil,
            workflowSteps: [],
            targetKPI: nil,
            zone: nil,
            shift: nil,
            owner: nil,
            facilityTemplate: nil,
            benchmarkStations: [],
            lightingWindows: [],
            movableObstacles: [],
            floorConditionNotes: [],
            reflectiveSurfaceNotes: [],
            accessRules: [],
            adjacentSystems: [],
            privacyRestrictions: [],
            securityRestrictions: [],
            knownBlockers: [],
            nonRoutineModes: [],
            peopleTrafficNotes: [],
            captureRestrictions: []
        )

        #expect(ScanHomeViewModel.permissionTier(for: approved) == .approved)
        #expect(ScanHomeViewModel.permissionTier(for: review) == .reviewRequired)
        #expect(ScanHomeViewModel.permissionTier(for: permission) == .permissionRequired)
        #expect(ScanHomeViewModel.permissionTier(for: blocked) == .blocked)
    }

    @Test @MainActor func scanHome_prefersExplicitImageThenStreetViewThenMapFallback() async throws {
        let now = Date()
        let explicit = makeJob(id: "explicit", title: "Explicit", address: "A", lat: 0, lng: 0, updatedAt: now)
        let streetOnly = ScanJob(
            id: "street",
            title: "Street",
            address: "B",
            lat: 0,
            lng: 0,
            payoutCents: 1000,
            estMinutes: 10,
            active: true,
            updatedAt: now,
            thumbnailURL: nil,
            heroImageURL: nil,
            category: nil,
            instructions: [],
            allowedAreas: [],
            restrictedAreas: [],
            permissionDocURL: nil,
            checkinRadiusM: 150,
            alertRadiusM: 200,
            priority: 0,
            priorityWeight: 1.0,
            regionId: nil,
            jobType: .curatedNearby,
            buyerRequestId: nil,
            siteSubmissionId: nil,
            quotedPayoutCents: nil,
            dueWindow: nil,
            approvalRequirements: [],
            recaptureReason: nil,
            rightsChecklist: [],
            rightsProfile: nil,
            requestedOutputs: [],
            workflowName: nil,
            workflowSteps: [],
            targetKPI: nil,
            zone: nil,
            shift: nil,
            owner: nil,
            facilityTemplate: nil,
            benchmarkStations: [],
            lightingWindows: [],
            movableObstacles: [],
            floorConditionNotes: [],
            reflectiveSurfaceNotes: [],
            accessRules: [],
            adjacentSystems: [],
            privacyRestrictions: [],
            securityRestrictions: [],
            knownBlockers: [],
            nonRoutineModes: [],
            peopleTrafficNotes: [],
            captureRestrictions: []
        )

        let explicitSelection = ScanHomeViewModel.previewSelection(for: explicit)
        let mapSelection = ScanHomeViewModel.previewSelection(for: streetOnly)

        #expect(explicitSelection.source == .jobImage)
        #expect(explicitSelection.url == explicit.primaryImageURL)
        #expect(mapSelection.source == .mapSnapshot)
        #expect(mapSelection.url == nil)
    }

    @Test @MainActor func scanHome_placesReviewSubmissionAfterLiveSections() async throws {
        let sections = ScanHomeViewModel.homeSectionKinds(
            hasReadyNearby: true,
            nearbyCount: 3,
            specialCount: 2,
            submissionCount: 1
        )

        #expect(sections.last == .reviewSubmission)
        #expect(sections == [.readyNearby, .nearby, .special, .submissions, .reviewSubmission])
    }

    @Test @MainActor func uploadQueue_enqueuesGlassesCaptureAndCompletesTargetOnUploadCompletion() async throws {
        let upload = MockCaptureUploadService()
        let targets = MockTargetStateService()
        let store = UploadQueueStore(fileURL: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("upload-queue-tests-\(UUID().uuidString).json"))

        let vm = UploadQueueViewModel(uploadService: upload, targetStateService: targets, store: store)

        let baseDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("glasses-artifacts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)

        let artifacts = GlassesCaptureManager.CaptureArtifacts(
            baseFilename: "test",
            directoryURL: baseDir,
            videoURL: baseDir.appendingPathComponent("walkthrough.mov"),
            framesDirectoryURL: baseDir.appendingPathComponent("frames", isDirectory: true),
            motionLogURL: baseDir.appendingPathComponent("motion.jsonl"),
            manifestURL: baseDir.appendingPathComponent("manifest.json"),
            packageURL: baseDir,
            startedAt: Date(),
            endedAt: Date(),
            frameCount: 10,
            durationSeconds: 3.0
        )

        let job = makeJob(id: "job_123", title: "Job", address: "Addr", lat: 0, lng: 0, payoutCents: 5000, updatedAt: Date())

        vm.enqueueGlassesCapture(artifacts: artifacts, job: job)
        #expect(upload.enqueued.count == 1)
        #expect(upload.enqueued.first?.metadata.targetId == "job_123")
        #expect(upload.enqueued.first?.metadata.jobId == "job_123")
        #expect(upload.enqueued.first?.metadata.captureSource == .metaGlasses)
        #expect(upload.enqueued.first?.metadata.sceneMemory?.inaccessibleAreas == ["Back office"])
        #expect(upload.enqueued.first?.metadata.captureRights?.consentStatus == .documented)
        #expect(upload.enqueued.first?.metadata.captureRights?.permissionDocumentURI == "https://example.com/permit.pdf")
        #expect(upload.enqueued.first?.metadata.captureRights?.consentScope == ["Sales floor"])
        #expect(upload.enqueued.first?.metadata.captureRights?.payoutEligible == true)

        // Simulate successful upload completion.
        if let req = upload.enqueued.first {
            upload.subject.send(.completed(req))
        }

        // Wait briefly for the async complete() Task to run.
        for _ in 0..<20 {
            if targets.completedTargetIds.contains("job_123") { break }
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        #expect(targets.completedTargetIds.contains("job_123"))
    }
}

private func makeJob(
    id: String,
    title: String,
    address: String,
    lat: Double,
    lng: Double,
    payoutCents: Int = 1000,
    priority: Int = 0,
    updatedAt: Date
) -> ScanJob {
    ScanJob(
        id: id,
        title: title,
        address: address,
        lat: lat,
        lng: lng,
        payoutCents: payoutCents,
        estMinutes: 10,
        active: true,
        updatedAt: updatedAt,
        thumbnailURL: URL(string: "https://example.com/thumb.png"),
        heroImageURL: URL(string: "https://example.com/hero.png"),
        category: nil,
        instructions: [],
        allowedAreas: ["Sales floor"],
        restrictedAreas: ["Back office"],
        permissionDocURL: URL(string: "https://example.com/permit.pdf"),
        checkinRadiusM: 150,
        alertRadiusM: 200,
        priority: priority,
        priorityWeight: 1.0,
        regionId: "bay-area",
        jobType: .buyerRequestedSpecialTask,
        buyerRequestId: "req-\(id)",
        siteSubmissionId: id,
        quotedPayoutCents: payoutCents,
        dueWindow: "managed",
        approvalRequirements: ["ops_review"],
        recaptureReason: nil,
        rightsChecklist: ["permission doc"],
        rightsProfile: "documented_permission",
        requestedOutputs: ["qualification", "preview_simulation"],
        workflowName: nil,
        workflowSteps: [],
        targetKPI: nil,
        zone: nil,
        shift: nil,
        owner: nil,
        facilityTemplate: nil,
        benchmarkStations: [],
        lightingWindows: [],
        movableObstacles: [],
        floorConditionNotes: [],
        reflectiveSurfaceNotes: [],
        accessRules: [],
        adjacentSystems: [],
        privacyRestrictions: [],
        securityRestrictions: [],
        knownBlockers: [],
        nonRoutineModes: [],
        peopleTrafficNotes: [],
        captureRestrictions: []
    )
}

// MARK: - Mocks

final class MockCaptureUploadService: CaptureUploadServiceProtocol {
    let subject = PassthroughSubject<CaptureUploadService.Event, Never>()
    private(set) var enqueued: [CaptureUploadRequest] = []

    var events: AnyPublisher<CaptureUploadService.Event, Never> { subject.eraseToAnyPublisher() }

    func enqueue(_ request: CaptureUploadRequest) {
        enqueued.append(request)
        subject.send(.queued(request))
    }

    func retryUpload(id: UUID) {}
    func cancelUpload(id: UUID) {}
}

@MainActor
final class MockTargetStateService: TargetStateServiceProtocol {
    private(set) var completedTargetIds: [String] = []

    func batchFetchStates(for targetIds: [String]) async -> [String : TargetState] { [:] }

    func observeState(for targetId: String, onChange: @escaping (TargetState?) -> Void) -> TargetStateObservation {
        TargetStateObservation {}
    }

    func reserve(target: Target, for duration: TimeInterval) async throws -> Reservation {
        Reservation(targetId: target.id, reservedUntil: Date().addingTimeInterval(duration))
    }

    func cancelReservation(for targetId: String) async {}
    func checkIn(targetId: String) async throws {}

    func complete(targetId: String) async throws {
        completedTargetIds.append(targetId)
    }

    func fetchActiveReservationForCurrentUser() async -> Reservation? { nil }
}
