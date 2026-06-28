import Foundation
import Combine
#if canImport(FirebaseStorage)
import FirebaseStorage
#endif
#if canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif
#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

protocol CaptureUploadServiceProtocol: AnyObject {
    var events: AnyPublisher<CaptureUploadService.Event, Never> { get }
    func enqueue(_ request: CaptureUploadRequest)
    func retryUpload(id: UUID)
    func cancelUpload(id: UUID)
}

final class CaptureUploadService: CaptureUploadServiceProtocol {
    nonisolated(unsafe) static let shared = CaptureUploadService()

    /// Firebase-backed upload pipeline that emits progress/completion events
    enum Event {
        case queued(CaptureUploadRequest)
        case progress(id: UUID, progress: Double)
        case completed(CaptureUploadRequest)
        case failed(CaptureUploadRequest, UploadError)
    }

    enum UploadError: LocalizedError, Equatable {
        case fileMissing
        case cancelled
        case uploadFailed
        case authenticationRequired
        case missingStructuredIntake
        case rawContractValidationFailed
        case captureLifecycleRegistrationFailed
        case submissionRegistrationFailed
        case invalidBundle(reasons: [String])

        var errorDescription: String? {
            switch self {
            case .fileMissing:
                return "The recorded file could not be found."
            case .cancelled:
                return "Upload cancelled."
            case .uploadFailed:
                return "Upload failed. Please try again."
            case .authenticationRequired:
                return "Blueprint could not establish Firebase authentication for this capture. Enable Anonymous Auth or sign in before uploading."
            case .missingStructuredIntake:
                return "Structured intake is required before upload."
            case .rawContractValidationFailed:
                return "Raw capture validation failed. Please retake and upload again."
            case .captureLifecycleRegistrationFailed:
                return "Blueprint could not register this capture as in-progress before upload started. Check Firebase Auth and Firestore configuration before retrying."
            case .submissionRegistrationFailed:
                return "Upload reached storage but Blueprint could not register the capture submission. Check Firebase Auth and Firestore production config before retrying."
            case .invalidBundle(let reasons):
                return "Raw capture bundle is invalid and cannot be uploaded: \(reasons.joined(separator: ", ")). Please re-record the site walkthrough."
            }
        }

        var lifecycleFailureCode: String {
            switch self {
            case .fileMissing:
                return "file_missing"
            case .cancelled:
                return "cancelled"
            case .uploadFailed:
                return "upload_failed"
            case .authenticationRequired:
                return "authentication_required"
            case .missingStructuredIntake:
                return "missing_structured_intake"
            case .rawContractValidationFailed:
                return "raw_contract_v3_validation_failed"
            case .captureLifecycleRegistrationFailed:
                return "capture_lifecycle_registration_failed"
            case .submissionRegistrationFailed:
                return "submission_registration_failed"
            case .invalidBundle:
                return "invalid_bundle"
            }
        }

        var shouldRecordLifecycleFailure: Bool {
            self != .cancelled
        }

        var lifecycleStatus: String {
            switch self {
            case .rawContractValidationFailed, .invalidBundle:
                return "raw_validation_failed"
            default:
                return "upload_failed"
            }
        }

        var lifecycleQaState: String {
            switch self {
            case .rawContractValidationFailed, .invalidBundle:
                return "blocked_raw_validation"
            default:
                return "not_started"
            }
        }
    }

    var events: AnyPublisher<Event, Never> {
        subject.eraseToAnyPublisher()
    }

    private struct UploadRecord {
        var request: CaptureUploadRequest
        var task: Task<Void, Never>?
        var cancelActiveTransfer: (() -> Void)?
        var attempt: UUID
    }

    private let queue = DispatchQueue(label: "com.blueprint.captureUploadService")
    private var uploads: [UUID: UploadRecord] = [:]
    private let subject = PassthroughSubject<Event, Never>()
    private let storageBucketURL = "gs://blueprint-8c1ca.appspot.com"
    private let finalizer: CaptureBundleFinalizerProtocol
    private let rawContractValidator: CaptureRawContractV3Validator
    init(
        finalizer: CaptureBundleFinalizerProtocol = CaptureBundleFinalizer(),
        rawContractValidator: CaptureRawContractV3Validator = CaptureRawContractV3Validator()
    ) {
        self.finalizer = finalizer
        self.rawContractValidator = rawContractValidator
    }

    func enqueue(_ request: CaptureUploadRequest) {
        queue.async {
            self.storeAndBeginUpload(request: request)
        }
    }

    func retryUpload(id: UUID) {
        queue.async {
            guard var record = self.uploads[id] else { return }
            record.task?.cancel()
            record.cancelActiveTransfer?()
            var request = record.request
            request.metadata.uploadedAt = nil
            record.request = request
            record.task = nil
            record.cancelActiveTransfer = nil
            record.attempt = UUID()
            self.uploads[id] = record
            self.storeAndBeginUpload(request: request)
        }
    }

    func cancelUpload(id: UUID) {
        queue.async {
            guard var record = self.uploads[id] else { return }
            record.task?.cancel()
            record.cancelActiveTransfer?()
            record.task = nil
            record.cancelActiveTransfer = nil
            record.attempt = UUID()
            self.uploads[id] = record
            self.subject.send(.failed(record.request, .cancelled))
        }
    }

    private func storeAndBeginUpload(request: CaptureUploadRequest) {
        let id = request.metadata.id
        if var existing = uploads[id], existing.task != nil {
            existing.request = request
            uploads[id] = existing
            print("ℹ️ [UploadService] Duplicate enqueue ignored for id=\(id)")
            return
        }

        let attempt = UUID()
        var record = uploads[id] ?? UploadRecord(request: request, task: nil, cancelActiveTransfer: nil, attempt: attempt)
        record.request = request
        record.task = nil
        record.cancelActiveTransfer = nil
        record.attempt = attempt
        uploads[id] = record
        subject.send(.queued(request))

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performUpload(for: id, attempt: attempt)
        }
        record.task = task
        uploads[id] = record
    }

    private func performUpload(for id: UUID, attempt: UUID) async {
        guard let record = queue.sync(execute: { uploads[id] }), record.attempt == attempt else { return }
        let packageURL = record.request.packageURL
        print("🚀 [UploadService] performUpload start id=\(id) url=\(packageURL.path)")

        // Alpha: intake gate removed — proceed regardless of intake completeness
        guard FileManager.default.fileExists(atPath: packageURL.path) else {
            print("❌ [UploadService] package missing at path=\(packageURL.path)")
            markUploadFailed(id: id, attempt: attempt, error: .fileMissing)
            return
        }

        #if canImport(FirebaseStorage)
        do {
            _ = try await UserDeviceService.ensureFirebaseGuestSession(timeout: 10)
        } catch {
            SessionEventManager.shared.logError(
                errorCode: "guest_auth_bootstrap_failed",
                metadata: [
                    "context": "upload_enqueue",
                    "message": error.localizedDescription
                ]
            )
            print("❌ [UploadService] Firebase auth unavailable; refusing to upload without a capture_submissions-capable session")
            markUploadFailed(id: id, attempt: attempt, error: .authenticationRequired)
            return
        }

        let storage = Storage.storage(url: storageBucketURL)
        let lifecycleWritten = await ensureCaptureLifecycleRecordWritten(for: record.request)
        guard lifecycleWritten else {
            markUploadFailed(id: id, attempt: attempt, error: .captureLifecycleRegistrationFailed)
            return
        }
        var isDir: ObjCBool = false
        _ = FileManager.default.fileExists(atPath: packageURL.path, isDirectory: &isDir)

        if isDir.boolValue {
            // Upload directory contents recursively
            let basePath = makeBaseDirectoryPath(for: record.request)
            print("📁 [UploadService] Uploading directory → basePath=\(basePath)")
            let ok = await uploadDirectory(
                storage: storage,
                localDirectory: packageURL,
                remoteBasePath: basePath,
                id: id,
                attempt: attempt,
                request: record.request
            )
            if !ok { return }
            await finalizeSuccessfulUpload(id: id, attempt: attempt)
            print("✅ [UploadService] Directory upload completed id=\(id)")
        } else {
            // Upload single file (zip)
            let path = makeStoragePath(for: record.request)
            let ref = storage.reference(withPath: path)
            print("📦 [UploadService] Uploading file → path=\(path)")

            let metadata = StorageMetadata()
            metadata.contentType = contentType(for: packageURL)
            var custom: [String: String] = [:]
            custom["jobId"] = record.request.metadata.jobId
            custom["creatorId"] = record.request.metadata.creatorId
            custom["capturedAt"] = ISO8601DateFormatter().string(from: record.request.metadata.capturedAt)
            custom["captureSource"] = record.request.metadata.captureSource.rawValue
            if let t = record.request.metadata.targetId { custom["targetId"] = t }
            if let r = record.request.metadata.reservationId { custom["reservationId"] = r }
            metadata.customMetadata = custom

            var uploadError: Error?
            var progressHandle: String?
            var finishUpload: (() -> Void)?
            let uploadTask = ref.putFile(from: packageURL, metadata: metadata) { _, error in
                uploadError = error
                finishUpload?()
            }
            setActiveTransferCancellationHandler(for: id, attempt: attempt) {
                uploadTask.cancel()
            }

            // Observe progress
            progressHandle = uploadTask.observe(.progress) { [weak self] snapshot in
                guard let self, self.isCurrentAttempt(id: id, attempt: attempt) else { return }
                let prog = Double(snapshot.progress?.fractionCompleted ?? 0)
                self.subject.send(.progress(id: id, progress: min(max(prog, 0.0), 0.999)))
            }

            // Await completion using the upload completion callback. Firebase Storage can emit
            // an "already finalized" failure after the object has already been committed.
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                var resumed = false
                let resumeOnce = {
                    guard !resumed else { return }
                    resumed = true
                    continuation.resume()
                }
                finishUpload = resumeOnce
                if uploadTask.snapshot.status == .success || uploadTask.snapshot.status == .failure {
                    resumeOnce()
                }
            }
            if let progressHandle {
                uploadTask.removeObserver(withHandle: progressHandle)
            }
            clearActiveTransferCancellationHandler(for: id, attempt: attempt)

            guard isCurrentAttempt(id: id, attempt: attempt) else { return }
            let uploadSucceeded: Bool
            if let uploadError {
                uploadSucceeded = await shouldTreatUploadErrorAsSuccess(uploadError, for: ref)
            } else {
                uploadSucceeded = true
            }
            if uploadSucceeded {
                await finalizeSuccessfulUpload(id: id, attempt: attempt)
                print("✅ [UploadService] Upload finished id=\(id)")
            } else if !Task.isCancelled {
                markUploadFailed(id: id, attempt: attempt, error: .uploadFailed)
                print("❌ [UploadService] Upload failed id=\(id)")
            }
        }
        #else
        // Fallback: simulate progress if FirebaseStorage is unavailable (e.g., in previews)
        let steps = 12
        print("🧪 [UploadService] Simulating upload progress id=\(id)")
        for step in 1...steps {
            try? await Task.sleep(nanoseconds: 150_000_000)
            if Task.isCancelled { return }
            let progress = Double(step) / Double(steps)
            subject.send(.progress(id: id, progress: min(progress, 0.999)))
        }
        queue.async {
            guard var latestRecord = self.uploads[id] else { return }
            latestRecord.request.metadata.uploadedAt = Date()
            latestRecord.task = nil
            self.uploads[id] = latestRecord
            self.subject.send(.progress(id: id, progress: 1.0))
            self.subject.send(.completed(latestRecord.request))
        }
        #endif
    }

    #if canImport(FirebaseStorage)
    // Upload all files under a directory, preserving relative paths beneath remoteBasePath
    private func uploadDirectory(storage: Storage, localDirectory: URL, remoteBasePath: String, id: UUID, attempt: UUID, request: CaptureUploadRequest) async -> Bool {
        print("📁 [UploadService] Preparing directory upload at \(localDirectory.path)")
        let finalizedBundle: FinalizedCaptureBundle
        do {
            finalizedBundle = try finalizer.finalize(
                request: request,
                mode: .upload(
                    remoteRawPrefix: remoteBasePath,
                    videoURI: storageBucketURL + "/" + remoteBasePath + "walkthrough.mov"
                )
            )
            ActivationFunnelStore.shared.record(
                .bundleFinalized,
                captureId: CaptureBundleContext.captureIdentifier(for: request),
                metadata: ["capture_source": request.metadata.captureSource.rawValue]
            )
        } catch let error as CaptureBundleFinalizer.FinalizationError {
            let uploadError: UploadError
            switch error {
            case .missingStructuredIntake:
                uploadError = .missingStructuredIntake
            case .invalidBundle(let reasons):
                uploadError = .invalidBundle(reasons: reasons)
            default:
                uploadError = .uploadFailed
            }
            markUploadFailed(id: id, attempt: attempt, error: uploadError)
            return false
        } catch {
            markUploadFailed(id: id, attempt: attempt, error: .uploadFailed)
            return false
        }

        let uploadRoot = finalizedBundle.rawDirectoryURL
        let rawContractValidation = rawContractValidator.validate(rawDirectoryURL: uploadRoot)
        guard rawContractValidation.isValid else {
            SessionEventManager.shared.logError(
                errorCode: "raw_contract_v3_validation_failed",
                metadata: [
                    "capture_id": CaptureBundleContext.captureIdentifier(for: request),
                    "scene_id": CaptureBundleContext.sceneIdentifier(for: request),
                    "error_count": String(rawContractValidation.errors.count),
                    "first_error": rawContractValidation.errors.first ?? "unknown"
                ]
            )
            print("❌ [UploadService] Raw contract V3 validation failed captureId=\(CaptureBundleContext.captureIdentifier(for: request)) errors=\(rawContractValidation.errors.joined(separator: ","))")
            markUploadFailed(id: id, attempt: attempt, error: .rawContractValidationFailed)
            return false
        }
        if !rawContractValidation.warnings.isEmpty {
            print("⚠️ [UploadService] Raw contract V3 warnings captureId=\(CaptureBundleContext.captureIdentifier(for: request)) warnings=\(rawContractValidation.warnings.joined(separator: ","))")
        }

        // Gather files
        guard let uploadPlan = CaptureUploadFilePlan.make(for: uploadRoot) else {
            print("❌ [UploadService] Failed to enumerate directory at \(uploadRoot.path)")
            markUploadFailed(id: id, attempt: attempt, error: .uploadFailed)
            return false
        }
        let files = uploadPlan.payloadFiles
        let totalBytes = uploadPlan.totalPayloadBytes
        let completionMarkerFile = uploadPlan.completionMarkerFile
        guard !files.isEmpty || completionMarkerFile != nil else {
            print("❌ [UploadService] No files found to upload under \(uploadRoot.path)")
            markUploadFailed(id: id, attempt: attempt, error: .uploadFailed)
            return false
        }

        var uploadedBytes: Int64 = 0
        print("📁 [UploadService] Uploading \(files.count + (completionMarkerFile == nil ? 0 : 1)) files (\(totalBytes) bytes + completion marker) to basePath=\(remoteBasePath)")
        for file in files {
            if Task.isCancelled { return false }
            let relPath = file.path.replacingOccurrences(of: uploadRoot.path + "/", with: "")
            let remotePath = remoteBasePath + relPath
            let ref = storage.reference(withPath: remotePath)
            let md = StorageMetadata()
            md.contentType = contentType(for: file)
            // propagate custom metadata for each file
            var custom: [String: String] = [:]
            custom["jobId"] = request.metadata.jobId
            custom["creatorId"] = request.metadata.creatorId
            custom["capturedAt"] = ISO8601DateFormatter().string(from: request.metadata.capturedAt)
            custom["captureSource"] = request.metadata.captureSource.rawValue
            custom["sceneId"] = CaptureBundleContext.sceneIdentifier(for: request)
            custom["captureId"] = CaptureBundleContext.captureIdentifier(for: request)
            if let t = request.metadata.targetId { custom["targetId"] = t }
            if let r = request.metadata.reservationId { custom["reservationId"] = r }
            md.customMetadata = custom

            var uploadError: Error?
            var progressHandle: String?
            var finishUpload: (() -> Void)?
            let uploadTask = ref.putFile(from: file, metadata: md) { _, error in
                uploadError = error
                finishUpload?()
            }
            setActiveTransferCancellationHandler(for: id, attempt: attempt) {
                uploadTask.cancel()
            }

            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                progressHandle = uploadTask.observe(.progress) { [weak self] snapshot in
                    guard let self, self.isCurrentAttempt(id: id, attempt: attempt) else { return }
                    let completed = snapshot.progress?.completedUnitCount ?? 0
                    let fraction = Double(uploadedBytes + completed) / Double(max(1, totalBytes))
                    self.subject.send(.progress(id: id, progress: min(max(fraction, 0.0), 0.999)))
                }
                var resumed = false
                let resumeOnce = {
                    guard !resumed else { return }
                    resumed = true
                    continuation.resume()
                }
                finishUpload = resumeOnce
                if uploadTask.snapshot.status == .success || uploadTask.snapshot.status == .failure {
                    resumeOnce()
                }
            }
            if let progressHandle {
                uploadTask.removeObserver(withHandle: progressHandle)
            }
            clearActiveTransferCancellationHandler(for: id, attempt: attempt)

            guard isCurrentAttempt(id: id, attempt: attempt) else { return false }
            if Task.isCancelled { return false }

            let fileUploaded: Bool
            if let uploadError {
                fileUploaded = await shouldTreatUploadErrorAsSuccess(uploadError, for: ref)
            } else {
                fileUploaded = true
            }
            if !fileUploaded {
                SessionEventManager.shared.logOperationalEvent(
                    operation: "upload_file",
                    status: "failure",
                    metadata: [
                        "path": remotePath,
                        "message": uploadError?.localizedDescription ?? "unknown"
                    ]
                )
                print("❌ [UploadService] File upload failed path=\(remotePath) error=\(uploadError?.localizedDescription ?? "unknown")")
                markUploadFailed(id: id, attempt: attempt, error: .uploadFailed)
                return false
            }
            let completed = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? 0
            uploadedBytes += completed
        }

        if let completionMarkerFile {
            let completionRemotePath = remoteBasePath + CaptureUploadFilePlan.completionMarkerFilename
            let completionRef = storage.reference(withPath: completionRemotePath)
            let completionUploaded = await uploadCompletionMarker(
                at: completionMarkerFile,
                to: completionRef,
                id: id,
                attempt: attempt
            )
            guard completionUploaded else {
                SessionEventManager.shared.logOperationalEvent(
                    operation: "upload_completion_marker",
                    status: "failure",
                    metadata: [
                        "path": completionRemotePath
                    ]
                )
                print("❌ [UploadService] Completion marker upload failed path=\(completionRemotePath)")
                markUploadFailed(id: id, attempt: attempt, error: .uploadFailed)
                return false
            }
        }

        return true
    }

    private func slugifyCity(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private func parseCityContext(addressFull: String?, regionId: String?) -> [String: Any]? {
        if let addressFull {
            let normalized = addressFull.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalized.isEmpty {
                if normalized.contains("·"),
                   let explicitCity = normalized
                    .components(separatedBy: "·")
                    .last?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !explicitCity.isEmpty {
                    return [
                        "city": explicitCity,
                        "city_slug": slugifyCity(explicitCity)
                    ]
                }

                let commaParts = normalized
                    .components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                if commaParts.count >= 2 {
                    let city = commaParts[commaParts.count - 2]
                    if !city.isEmpty {
                        return [
                            "city": city,
                            "city_slug": slugifyCity(city)
                        ]
                    }
                }
            }
        }

        if let regionId {
            let normalizedRegion = regionId.trimmingCharacters(in: .whitespacesAndNewlines)
            let regionPattern = #"^[a-z0-9]+(?:-[a-z0-9]+)*-[a-z]{2}$"#
            if normalizedRegion.range(of: regionPattern, options: .regularExpression) != nil {
                let parts = normalizedRegion.split(separator: "-")
                if let state = parts.last {
                    let city = parts.dropLast().map { $0.capitalized }.joined(separator: " ")
                    if !city.isEmpty {
                        return [
                            "city": "\(city), \(state.uppercased())",
                            "city_slug": normalizedRegion
                        ]
                    }
                }
            }
        }

        return nil
    }

    private func targetContextPayload(for request: CaptureUploadRequest) -> [String: Any]? {
        var payload: [String: Any] = [:]
        if let targetId = request.metadata.targetId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !targetId.isEmpty {
            payload["target_id"] = targetId
        }
        let workflowFit =
            request.metadata.taskHypothesis?.workflowName
            ?? request.metadata.intakePacket?.workflowName
            ?? request.metadata.captureContextHint
        if let workflowFit = workflowFit?.trimmingCharacters(in: .whitespacesAndNewlines),
           !workflowFit.isEmpty {
            payload["workflow_fit"] = workflowFit
        }
        return payload.isEmpty ? nil : payload
    }

    private func siteIdentityPayload(for request: CaptureUploadRequest) -> [String: Any]? {
        guard let siteIdentity = request.metadata.siteIdentity else {
            return nil
        }

        var payload: [String: Any] = [
            "site_id": siteIdentity.siteId,
            "site_id_source": siteIdentity.siteIdSource,
            "place_id": siteIdentity.placeId as Any,
            "site_name": siteIdentity.siteName as Any,
            "address_full": siteIdentity.addressFull as Any,
            "building_id": siteIdentity.buildingId as Any,
            "floor_id": siteIdentity.floorId as Any,
            "room_id": siteIdentity.roomId as Any,
            "zone_id": siteIdentity.zoneId as Any
        ]
        if let geo = siteIdentity.geo {
            payload["geo"] = [
                "latitude": geo.latitude,
                "longitude": geo.longitude,
                "accuracy_m": geo.accuracyM
            ]
        }
        return payload
    }

    private func normalizedExternalId(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private func resolvedBuyerRequestId(for request: CaptureUploadRequest) -> String? {
        if let explicit = normalizedExternalId(request.metadata.buyerRequestId) {
            return explicit
        }
        if let siteIdentity = request.metadata.siteIdentity,
           siteIdentity.siteIdSource == "buyer_request" {
            let inferred = siteIdentity.siteId.trimmingCharacters(in: .whitespacesAndNewlines)
            return inferred.isEmpty ? nil : inferred
        }
        return nil
    }

    private func captureSubmissionPayload(
        for request: CaptureUploadRequest,
        recordedAt: Date,
        uploadState: String,
        includeUploadStart: Bool,
        includeUploadCompletion: Bool,
        includeSubmittedAt: Bool
    ) -> [String: Any] {
        let captureId = CaptureBundleContext.captureIdentifier(for: request)
        let sceneId = CaptureBundleContext.sceneIdentifier(for: request)
        let captureJobId = normalizedExternalId(request.metadata.captureJobId)
        let siteSubmissionId = normalizedExternalId(request.metadata.siteSubmissionId)
        let assignmentState = captureJobId == nil
            ? "unassigned_or_open_capture"
            : "assigned_capture_job"

        var lifecycle: [String: Any] = [
            "capture_started_at": Timestamp(date: request.metadata.capturedAt)
        ]
        if includeUploadStart {
            lifecycle["upload_started_at"] = Timestamp(date: recordedAt)
        }
        if includeUploadCompletion {
            lifecycle["capture_uploaded_at"] = Timestamp(date: recordedAt)
        }

        var payload: [String: Any] = [
            "capture_id": captureId,
            "scene_id": sceneId,
            "creator_id": request.metadata.creatorId,
            "job_id": request.metadata.jobId,
            "capture_source": request.metadata.captureSource.rawValue,
            "status": "submitted",
            "requested_outputs": request.metadata.requestedOutputs,
            "has_site_identity": request.metadata.siteIdentity != nil,
            "has_capture_topology": request.metadata.captureTopology != nil,
            "created_at": Timestamp(date: recordedAt),
            "operational_state": [
                "assignment_state": assignmentState,
                "upload_state": uploadState,
                "qa_state": "queued",
                "qa_outcome": NSNull(),
                "repeat_ready": false
            ],
            "lifecycle": lifecycle
        ]

        if includeSubmittedAt {
            payload["submitted_at"] = Timestamp(date: recordedAt)
        }
        if let captureJobId {
            payload["capture_job_id"] = captureJobId
        }
        if let buyerRequestId = resolvedBuyerRequestId(for: request) {
            payload["buyer_request_id"] = buyerRequestId
        }
        if let siteSubmissionId {
            payload["site_submission_id"] = siteSubmissionId
        }
        if let regionId = request.metadata.regionId {
            payload["region_id"] = regionId
        }
        if let quotedPayoutCents = request.metadata.quotedPayoutCents {
            payload["estimated_payout_cents"] = quotedPayoutCents
        }
        if let rightsProfile = request.metadata.rightsProfile {
            payload["rights_profile"] = rightsProfile
        }
        if let addressFull = request.metadata.siteIdentity?.addressFull {
            payload["target_address"] = addressFull
        }
        if let siteIdentityPayload = siteIdentityPayload(for: request) {
            payload["site_identity"] = siteIdentityPayload
        }
        if let cityContext = parseCityContext(
            addressFull: request.metadata.siteIdentity?.addressFull,
            regionId: request.metadata.regionId
        ) {
            payload["city_context"] = cityContext
        }
        if let targetContext = targetContextPayload(for: request) {
            payload["target_context"] = targetContext
        }
        if request.packageURL.hasDirectoryPath {
            payload["raw_prefix"] = "\(makeBaseDirectoryPath(for: request))raw/"
        }

        return payload
    }

    private func ensureCaptureLifecycleRecordWritten(for request: CaptureUploadRequest) async -> Bool {
        #if canImport(FirebaseFirestore)
        let captureId = CaptureBundleContext.captureIdentifier(for: request)
        do {
            _ = try await UserDeviceService.ensureFirebaseGuestSession(timeout: 10)
        } catch {
            SessionEventManager.shared.logError(
                errorCode: "capture_lifecycle_write_failed",
                metadata: [
                    "capture_id": captureId,
                    "reason": "guest_session_unavailable",
                    "message": error.localizedDescription
                ]
            )
            print("❌ [UploadService] capture_submissions/\(captureId) cannot be marked capture_in_progress because Firebase auth is unavailable")
            return false
        }

        let db = Firestore.firestore()
        let docRef = db.collection("capture_submissions").document(captureId)
        let now = Date()
        let payload = captureSubmissionPayload(
            for: request,
            recordedAt: now,
            uploadState: "uploading",
            includeUploadStart: true,
            includeUploadCompletion: false,
            includeSubmittedAt: false
        )

        return await withCheckedContinuation { continuation in
            docRef.setData(payload, merge: true) { error in
                if let error = error {
                    SessionEventManager.shared.logError(
                        errorCode: "capture_lifecycle_write_failed",
                        metadata: [
                            "capture_id": captureId,
                            "reason": "firestore_write_failed",
                            "message": error.localizedDescription
                        ]
                    )
                    print("⚠️ [UploadService] Failed to write capture_in_progress for capture_submissions/\(captureId): \(error.localizedDescription)")
                    continuation.resume(returning: false)
                } else {
                    SessionEventManager.shared.logOperationalEvent(
                        operation: "capture_lifecycle_start",
                        status: "success",
                        metadata: [
                            "capture_id": captureId
                        ]
                    )
                    print("✅ [UploadService] capture_submissions/\(captureId) marked capture_in_progress")
                    continuation.resume(returning: true)
                }
            }
        }
        #else
        return true
        #endif
    }

    /// Writes `capture_submissions/{captureId}` before the upload is reported as complete.
    /// This keeps the iPhone launch path fail-closed: raw storage upload alone is not success
    /// unless downstream submission registration also succeeds.
    private func ensureSubmissionRecordWritten(for request: CaptureUploadRequest) async -> Bool {
        #if canImport(FirebaseFirestore)
        let captureId = CaptureBundleContext.captureIdentifier(for: request)
        do {
            _ = try await UserDeviceService.ensureFirebaseGuestSession(timeout: 10)
        } catch {
            SessionEventManager.shared.logError(
                errorCode: "submission_write_failed",
                metadata: [
                    "capture_id": captureId,
                    "reason": "guest_session_unavailable",
                    "message": error.localizedDescription
                ]
            )
            print("❌ [UploadService] capture_submissions/\(captureId) cannot be written because Firebase auth is unavailable")
            return false
        }
        let db = Firestore.firestore()
        let docRef = db.collection("capture_submissions").document(captureId)
        let submittedAt = request.metadata.uploadedAt ?? Date()
        let mutablePayload = captureSubmissionPayload(
            for: request,
            recordedAt: submittedAt,
            uploadState: "uploaded",
            includeUploadStart: false,
            includeUploadCompletion: true,
            includeSubmittedAt: true
        )
        return await withCheckedContinuation { continuation in
            docRef.setData(mutablePayload, merge: true) { error in
                if let error = error {
                    SessionEventManager.shared.logError(
                        errorCode: "submission_write_failed",
                        metadata: [
                            "capture_id": captureId,
                            "reason": "firestore_write_failed",
                            "message": error.localizedDescription
                        ]
                    )
                    print("⚠️ [UploadService] Failed to write capture_submissions/\(captureId): \(error.localizedDescription)")
                    continuation.resume(returning: false)
                } else {
                    SessionEventManager.shared.logOperationalEvent(
                        operation: "submission_registration",
                        status: "success",
                        metadata: [
                            "capture_id": captureId
                        ]
                    )
                    print("✅ [UploadService] capture_submissions/\(captureId) written")
                    continuation.resume(returning: true)
                }
            }
        }
        #else
        return true
        #endif
    }

    private func finalizeSuccessfulUpload(id: UUID, attempt: UUID) async {
        let record = queue.sync(execute: { uploads[id] })
        guard let record, record.attempt == attempt else { return }
        let request = record.request

        let submissionWritten = await ensureSubmissionRecordWritten(for: request)
        guard submissionWritten else {
            markUploadFailed(id: id, attempt: attempt, error: .submissionRegistrationFailed)
            return
        }

        markUploadCompleted(id: id, attempt: attempt)
    }

    private func captureAssignmentState(for request: CaptureUploadRequest) -> String {
        normalizedExternalId(request.metadata.captureJobId) == nil
            ? "unassigned_or_open_capture"
            : "assigned_capture_job"
    }

    private func uploadFailurePayload(
        for request: CaptureUploadRequest,
        error: UploadError,
        recordedAt: Date
    ) -> [String: Any] {
        let captureId = CaptureBundleContext.captureIdentifier(for: request)
        let sceneId = CaptureBundleContext.sceneIdentifier(for: request)
        let captureJobId = normalizedExternalId(request.metadata.captureJobId)
        let siteSubmissionId = normalizedExternalId(request.metadata.siteSubmissionId)
        var payload: [String: Any] = [
            "capture_id": captureId,
            "scene_id": sceneId,
            "creator_id": request.metadata.creatorId,
            "job_id": request.metadata.jobId,
            "capture_source": request.metadata.captureSource.rawValue,
            "status": error.lifecycleStatus,
            "operational_state": [
                "assignment_state": captureAssignmentState(for: request),
                "upload_state": "failed",
                "qa_state": error.lifecycleQaState,
                "qa_outcome": NSNull(),
                "repeat_ready": true
            ],
            "lifecycle": [
                "capture_started_at": Timestamp(date: request.metadata.capturedAt),
                "upload_failed_at": Timestamp(date: recordedAt)
            ],
            "upload_error": [
                "code": error.lifecycleFailureCode,
                "message": error.errorDescription ?? "Upload failed.",
                "recorded_at": Timestamp(date: recordedAt)
            ]
        ]

        if let captureJobId {
            payload["capture_job_id"] = captureJobId
        }
        if let buyerRequestId = resolvedBuyerRequestId(for: request) {
            payload["buyer_request_id"] = buyerRequestId
        }
        if let siteSubmissionId {
            payload["site_submission_id"] = siteSubmissionId
        }
        if let regionId = request.metadata.regionId {
            payload["region_id"] = regionId
        }
        if let quotedPayoutCents = request.metadata.quotedPayoutCents {
            payload["estimated_payout_cents"] = quotedPayoutCents
        }
        if let rightsProfile = request.metadata.rightsProfile {
            payload["rights_profile"] = rightsProfile
        }
        if let addressFull = request.metadata.siteIdentity?.addressFull {
            payload["target_address"] = addressFull
        }
        if let siteIdentityPayload = siteIdentityPayload(for: request) {
            payload["site_identity"] = siteIdentityPayload
        }
        if let cityContext = parseCityContext(
            addressFull: request.metadata.siteIdentity?.addressFull,
            regionId: request.metadata.regionId
        ) {
            payload["city_context"] = cityContext
        }
        if let targetContext = targetContextPayload(for: request) {
            payload["target_context"] = targetContext
        }
        if request.packageURL.hasDirectoryPath {
            payload["raw_prefix"] = "\(makeBaseDirectoryPath(for: request))raw/"
        }
        return payload
    }

    private func recordUploadFailure(for request: CaptureUploadRequest, error uploadError: UploadError) async {
        guard uploadError.shouldRecordLifecycleFailure else { return }
        #if canImport(FirebaseFirestore)
        let captureId = CaptureBundleContext.captureIdentifier(for: request)
        do {
            _ = try await UserDeviceService.ensureFirebaseGuestSession(timeout: 10)
        } catch {
            SessionEventManager.shared.logError(
                errorCode: "capture_lifecycle_failure_write_failed",
                metadata: [
                    "capture_id": captureId,
                    "failure_code": uploadError.lifecycleFailureCode,
                    "reason": "guest_session_unavailable",
                    "message": error.localizedDescription
                ]
            )
            return
        }

        let db = Firestore.firestore()
        let payload = uploadFailurePayload(for: request, error: uploadError, recordedAt: Date())
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            db.collection("capture_submissions").document(captureId).setData(payload, merge: true) { writeError in
                if let writeError {
                    SessionEventManager.shared.logError(
                        errorCode: "capture_lifecycle_failure_write_failed",
                        metadata: [
                            "capture_id": captureId,
                            "failure_code": uploadError.lifecycleFailureCode,
                            "reason": "firestore_write_failed",
                            "message": writeError.localizedDescription
                        ]
                    )
                    print("⚠️ [UploadService] Failed to record upload failure for capture_submissions/\(captureId): \(writeError.localizedDescription)")
                } else {
                    SessionEventManager.shared.logOperationalEvent(
                        operation: "capture_lifecycle_failure",
                        status: "recorded",
                        metadata: [
                            "capture_id": captureId,
                            "failure_code": uploadError.lifecycleFailureCode
                        ]
                    )
                    print("✅ [UploadService] capture_submissions/\(captureId) marked \(uploadError.lifecycleStatus)")
                }
                continuation.resume()
            }
        }
        #endif
    }

    private func contentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "zip": return "application/zip"
        case "mov": return "video/quicktime"
        case "mp4": return "video/mp4"
        case "json", "jsonl": return "application/json"
        case "bin": return "application/octet-stream"
        case "obj": return "text/plain"
        default: return "application/octet-stream"
        }
    }

    private func makeStoragePath(for request: CaptureUploadRequest) -> String {
        let basename = request.packageURL.lastPathComponent
        return CaptureBundleContext.sceneBasePath(for: request) + basename
    }

    private func makeBaseDirectoryPath(for request: CaptureUploadRequest) -> String {
        return CaptureBundleContext.rawBasePath(for: request)
    }

    private func uploadCompletionMarker(at file: URL, to ref: StorageReference, id: UUID, attempt: UUID) async -> Bool {
        guard let data = try? Data(contentsOf: file) else {
            return false
        }

        let metadata = StorageMetadata()
        metadata.contentType = "application/json"

        var uploadError: Error?
        var finishUpload: (() -> Void)?
        let uploadTask = ref.putData(data, metadata: metadata) { _, error in
            uploadError = error
            finishUpload?()
        }
        setActiveTransferCancellationHandler(for: id, attempt: attempt) {
            uploadTask.cancel()
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var resumed = false
            let resumeOnce = {
                guard !resumed else { return }
                resumed = true
                continuation.resume()
            }
            finishUpload = resumeOnce
            if uploadTask.snapshot.status == .success || uploadTask.snapshot.status == .failure {
                resumeOnce()
            }
        }
        clearActiveTransferCancellationHandler(for: id, attempt: attempt)

        guard isCurrentAttempt(id: id, attempt: attempt), !Task.isCancelled else {
            return false
        }
        if let uploadError {
            return await shouldTreatUploadErrorAsSuccess(uploadError, for: ref)
        }
        return true
    }

    private func fileExistsInStorage(_ ref: StorageReference) async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            ref.getMetadata { _, error in
                cont.resume(returning: error == nil)
            }
        }
    }

    private func shouldTreatUploadErrorAsSuccess(_ error: Error, for ref: StorageReference) async -> Bool {
        guard CaptureUploadErrorClassifier.isAlreadyFinalized(error),
              await fileExistsInStorage(ref) else {
            return false
        }
        print("⚠️ [UploadService] Storage reported an already-finalized upload for \(ref.fullPath); treating as success")
        return true
    }
    #endif

    private func isCurrentAttempt(id: UUID, attempt: UUID) -> Bool {
        queue.sync {
            uploads[id]?.attempt == attempt
        }
    }

    private func setActiveTransferCancellationHandler(for id: UUID, attempt: UUID, handler: @escaping () -> Void) {
        queue.sync {
            guard var record = uploads[id], record.attempt == attempt else { return }
            record.cancelActiveTransfer = handler
            uploads[id] = record
        }
    }

    private func clearActiveTransferCancellationHandler(for id: UUID, attempt: UUID) {
        queue.sync {
            guard var record = uploads[id], record.attempt == attempt else { return }
            record.cancelActiveTransfer = nil
            uploads[id] = record
        }
    }

    private func markUploadCompleted(id: UUID, attempt: UUID) {
        queue.async {
            guard var latestRecord = self.uploads[id], latestRecord.attempt == attempt else { return }
            latestRecord.request.metadata.uploadedAt = Date()
            latestRecord.task = nil
            latestRecord.cancelActiveTransfer = nil
            self.uploads[id] = latestRecord
            self.subject.send(.progress(id: id, progress: 1.0))
            self.subject.send(.completed(latestRecord.request))
        }
    }

    private func markUploadFailed(id: UUID, attempt: UUID, error: UploadError) {
        queue.async {
            guard var failingRecord = self.uploads[id], failingRecord.attempt == attempt else { return }
            failingRecord.task = nil
            failingRecord.cancelActiveTransfer = nil
            self.uploads[id] = failingRecord
            self.subject.send(.failed(failingRecord.request, error))
            Task {
                await self.recordUploadFailure(for: failingRecord.request, error: error)
            }
        }
    }
}
