import Foundation
import Combine

@MainActor
final class UploadQueueViewModel: ObservableObject {
    @Published private(set) var uploadStatuses: [UploadStatus] = []

    private let uploadService: CaptureUploadServiceProtocol
    private let targetStateService: TargetStateServiceProtocol
    private let store: UploadQueueStore
    private let exportService: CaptureExportServiceProtocol

    private var uploadStatusMap: [UUID: UploadStatus] = [:]
    private var cancellables: Set<AnyCancellable> = []

    init(uploadService: CaptureUploadServiceProtocol = CaptureUploadService(),
         targetStateService: TargetStateServiceProtocol = TargetStateService(),
         store: UploadQueueStore = UploadQueueStore(),
         exportService: CaptureExportServiceProtocol = CaptureExportService()) {
        self.uploadService = uploadService
        self.targetStateService = targetStateService
        self.store = store
        self.exportService = exportService

        observeUploadEvents()
        restorePending()
    }

    // MARK: - Public API

    func enqueue(_ request: CaptureUploadRequest, targetName: String?, estimatedPayoutRange: ClosedRange<Int>?) {
        let id = request.metadata.id
        uploadStatusMap[id] = UploadStatus(
            metadata: request.metadata,
            packageURL: request.packageURL,
            state: .queued,
            targetName: targetName,
            estimatedPayoutRange: estimatedPayoutRange
        )
        persist()
        refreshUploadStatuses()
        uploadService.enqueue(request)
    }

    func enqueueGlassesCapture(artifacts: GlassesCaptureManager.CaptureArtifacts, job: ScanJob) {
        let payoutEligible = job.payoutCents > 0
        let metadata = CaptureUploadMetadata(
            id: UUID(),
            targetId: job.id,
            reservationId: nil,
            jobId: job.id,
            captureJobId: job.id,
            buyerRequestId: job.buyerRequestId,
            siteSubmissionId: job.siteSubmissionId ?? job.id,
            regionId: job.regionId,
            creatorId: UserDeviceService.resolvedUserId(),
            capturedAt: artifacts.startedAt,
            uploadedAt: nil,
            captureSource: .metaGlasses,
            specialTaskType: job.captureSpecialTaskType,
            priorityWeight: job.priorityWeight,
            quotedPayoutCents: job.quotedPayoutCents ?? job.payoutCents,
            rightsProfile: job.rightsProfile,
            requestedOutputs: job.requestedOutputs,
            intakePacket: job.qualificationIntakePacket,
            intakeMetadata: CaptureIntakeMetadata(source: .authoritative),
            taskHypothesis: nil,
            scaffoldingPacket: job.defaultScaffoldingPacket,
            captureModality: "glasses_video_only",
            evidenceTier: "pre_screen_video",
            captureContextHint: "\(job.title) at \(job.address)",
            sceneMemory: SceneMemoryCaptureMetadata(
                continuityScore: nil,
                lightingConsistency: "unknown",
                dynamicObjectDensity: "unknown",
                operatorNotes: [],
                inaccessibleAreas: job.inaccessibleAreasForCapture
            ),
            captureRights: CaptureRightsMetadata(
                derivedSceneGenerationAllowed: false,
                dataLicensingAllowed: false,
                payoutEligible: payoutEligible,
                consentStatus: job.captureConsentStatus,
                permissionDocumentURI: job.permissionDocURL?.absoluteString,
                consentScope: job.allowedAreas,
                consentNotes: []
            )
        )
        let request = CaptureUploadRequest(packageURL: artifacts.packageURL, metadata: metadata)
        let payoutUsd = job.payoutDollars
        enqueue(request, targetName: job.title, estimatedPayoutRange: payoutUsd...payoutUsd)
    }

    func retryUpload(id: UUID) {
        uploadService.retryUpload(id: id)
    }

    func exportCapture(id: UUID) async throws -> FinalizedCaptureBundle {
        guard let status = uploadStatusMap[id] else {
            throw CaptureBundleFinalizer.FinalizationError.packageMissing
        }
        let request = CaptureUploadRequest(packageURL: status.packageURL, metadata: status.metadata)
        return try await exportService.exportCapture(request: request)
    }

    func simulateUITestUpload(for job: ScanJob) {
        let now = Date()
        let metadata = CaptureUploadMetadata(
            id: UUID(),
            targetId: job.id,
            reservationId: nil,
            jobId: job.id,
            captureJobId: job.id,
            buyerRequestId: job.buyerRequestId,
            siteSubmissionId: job.siteSubmissionId ?? job.id,
            regionId: job.regionId,
            creatorId: UserDeviceService.resolvedUserId(),
            capturedAt: now,
            uploadedAt: nil,
            captureSource: .metaGlasses,
            specialTaskType: job.captureSpecialTaskType,
            priorityWeight: job.priorityWeight,
            quotedPayoutCents: job.quotedPayoutCents ?? job.payoutCents,
            rightsProfile: job.rightsProfile,
            requestedOutputs: job.requestedOutputs,
            intakePacket: job.qualificationIntakePacket,
            intakeMetadata: CaptureIntakeMetadata(source: .authoritative),
            taskHypothesis: nil,
            scaffoldingPacket: job.defaultScaffoldingPacket,
            captureModality: "glasses_video_only",
            evidenceTier: "pre_screen_video",
            captureContextHint: "\(job.title) at \(job.address)",
            sceneMemory: SceneMemoryCaptureMetadata(),
            captureRights: CaptureRightsMetadata(
                derivedSceneGenerationAllowed: false,
                dataLicensingAllowed: false,
                payoutEligible: true,
                consentStatus: .policyOnly,
                permissionDocumentURI: job.permissionDocURL?.absoluteString,
                consentScope: job.allowedAreas,
                consentNotes: ["UI test simulated upload"]
            )
        )

        let status = UploadStatus(
            metadata: metadata,
            packageURL: FileManager.default.temporaryDirectory.appendingPathComponent("ui-test-\(metadata.id.uuidString)", isDirectory: true),
            state: .uploading(progress: 0.42),
            targetName: job.title,
            estimatedPayoutRange: job.payoutDollars...job.payoutDollars
        )
        uploadStatusMap[metadata.id] = status
        refreshUploadStatuses()

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 750_000_000)
            guard let self, var updated = self.uploadStatusMap[metadata.id] else { return }
            updated.state = .completed
            self.uploadStatusMap[metadata.id] = updated
            self.refreshUploadStatuses()
        }
    }

    func dismissUpload(id: UUID) {
        uploadStatusMap.removeValue(forKey: id)
        persist()
        refreshUploadStatuses()
    }

    // MARK: - Restore / Persist

    private func restorePending() {
        let records = store.load()
        guard !records.isEmpty else { return }

        for r in records {
            let url = URL(fileURLWithPath: r.packagePath)
            let request = CaptureUploadRequest(packageURL: url, metadata: r.metadata)
            uploadStatusMap[r.id] = UploadStatus(
                metadata: r.metadata,
                packageURL: url,
                state: .queued,
                targetName: r.targetName,
                estimatedPayoutRange: r.estimatedPayoutRange
            )
            uploadService.enqueue(request)
        }
        refreshUploadStatuses()
    }

    private func persist() {
        let records: [PendingUploadRecord] = uploadStatusMap.values.map { status in
            PendingUploadRecord(
                id: status.metadata.id,
                packagePath: status.packageURL.path,
                metadata: status.metadata,
                targetName: status.targetName,
                estimatedPayoutRange: status.estimatedPayoutRange
            )
        }
        store.save(records)
    }

    // MARK: - Upload Events

    private func observeUploadEvents() {
        uploadService.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleUpload(event)
            }
            .store(in: &cancellables)
    }

    private func handleUpload(_ event: CaptureUploadService.Event) {
        switch event {
        case .queued(let request):
            let id = request.metadata.id
            if uploadStatusMap[id] == nil {
                uploadStatusMap[id] = UploadStatus(
                    metadata: request.metadata,
                    packageURL: request.packageURL,
                    state: .queued,
                    targetName: nil,
                    estimatedPayoutRange: nil
                )
            }

        case .progress(let id, let progress):
            guard var status = uploadStatusMap[id] else { break }
            status.state = .uploading(progress: progress)
            uploadStatusMap[id] = status

        case .completed(let request):
            let id = request.metadata.id
            guard var status = uploadStatusMap[id] else { break }
            status.metadata = request.metadata
            status.state = .completed
            uploadStatusMap[id] = status

            // Mark target as completed so it disappears from future job feeds.
            if let targetId = request.metadata.targetId, !targetId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Task { [weak self] in
                    guard let self else { return }
                    do { try await self.targetStateService.complete(targetId: targetId) }
                    catch { print("⚠️ [UploadQueue] Failed to mark completed targetId=\(targetId): \(error.localizedDescription)") }
                }
            }

            // Remove from persistence once uploaded.
            persistRemove(id: id)

        case .failed(let request, let error):
            let id = request.metadata.id
            guard var status = uploadStatusMap[id] else { break }
            status.metadata = request.metadata
            status.state = .failed(message: error.errorDescription ?? "Upload failed")
            uploadStatusMap[id] = status

            // If the file is missing, don't keep retrying across launches.
            if error == .fileMissing {
                persistRemove(id: id)
            } else {
                persist()
            }
        }

        refreshUploadStatuses()
    }

    private func persistRemove(id: UUID) {
        // Keep UI status around until user dismisses, but stop re-enqueueing across launches.
        let current = store.load().filter { $0.id != id }
        store.save(current)
    }

    private func refreshUploadStatuses() {
        uploadStatuses = uploadStatusMap.values.sorted { $0.metadata.capturedAt > $1.metadata.capturedAt }
    }
}

extension UploadQueueViewModel {
    struct UploadStatus: Identifiable, Equatable {
        var metadata: CaptureUploadMetadata
        let packageURL: URL
        var state: State
        var targetName: String?
        var estimatedPayoutRange: ClosedRange<Int>?

        var id: UUID { metadata.id }

        enum State: Equatable {
            case queued
            case uploading(progress: Double)
            case completed
            case failed(message: String)
        }
    }
}
