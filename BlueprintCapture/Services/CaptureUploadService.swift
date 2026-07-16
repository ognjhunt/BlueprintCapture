import Foundation
import Combine
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(UIKit)
import UIKit
#endif
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
    nonisolated static let shared = CaptureUploadService()

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
        case insufficientDiskSpace
        case uploadLimitExceeded(reasons: [String])
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
            case .insufficientDiskSpace:
                return "Not enough free space to finalize this capture bundle safely. Free storage and try again before uploading."
            case .uploadLimitExceeded(let reasons):
                return "Capture exceeds beta upload limits and was not uploaded: \(reasons.joined(separator: ", ")). Shorten the walkthrough or split the site into smaller captures."
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
            case .insufficientDiskSpace:
                return "insufficient_disk_space"
            case .uploadLimitExceeded:
                return "capture_upload_limit_exceeded"
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
            case .insufficientDiskSpace, .uploadLimitExceeded:
                return "local_preflight_failed"
            default:
                return "upload_failed"
            }
        }

        var lifecycleQaState: String {
            switch self {
            case .rawContractValidationFailed, .invalidBundle:
                return "blocked_raw_validation"
            case .insufficientDiskSpace:
                return "blocked_local_storage"
            case .uploadLimitExceeded:
                return "blocked_local_capture_limits"
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
        var autoRetriesRemaining: Int = CaptureUploadService.maxInSessionAutoRetries
    }

    /// Bounded in-session automatic retry policy. The locally preserved
    /// bundle is never touched by a retry — it only re-runs the upload.
    static let maxInSessionAutoRetries = 2

    static func shouldAutoRetry(error: UploadError, retriesRemaining: Int) -> Bool {
        guard retriesRemaining > 0 else { return false }
        switch error {
        case .uploadFailed, .submissionRegistrationFailed:
            // Transient transport/registration failures: storage uploads
            // resume from verified chunks and the registration write is
            // idempotent under the capture_submissions rules contract.
            return true
        case .fileMissing, .cancelled, .authenticationRequired,
             .missingStructuredIntake, .rawContractValidationFailed,
             .insufficientDiskSpace, .uploadLimitExceeded,
             .captureLifecycleRegistrationFailed, .invalidBundle:
            // Requires user action or a real precondition change; retrying
            // in-session would just repeat the same deterministic failure.
            return false
        }
    }

    static func autoRetryDelaySeconds(forRetryNumber retryNumber: Int) -> Double {
        // 4s, 16s, ... capped well below the background-task budget.
        min(pow(4.0, Double(max(retryNumber, 1))), 60.0)
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
        // A fresh enqueue (or explicit manual retry) replenishes the bounded
        // in-session auto-retry budget.
        record.autoRetriesRemaining = Self.maxInSessionAutoRetries
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

        #if canImport(UIKit)
        let backgroundTask = await MainActor.run {
            UIApplication.shared.beginBackgroundTask(withName: "BlueprintCaptureUpload-\(id.uuidString)") {
                SessionEventManager.shared.logOperationalEvent(
                    operation: "upload_background_task",
                    status: "expired",
                    metadata: ["capture_id": CaptureBundleContext.captureIdentifier(for: record.request)]
                )
            }
        }
        defer {
            Task { @MainActor in
                if backgroundTask != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTask)
                }
            }
        }
        #endif

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
            SessionEventManager.shared.logError(
                errorCode: "single_file_upload_unsupported",
                metadata: [
                    "capture_id": CaptureBundleContext.captureIdentifier(for: record.request),
                    "scene_id": CaptureBundleContext.sceneIdentifier(for: record.request),
                    "package_name": packageURL.lastPathComponent
                ]
            )
            print("❌ [UploadService] Refusing non-directory upload package id=\(id) url=\(packageURL.path); external beta requires canonical raw bundle directories")
            markUploadFailed(
                id: id,
                attempt: attempt,
                error: .invalidBundle(reasons: ["canonical_raw_bundle_directory_required"])
            )
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
        guard hasUsableDiskSpace(for: localDirectory) else {
            SessionEventManager.shared.logError(
                errorCode: "insufficient_disk_space",
                metadata: [
                    "capture_id": CaptureBundleContext.captureIdentifier(for: request),
                    "scene_id": CaptureBundleContext.sceneIdentifier(for: request)
                ]
            )
            markUploadFailed(id: id, attempt: attempt, error: .insufficientDiskSpace)
            return false
        }

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
        let hashArtifacts = loadHashArtifacts(from: uploadRoot)

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
        let limitDecision = CaptureUploadLimitPolicy.betaDefault.evaluate(
            plan: uploadPlan,
            durationSeconds: manifestDurationSeconds(from: uploadRoot)
        )
        guard limitDecision.allowed else {
            SessionEventManager.shared.logOperationalEvent(
                operation: "capture_upload_limit_preflight",
                status: "blocked",
                metadata: [
                    "capture_id": CaptureBundleContext.captureIdentifier(for: request),
                    "scene_id": CaptureBundleContext.sceneIdentifier(for: request),
                    "reasons": limitDecision.reasons.joined(separator: ","),
                    "total_payload_bytes": String(limitDecision.totalPayloadBytes),
                    "max_file_size_bytes": String(limitDecision.maxFileSizeBytes),
                    "duration_seconds": limitDecision.durationSeconds.map { String(format: "%.3f", $0) } ?? "unknown",
                    "max_duration_seconds": String(format: "%.3f", limitDecision.maxDurationSeconds)
                ]
            )
            print("❌ [UploadService] Capture exceeds beta upload limits id=\(id) reasons=\(limitDecision.reasons.joined(separator: ",")) bytes=\(limitDecision.totalPayloadBytes)")
            markUploadFailed(id: id, attempt: attempt, error: .uploadLimitExceeded(reasons: limitDecision.reasons))
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
            if let expectedSha256 = hashArtifacts[relPath] ?? sha256Hex(for: file) {
                custom["sha256"] = expectedSha256
            }
            if let t = request.metadata.targetId { custom["targetId"] = t }
            if let r = request.metadata.reservationId { custom["reservationId"] = r }
            md.customMetadata = custom

            var uploadError: Error?
            do {
                try await BackgroundFirebaseStorageUploader.shared.uploadFile(
                    file,
                    bucketURL: storageBucketURL,
                    objectPath: remotePath,
                    contentType: md.contentType ?? contentType(for: file),
                    customMetadata: custom,
                    onTaskStarted: { [weak self] uploadTask in
                        self?.setActiveTransferCancellationHandler(for: id, attempt: attempt) {
                            uploadTask.cancel()
                        }
                    },
                    onProgress: { [weak self] completed, _ in
                        guard let self, self.isCurrentAttempt(id: id, attempt: attempt) else { return }
                        let fraction = Double(uploadedBytes + completed) / Double(max(1, totalBytes))
                        self.subject.send(.progress(id: id, progress: min(max(fraction, 0.0), 0.999)))
                    }
                )
            } catch {
                uploadError = error
            }
            clearActiveTransferCancellationHandler(for: id, attempt: attempt)

            guard isCurrentAttempt(id: id, attempt: attempt) else { return false }
            if Task.isCancelled { return false }

            let fileUploaded: Bool
            if let uploadError {
                fileUploaded = await shouldTreatUploadErrorAsSuccess(uploadError, for: ref, localFile: file, expectedSha256: hashArtifacts[relPath] ?? sha256Hex(for: file))
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
                attempt: attempt,
                request: request,
                expectedSha256: hashArtifacts[CaptureUploadFilePlan.completionMarkerFilename] ?? sha256Hex(for: completionMarkerFile)
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

    private func manifestDurationSeconds(from uploadRoot: URL) -> Double? {
        let manifestURL = uploadRoot.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let value = json["duration_seconds"] as? Double {
            return value
        }
        if let value = json["duration_seconds"] as? Int {
            return Double(value)
        }
        if let value = json["duration"] as? Double {
            return value
        }
        if let value = json["duration"] as? Int {
            return Double(value)
        }
        return nil
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

    func captureSubmissionPayload(
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

    func uploadFailurePayload(
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

    private func uploadCompletionMarker(
        at file: URL,
        to ref: StorageReference,
        id: UUID,
        attempt: UUID,
        request: CaptureUploadRequest,
        expectedSha256: String?
    ) async -> Bool {
        guard let data = try? Data(contentsOf: file) else {
            return false
        }

        let metadata = StorageMetadata()
        metadata.contentType = "application/json"
        metadata.customMetadata = [
            "jobId": request.metadata.jobId,
            "creatorId": request.metadata.creatorId,
            "capturedAt": ISO8601DateFormatter().string(from: request.metadata.capturedAt),
            "captureSource": request.metadata.captureSource.rawValue,
            "sceneId": CaptureBundleContext.sceneIdentifier(for: request),
            "captureId": CaptureBundleContext.captureIdentifier(for: request),
            "sha256": expectedSha256 ?? sha256Hex(of: data)
        ]

        var uploadError: Error?
        do {
            try await BackgroundFirebaseStorageUploader.shared.uploadFile(
                file,
                bucketURL: storageBucketURL,
                objectPath: ref.fullPath,
                contentType: metadata.contentType ?? "application/json",
                customMetadata: metadata.customMetadata ?? [:],
                onTaskStarted: { [weak self] uploadTask in
                    self?.setActiveTransferCancellationHandler(for: id, attempt: attempt) {
                        uploadTask.cancel()
                    }
                }
            )
        } catch {
            uploadError = error
        }
        clearActiveTransferCancellationHandler(for: id, attempt: attempt)

        guard isCurrentAttempt(id: id, attempt: attempt), !Task.isCancelled else {
            return false
        }
        if let uploadError {
            return await shouldTreatUploadErrorAsSuccess(uploadError, for: ref, localFile: file, expectedSha256: expectedSha256 ?? sha256Hex(of: data))
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

    private func shouldTreatUploadErrorAsSuccess(_ error: Error, for ref: StorageReference, localFile: URL? = nil, expectedSha256: String? = nil) async -> Bool {
        guard CaptureUploadErrorClassifier.isAlreadyFinalized(error) else {
            return false
        }
        guard await remoteObjectMatchesLocalTruth(ref: ref, localFile: localFile, expectedSha256: expectedSha256) else {
            return false
        }
        print("⚠️ [UploadService] Storage reported an already-finalized upload for \(ref.fullPath); treating as success")
        return true
    }

    private func remoteObjectMatchesLocalTruth(ref: StorageReference, localFile: URL?, expectedSha256: String?) async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            ref.getMetadata { metadata, error in
                guard error == nil, let metadata else {
                    cont.resume(returning: false)
                    return
                }
                if let localFile,
                   let localSize = (try? localFile.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
                   metadata.size != Int64(localSize) {
                    cont.resume(returning: false)
                    return
                }
                if let expectedSha256,
                   metadata.customMetadata?["sha256"] != expectedSha256 {
                    cont.resume(returning: false)
                    return
                }
                cont.resume(returning: true)
            }
        }
    }
    #endif

    private func hasUsableDiskSpace(for directory: URL) -> Bool {
        guard let freeBytes = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage else {
            return true
        }
        let plannedBytes = CaptureUploadFilePlan.make(for: directory)?.totalPayloadBytes ?? 0
        let requiredHeadroom = max(250_000_000, plannedBytes / 5)
        return freeBytes > requiredHeadroom
    }

    private func loadHashArtifacts(from rawDirectoryURL: URL) -> [String: String] {
        let hashesURL = rawDirectoryURL.appendingPathComponent("hashes.json")
        guard let data = try? Data(contentsOf: hashesURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let artifacts = json["artifacts"] as? [String: String] else {
            return [:]
        }
        return artifacts
    }

    private func sha256Hex(for fileURL: URL) -> String? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return sha256Hex(of: data)
    }

    private func sha256Hex(of data: Data) -> String {
        #if canImport(CryptoKit)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
        #else
        return ""
        #endif
    }

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

            if Self.shouldAutoRetry(error: error, retriesRemaining: failingRecord.autoRetriesRemaining) {
                failingRecord.autoRetriesRemaining -= 1
                let retryNumber = Self.maxInSessionAutoRetries - failingRecord.autoRetriesRemaining
                let delaySeconds = Self.autoRetryDelaySeconds(forRetryNumber: retryNumber)
                let retryAttempt = UUID()
                failingRecord.attempt = retryAttempt
                SessionEventManager.shared.logOperationalEvent(
                    operation: "upload_in_session_auto_retry",
                    status: "scheduled",
                    metadata: [
                        "capture_id": CaptureBundleContext.captureIdentifier(for: failingRecord.request),
                        "failure_code": error.lifecycleFailureCode,
                        "retry_number": "\(retryNumber)",
                        "delay_seconds": "\(delaySeconds)"
                    ]
                )
                print("🔁 [UploadService] Scheduling in-session auto-retry #\(retryNumber) in \(delaySeconds)s for id=\(id)")
                let failedRequest = failingRecord.request
                let retryTask = Task { [weak self] in
                    // Persist the documented failure transition BEFORE the
                    // backoff sleep: if iOS suspends/kills the process while
                    // the retry is parked, the submission must not stay
                    // "uploading" forever. The write completes before the
                    // retry begins, and a successful retry then re-asserts
                    // submitted/uploaded (the rules allow failed -> retry).
                    await self?.recordUploadFailure(for: failedRequest, error: error)
                    try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
                    guard let self, !Task.isCancelled else { return }
                    await self.performUpload(for: id, attempt: retryAttempt)
                }
                failingRecord.task = retryTask
                self.uploads[id] = failingRecord
                return
            }

            self.uploads[id] = failingRecord
            self.subject.send(.failed(failingRecord.request, error))
            Task {
                await self.recordUploadFailure(for: failingRecord.request, error: error)
            }
        }
    }
}

final class BackgroundFirebaseStorageUploader: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate {
    static let shared = BackgroundFirebaseStorageUploader()

    private struct PendingUpload {
        let continuation: CheckedContinuation<Void, Error>
        let onProgress: (Int64, Int64) -> Void
        let temporaryFileURL: URL?
        var responseData = Data()
        var response: HTTPURLResponse?
    }

    private struct PersistedUploadSession: Codable {
        let bucketName: String
        let objectPath: String
        let localFilePath: String
        let fileSize: Int64
        let contentType: String
        let uploadURLString: String
        var lastKnownOffset: Int64
        var updatedAt: Date
    }

    private final class CancellableUploadTaskBox: @unchecked Sendable {
        private let lock = NSLock()
        private var task: URLSessionUploadTask?

        func set(_ task: URLSessionUploadTask) {
            lock.lock()
            self.task = task
            lock.unlock()
        }

        func cancel() {
            lock.lock()
            let task = self.task
            lock.unlock()
            task?.cancel()
        }
    }


    private enum UploadError: LocalizedError {
        case invalidBucketURL(String)
        case missingFirebaseUser
        case missingUploadURL
        case startFailed(status: Int, body: String)
        case uploadFailed(status: Int, body: String)

        var errorDescription: String? {
            switch self {
            case .invalidBucketURL(let url):
                return "Invalid Firebase Storage bucket URL: \(url)"
            case .missingFirebaseUser:
                return "Firebase authentication is required before starting a background upload."
            case .missingUploadURL:
                return "Firebase Storage did not return a resumable upload URL."
            case .startFailed(let status, let body):
                return "Firebase Storage resumable upload start failed with status \(status): \(body)"
            case .uploadFailed(let status, let body):
                return "Firebase Storage background upload failed with status \(status): \(body)"
            }
        }
    }

    private let lock = NSLock()
    private var pendingUploads: [Int: PendingUpload] = [:]
    private var backgroundCompletionHandler: (() -> Void)?
    private let uploadChunkSize: Int64 = 8 * 1024 * 1024

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(
            withIdentifier: "Public.BlueprintCapture.firebase-storage-background-upload"
        )
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    func setBackgroundCompletionHandler(_ completionHandler: @escaping () -> Void) {
        lock.lock()
        backgroundCompletionHandler = completionHandler
        lock.unlock()
    }

    func uploadFile(
        _ fileURL: URL,
        bucketURL: String,
        objectPath: String,
        contentType: String,
        customMetadata: [String: String],
        onTaskStarted: @escaping (URLSessionUploadTask) -> Void = { _ in },
        onProgress: @escaping (Int64, Int64) -> Void = { _, _ in }
    ) async throws {
        let bucketName = try Self.bucketName(from: bucketURL)
        let fileSize = Int64((try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        let token = try await firebaseIDToken()
        let uploadSession = try await prepareResumableUploadSession(
            bucketName: bucketName,
            objectPath: objectPath,
            fileURL: fileURL,
            contentType: contentType,
            customMetadata: customMetadata,
            fileSize: fileSize,
            idToken: token
        )

        if uploadSession.offset >= fileSize {
            clearPersistedUploadSession(key: uploadSession.key)
            onProgress(fileSize, fileSize)
            return
        }

        var offset = uploadSession.offset
        if offset > 0 {
            onProgress(offset, fileSize)
        }

        if fileSize == 0 {
            try await uploadChunk(
                fileURL,
                uploadURL: uploadSession.uploadURL,
                idToken: token,
                contentType: contentType,
                offset: 0,
                totalFileSize: fileSize,
                command: "upload, finalize",
                temporaryFileURL: nil,
                onTaskStarted: onTaskStarted,
                onProgress: onProgress
            )
            clearPersistedUploadSession(key: uploadSession.key)
            return
        }

        while offset < fileSize {
            try Task.checkCancellation()
            let length = min(uploadChunkSize, fileSize - offset)
            let isFinalChunk = offset + length >= fileSize
            let chunkURL = try makeChunkFile(from: fileURL, offset: offset, length: length)
            try await uploadChunk(
                chunkURL,
                uploadURL: uploadSession.uploadURL,
                idToken: token,
                contentType: contentType,
                offset: offset,
                totalFileSize: fileSize,
                command: isFinalChunk ? "upload, finalize" : "upload",
                temporaryFileURL: chunkURL,
                onTaskStarted: onTaskStarted,
                onProgress: { [offset] completed, _ in
                    onProgress(min(fileSize, offset + completed), fileSize)
                }
            )
            offset += length
            persistUploadSessionOffset(key: uploadSession.key, offset: offset)
        }
        clearPersistedUploadSession(key: uploadSession.key)
    }

    private func uploadChunk(
        _ fileURL: URL,
        uploadURL: URL,
        idToken: String,
        contentType: String,
        offset: Int64,
        totalFileSize: Int64,
        command: String,
        temporaryFileURL: URL?,
        onTaskStarted: @escaping (URLSessionUploadTask) -> Void,
        onProgress: @escaping (Int64, Int64) -> Void
    ) async throws {
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(command, forHTTPHeaderField: "X-Goog-Upload-Command")
        request.setValue(String(offset), forHTTPHeaderField: "X-Goog-Upload-Offset")

        let uploadTaskBox = CancellableUploadTaskBox()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let task = session.uploadTask(with: request, fromFile: fileURL)
                uploadTaskBox.set(task)
                lock.lock()
                pendingUploads[task.taskIdentifier] = PendingUpload(
                    continuation: continuation,
                    onProgress: onProgress,
                    temporaryFileURL: temporaryFileURL
                )
                lock.unlock()
                onTaskStarted(task)
                task.resume()
            }
        } onCancel: {
            uploadTaskBox.cancel()
        }
    }

    private func makeChunkFile(from fileURL: URL, offset: Int64, length: Int64) throws -> URL {
        let chunkDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlueprintCaptureUploadChunks", isDirectory: true)
        try FileManager.default.createDirectory(at: chunkDirectory, withIntermediateDirectories: true)
        let chunkURL = chunkDirectory.appendingPathComponent("\(UUID().uuidString).part")
        let input = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? input.close()
        }
        try input.seek(toOffset: UInt64(offset))
        let data = try input.read(upToCount: Int(length)) ?? Data()
        try data.write(to: chunkURL, options: .atomic)
        return chunkURL
    }

    private func prepareResumableUploadSession(
        bucketName: String,
        objectPath: String,
        fileURL: URL,
        contentType: String,
        customMetadata: [String: String],
        fileSize: Int64,
        idToken: String
    ) async throws -> (key: String, uploadURL: URL, offset: Int64) {
        let key = uploadSessionKey(
            bucketName: bucketName,
            objectPath: objectPath,
            localFilePath: fileURL.path,
            fileSize: fileSize
        )
        if let persisted = loadPersistedUploadSession(key: key),
           persisted.bucketName == bucketName,
           persisted.objectPath == objectPath,
           persisted.localFilePath == fileURL.path,
           persisted.fileSize == fileSize,
           let persistedURL = URL(string: persisted.uploadURLString) {
            do {
                let serverOffset = try await queryResumableUploadOffset(
                    uploadURL: persistedURL,
                    idToken: idToken,
                    fileSize: fileSize
                )
                persistUploadSessionOffset(key: key, offset: serverOffset)
                return (key, persistedURL, serverOffset)
            } catch {
                clearPersistedUploadSession(key: key)
            }
        }

        let uploadURL = try await startResumableUpload(
            bucketName: bucketName,
            objectPath: objectPath,
            contentType: contentType,
            customMetadata: customMetadata,
            fileSize: fileSize,
            idToken: idToken
        )
        persistUploadSession(
            key: key,
            session: PersistedUploadSession(
                bucketName: bucketName,
                objectPath: objectPath,
                localFilePath: fileURL.path,
                fileSize: fileSize,
                contentType: contentType,
                uploadURLString: uploadURL.absoluteString,
                lastKnownOffset: 0,
                updatedAt: Date()
            )
        )
        return (key, uploadURL, 0)
    }

    private func queryResumableUploadOffset(uploadURL: URL, idToken: String, fileSize: Int64) async throws -> Int64 {
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue("query", forHTTPHeaderField: "X-Goog-Upload-Command")
        request.setValue("0", forHTTPHeaderField: "X-Goog-Upload-Offset")

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<400).contains(status), let httpResponse = response as? HTTPURLResponse else {
            throw UploadError.uploadFailed(status: status, body: String(data: data, encoding: .utf8) ?? "")
        }
        if let uploadStatus = Self.headerValue("X-Goog-Upload-Status", in: httpResponse),
           uploadStatus.lowercased() == "final" {
            return fileSize
        }
        if let received = Self.headerValue("X-Goog-Upload-Size-Received", in: httpResponse) ?? Self.headerValue("X-Goog-Upload-Offset", in: httpResponse),
           let parsed = Int64(received.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return min(max(0, parsed), fileSize)
        }
        return 0
    }

    private func uploadSessionKey(bucketName: String, objectPath: String, localFilePath: String, fileSize: Int64) -> String {
        let raw = "\(bucketName)\n\(objectPath)\n\(localFilePath)\n\(fileSize)"
        #if canImport(CryptoKit)
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
        #else
        return Data(raw.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        #endif
    }

    private func uploadSessionDirectory() -> URL? {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }
        let directory = applicationSupport
            .appendingPathComponent("BlueprintCapture", isDirectory: true)
            .appendingPathComponent("ResumableUploads", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        } catch {
            return nil
        }
    }

    private func uploadSessionFileURL(key: String) -> URL? {
        uploadSessionDirectory()?.appendingPathComponent("\(key).json")
    }

    private func loadPersistedUploadSession(key: String) -> PersistedUploadSession? {
        guard let url = uploadSessionFileURL(key: key),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(PersistedUploadSession.self, from: data)
    }

    private func persistUploadSession(key: String, session: PersistedUploadSession) {
        guard let url = uploadSessionFileURL(key: key),
              let data = try? JSONEncoder().encode(session) else {
            return
        }
        try? data.write(to: url, options: .atomic)
    }

    private func persistUploadSessionOffset(key: String, offset: Int64) {
        guard var session = loadPersistedUploadSession(key: key) else {
            return
        }
        session.lastKnownOffset = offset
        session.updatedAt = Date()
        persistUploadSession(key: key, session: session)
    }

    private func clearPersistedUploadSession(key: String) {
        guard let url = uploadSessionFileURL(key: key) else {
            return
        }
        try? FileManager.default.removeItem(at: url)
    }

    private static func bucketName(from bucketURL: String) throws -> String {
        guard bucketURL.hasPrefix("gs://") else {
            throw UploadError.invalidBucketURL(bucketURL)
        }
        let name = String(bucketURL.dropFirst("gs://".count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !name.isEmpty else {
            throw UploadError.invalidBucketURL(bucketURL)
        }
        return name
    }

    private func firebaseIDToken() async throws -> String {
        #if canImport(FirebaseAuth)
        guard let user = Auth.auth().currentUser else {
            throw UploadError.missingFirebaseUser
        }
        return try await withCheckedThrowingContinuation { continuation in
            user.getIDToken { token, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let token, !token.isEmpty else {
                    continuation.resume(throwing: UploadError.missingFirebaseUser)
                    return
                }
                continuation.resume(returning: token)
            }
        }
        #else
        throw UploadError.missingFirebaseUser
        #endif
    }

    private func startResumableUpload(
        bucketName: String,
        objectPath: String,
        contentType: String,
        customMetadata: [String: String],
        fileSize: Int64,
        idToken: String
    ) async throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "firebasestorage.googleapis.com"
        components.path = "/v0/b/\(bucketName)/o"
        components.queryItems = [URLQueryItem(name: "name", value: objectPath)]
        guard let url = components.url else {
            throw UploadError.invalidBucketURL(bucketName)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("resumable", forHTTPHeaderField: "X-Goog-Upload-Protocol")
        request.setValue("start", forHTTPHeaderField: "X-Goog-Upload-Command")
        request.setValue(String(fileSize), forHTTPHeaderField: "X-Goog-Upload-Header-Content-Length")
        request.setValue(contentType, forHTTPHeaderField: "X-Goog-Upload-Header-Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "name": objectPath,
            "contentType": contentType,
            "metadata": customMetadata,
        ], options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw UploadError.startFailed(status: status, body: String(data: data, encoding: .utf8) ?? "")
        }
        guard let httpResponse = response as? HTTPURLResponse,
              let uploadURLString = Self.headerValue("X-Goog-Upload-URL", in: httpResponse)
                ?? Self.headerValue("Location", in: httpResponse),
              let uploadURL = URL(string: uploadURLString) else {
            throw UploadError.missingUploadURL
        }
        return uploadURL
    }

    private static func headerValue(_ name: String, in response: HTTPURLResponse) -> String? {
        for (key, value) in response.allHeaderFields {
            guard String(describing: key).caseInsensitiveCompare(name) == .orderedSame else {
                continue
            }
            return String(describing: value)
        }
        return nil
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        lock.lock()
        let progress = pendingUploads[task.taskIdentifier]?.onProgress
        lock.unlock()
        progress?(totalBytesSent, totalBytesExpectedToSend)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let httpResponse = response as? HTTPURLResponse {
            lock.lock()
            if var pending = pendingUploads[dataTask.taskIdentifier] {
                pending.response = httpResponse
                pendingUploads[dataTask.taskIdentifier] = pending
            }
            lock.unlock()
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        if var pending = pendingUploads[dataTask.taskIdentifier] {
            pending.responseData.append(data)
            pendingUploads[dataTask.taskIdentifier] = pending
        }
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let pending = pendingUploads.removeValue(forKey: task.taskIdentifier)
        lock.unlock()

        guard let pending else {
            return
        }
        if let temporaryFileURL = pending.temporaryFileURL {
            try? FileManager.default.removeItem(at: temporaryFileURL)
        }
        if let error {
            pending.continuation.resume(throwing: error)
            return
        }
        let status = pending.response?.statusCode ?? 0
        if (200..<300).contains(status) {
            pending.continuation.resume()
        } else {
            pending.continuation.resume(
                throwing: UploadError.uploadFailed(
                    status: status,
                    body: String(data: pending.responseData, encoding: .utf8) ?? ""
                )
            )
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        lock.lock()
        let completionHandler = backgroundCompletionHandler
        backgroundCompletionHandler = nil
        lock.unlock()

        if let completionHandler {
            DispatchQueue.main.async {
                completionHandler()
            }
        }
    }
}
