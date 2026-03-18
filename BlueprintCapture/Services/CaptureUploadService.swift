import Foundation
import Combine
#if canImport(FirebaseStorage)
import FirebaseStorage
#endif
#if canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

struct QualificationIntakePacket: Equatable, Codable {
    let schemaVersion: String
    let workflowName: String?
    let taskSteps: [String]
    let targetKPI: String?
    let zone: String?
    let shift: String?
    let owner: String?
    let facilityTemplate: String?
    let requiredCoverageAreas: [String]
    let benchmarkStations: [String]
    let adjacentSystems: [String]
    let privacySecurityLimits: [String]
    let knownBlockers: [String]
    let nonRoutineModes: [String]
    let peopleTrafficNotes: [String]
    let captureRestrictions: [String]
    let lightingWindows: [String]
    let shiftTrafficWindows: [String]
    let movableObstacles: [String]
    let floorConditionNotes: [String]
    let reflectiveSurfaceNotes: [String]
    let accessRules: [String]

    init(
        schemaVersion: String = "v1",
        workflowName: String? = nil,
        taskSteps: [String] = [],
        targetKPI: String? = nil,
        zone: String? = nil,
        shift: String? = nil,
        owner: String? = nil,
        facilityTemplate: String? = nil,
        requiredCoverageAreas: [String] = [],
        benchmarkStations: [String] = [],
        adjacentSystems: [String] = [],
        privacySecurityLimits: [String] = [],
        knownBlockers: [String] = [],
        nonRoutineModes: [String] = [],
        peopleTrafficNotes: [String] = [],
        captureRestrictions: [String] = [],
        lightingWindows: [String] = [],
        shiftTrafficWindows: [String] = [],
        movableObstacles: [String] = [],
        floorConditionNotes: [String] = [],
        reflectiveSurfaceNotes: [String] = [],
        accessRules: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.workflowName = workflowName
        self.taskSteps = taskSteps
        self.targetKPI = targetKPI
        self.zone = zone
        self.shift = shift
        self.owner = owner
        self.facilityTemplate = facilityTemplate
        self.requiredCoverageAreas = requiredCoverageAreas
        self.benchmarkStations = benchmarkStations
        self.adjacentSystems = adjacentSystems
        self.privacySecurityLimits = privacySecurityLimits
        self.knownBlockers = knownBlockers
        self.nonRoutineModes = nonRoutineModes
        self.peopleTrafficNotes = peopleTrafficNotes
        self.captureRestrictions = captureRestrictions
        self.lightingWindows = lightingWindows
        self.shiftTrafficWindows = shiftTrafficWindows
        self.movableObstacles = movableObstacles
        self.floorConditionNotes = floorConditionNotes
        self.reflectiveSurfaceNotes = reflectiveSurfaceNotes
        self.accessRules = accessRules
    }

    var isComplete: Bool {
        let hasWorkflow = !(workflowName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasSteps = !taskSteps.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.isEmpty
        let hasZoneOrOwner = !((zone?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) && (owner?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true))
        return hasWorkflow && hasSteps && hasZoneOrOwner
    }
}

struct CaptureScaffoldingPacket: Equatable, Codable {
    let schemaVersion: String
    let scaffoldingUsed: [String]
    let coveragePlan: [String]
    let calibrationAssets: [String]
    let scaleAnchorAssets: [String]
    let checkpointAssets: [String]
    let validatedScaleMeters: Double?
    let validatedPoseCoverage: Double?
    let hiddenZoneBound: Double?
    let uncertaintyPriors: [String: Double]

    init(
        schemaVersion: String = "v1",
        scaffoldingUsed: [String] = [],
        coveragePlan: [String] = [],
        calibrationAssets: [String] = [],
        scaleAnchorAssets: [String] = [],
        checkpointAssets: [String] = [],
        validatedScaleMeters: Double? = nil,
        validatedPoseCoverage: Double? = nil,
        hiddenZoneBound: Double? = nil,
        uncertaintyPriors: [String: Double] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.scaffoldingUsed = scaffoldingUsed
        self.coveragePlan = coveragePlan
        self.calibrationAssets = calibrationAssets
        self.scaleAnchorAssets = scaleAnchorAssets
        self.checkpointAssets = checkpointAssets
        self.validatedScaleMeters = validatedScaleMeters
        self.validatedPoseCoverage = validatedPoseCoverage
        self.hiddenZoneBound = hiddenZoneBound
        self.uncertaintyPriors = uncertaintyPriors
    }

    var hasValidatedMetricBundle: Bool {
        guard !calibrationAssets.isEmpty,
              !scaleAnchorAssets.isEmpty,
              !checkpointAssets.isEmpty,
              let validatedScaleMeters,
              validatedScaleMeters > 0,
              let validatedPoseCoverage,
              validatedPoseCoverage >= 0.7,
              let hiddenZoneBound,
              hiddenZoneBound <= 0.35 else {
            return false
        }
        return true
    }
}

struct SiteGeoPoint: Equatable, Codable {
    let latitude: Double
    let longitude: Double
    let accuracyM: Double
}

struct SiteIdentity: Equatable, Codable {
    let siteId: String
    let siteIdSource: String   // "buyer_request" | "site_submission" | "open_capture"
    let placeId: String?
    let siteName: String?
    let addressFull: String?
    let geo: SiteGeoPoint?
    let buildingId: String?
    let floorId: String?
    let roomId: String?
    let zoneId: String?
}

struct CaptureTopologyMetadata: Equatable, Codable {
    let captureSessionId: String
    let routeId: String
    let passId: String
    let passIndex: Int
    let intendedPassRole: String   // "primary" | "revisit" | "loop_closure" | "critical_zone_revisit"
    let entryAnchorId: String?
    let returnAnchorId: String?
    let entryAnchorTCaptureSec: Double?      // t_device_sec midpoint of detected entry hold
    let entryAnchorHoldDurationSec: Double?  // seconds held at entry anchor
}

struct CaptureModeMetadata: Equatable, Codable {
    let requestedMode: String    // "qualification_only" | "site_world_candidate"
    let resolvedMode: String     // may be downgraded at finalization
    let downgradeReason: String?
}

struct SceneMemoryCaptureMetadata: Equatable, Codable {
    let continuityScore: Double?
    let lightingConsistency: String?
    let dynamicObjectDensity: String?
    let operatorNotes: [String]
    let inaccessibleAreas: [String]

    init(
        continuityScore: Double? = nil,
        lightingConsistency: String? = nil,
        dynamicObjectDensity: String? = nil,
        operatorNotes: [String] = [],
        inaccessibleAreas: [String] = []
    ) {
        self.continuityScore = continuityScore
        self.lightingConsistency = lightingConsistency
        self.dynamicObjectDensity = dynamicObjectDensity
        self.operatorNotes = operatorNotes
        self.inaccessibleAreas = inaccessibleAreas
    }
}

enum CaptureConsentStatus: String, Codable {
    case documented
    case policyOnly = "policy_only"
    case unknown
}

struct CaptureRightsMetadata: Equatable, Codable {
    let derivedSceneGenerationAllowed: Bool
    let dataLicensingAllowed: Bool
    let payoutEligible: Bool
    let consentStatus: CaptureConsentStatus
    let permissionDocumentURI: String?
    let consentScope: [String]
    let consentNotes: [String]

    init(
        derivedSceneGenerationAllowed: Bool = false,
        dataLicensingAllowed: Bool = false,
        payoutEligible: Bool = false,
        consentStatus: CaptureConsentStatus = .unknown,
        permissionDocumentURI: String? = nil,
        consentScope: [String] = [],
        consentNotes: [String] = []
    ) {
        self.derivedSceneGenerationAllowed = derivedSceneGenerationAllowed
        self.dataLicensingAllowed = dataLicensingAllowed
        self.payoutEligible = payoutEligible
        self.consentStatus = consentStatus
        self.permissionDocumentURI = permissionDocumentURI
        self.consentScope = consentScope
        self.consentNotes = consentNotes
    }
}

struct CaptureUploadMetadata: Identifiable, Equatable, Codable {
    enum CaptureSource: String, Codable {
        case iphoneVideo
        case metaGlasses
    }

    enum SpecialTaskType: String, Codable {
        case curatedNearby = "curated_nearby"
        case buyerRequested = "buyer_requested_special_task"
        case operatorApproved = "operator_approved_on_demand"
        case openCapture = "open_capture"
    }

    let id: UUID
    let targetId: String?
    let reservationId: String?
    let jobId: String
    let captureJobId: String?
    let buyerRequestId: String?
    let siteSubmissionId: String?
    let regionId: String?
    let creatorId: String
    let capturedAt: Date
    var uploadedAt: Date?
    let captureSource: CaptureSource
    let specialTaskType: SpecialTaskType?
    let priorityWeight: Double?
    let quotedPayoutCents: Int?
    let rightsProfile: String?
    let requestedOutputs: [String]
    var intakePacket: QualificationIntakePacket?
    var intakeMetadata: CaptureIntakeMetadata?
    var taskHypothesis: CaptureTaskHypothesis?
    let scaffoldingPacket: CaptureScaffoldingPacket?
    let captureModality: String?
    let evidenceTier: String?
    let captureContextHint: String?
    let sceneMemory: SceneMemoryCaptureMetadata?
    let captureRights: CaptureRightsMetadata?
    let siteIdentity: SiteIdentity?
    let captureTopology: CaptureTopologyMetadata?
    let captureMode: CaptureModeMetadata?
}

struct CaptureUploadRequest: Equatable {
    let packageURL: URL
    var metadata: CaptureUploadMetadata
}

protocol CaptureUploadServiceProtocol: AnyObject {
    var events: AnyPublisher<CaptureUploadService.Event, Never> { get }
    func enqueue(_ request: CaptureUploadRequest)
    func retryUpload(id: UUID)
    func cancelUpload(id: UUID)
}

final class CaptureUploadService: CaptureUploadServiceProtocol {
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
        case missingStructuredIntake

        var errorDescription: String? {
            switch self {
            case .fileMissing:
                return "The recorded file could not be found."
            case .cancelled:
                return "Upload cancelled."
            case .uploadFailed:
                return "Upload failed. Please try again."
            case .missingStructuredIntake:
                return "Structured intake is required before upload."
            }
        }
    }

    var events: AnyPublisher<Event, Never> {
        subject.eraseToAnyPublisher()
    }

    private struct UploadRecord {
        var request: CaptureUploadRequest
        var task: Task<Void, Never>?
    }

    private let queue = DispatchQueue(label: "com.blueprint.captureUploadService")
    private var uploads: [UUID: UploadRecord] = [:]
    private let subject = PassthroughSubject<Event, Never>()
    private let storageBucketURL = "gs://blueprint-8c1ca.appspot.com"
    private let finalizer: CaptureBundleFinalizerProtocol

    init(finalizer: CaptureBundleFinalizerProtocol = CaptureBundleFinalizer()) {
        self.finalizer = finalizer
    }

    func enqueue(_ request: CaptureUploadRequest) {
        queue.async {
            self.storeAndBeginUpload(request: request)
        }
    }

    func retryUpload(id: UUID) {
        queue.async {
            guard let record = self.uploads[id] else { return }
            record.task?.cancel()
            self.uploads[id] = record
            var request = record.request
            request.metadata.uploadedAt = nil
            self.storeAndBeginUpload(request: request)
        }
    }

    func cancelUpload(id: UUID) {
        queue.async {
            guard var record = self.uploads[id] else { return }
            record.task?.cancel()
            record.task = nil
            self.uploads[id] = record
            self.subject.send(.failed(record.request, .cancelled))
        }
    }

    private func storeAndBeginUpload(request: CaptureUploadRequest) {
        var record = UploadRecord(request: request, task: nil)
        uploads[request.metadata.id] = record
        subject.send(.queued(request))

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performUpload(for: request.metadata.id)
        }
        record.task = task
        uploads[request.metadata.id] = record
    }

    private func performUpload(for id: UUID) async {
        guard let record = queue.sync(execute: { uploads[id] }) else { return }
        let packageURL = record.request.packageURL
        print("🚀 [UploadService] performUpload start id=\(id) url=\(packageURL.path)")

        guard record.request.metadata.intakePacket?.isComplete == true else {
            queue.async {
                guard var failingRecord = self.uploads[id] else { return }
                failingRecord.task = nil
                self.uploads[id] = failingRecord
                self.subject.send(.failed(failingRecord.request, .missingStructuredIntake))
            }
            return
        }

        guard FileManager.default.fileExists(atPath: packageURL.path) else {
            print("❌ [UploadService] package missing at path=\(packageURL.path)")
            queue.async {
                guard var failingRecord = self.uploads[id] else { return }
                failingRecord.task = nil
                self.uploads[id] = failingRecord
                self.subject.send(.failed(failingRecord.request, .fileMissing))
            }
            return
        }

        #if canImport(FirebaseStorage)
        let storage = Storage.storage(url: storageBucketURL)
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
                request: record.request
            )
            if !ok { return }
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

            let uploadTask = ref.putFile(from: packageURL, metadata: metadata)

            // Observe progress
            let progressHandle = uploadTask.observe(.progress) { [weak self] snapshot in
                guard let self else { return }
                let prog = Double(snapshot.progress?.fractionCompleted ?? 0)
                self.subject.send(.progress(id: id, progress: min(max(prog, 0.0), 0.999)))
            }

            // Await completion
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let successHandle = uploadTask.observe(.success) { [weak self] _ in
                    guard let self else { continuation.resume(); return }
                    self.queue.async {
                        guard var latestRecord = self.uploads[id] else { continuation.resume(); return }
                        latestRecord.request.metadata.uploadedAt = Date()
                        latestRecord.task = nil
                        self.uploads[id] = latestRecord
                        self.subject.send(.progress(id: id, progress: 1.0))
                        self.subject.send(.completed(latestRecord.request))
                        self.writeSubmissionRecord(for: latestRecord.request)
                        print("✅ [UploadService] Upload finished id=\(id)")
                    }
                    continuation.resume()
                }

                let failureHandle = uploadTask.observe(.failure) { [weak self] _ in
                    guard let self else { continuation.resume(); return }
                    self.queue.async {
                        guard var failingRecord = self.uploads[id] else { continuation.resume(); return }
                        failingRecord.task = nil
                        self.uploads[id] = failingRecord
                        self.subject.send(.failed(failingRecord.request, .uploadFailed))
                        print("❌ [UploadService] Upload failed id=\(id)")
                    }
                    continuation.resume()
                }

                // Keep observers alive until continuation resumes
                _ = (progressHandle, successHandle, failureHandle)
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
    private func uploadDirectory(storage: Storage, localDirectory: URL, remoteBasePath: String, id: UUID, request: CaptureUploadRequest) async -> Bool {
        print("📁 [UploadService] Preparing directory upload at \(localDirectory.path)")
        do {
            _ = try finalizer.finalize(
                request: request,
                mode: .upload(
                    remoteRawPrefix: remoteBasePath,
                    videoURI: storageBucketURL + "/" + remoteBasePath + "walkthrough.mov"
                )
            )
        } catch let error as CaptureBundleFinalizer.FinalizationError {
            let uploadError: UploadError = error == .missingStructuredIntake ? .missingStructuredIntake : .uploadFailed
            self.queue.async {
                guard var failingRecord = self.uploads[id] else { return }
                failingRecord.task = nil
                self.uploads[id] = failingRecord
                self.subject.send(.failed(failingRecord.request, uploadError))
            }
            return false
        } catch {
            self.queue.async {
                guard var failingRecord = self.uploads[id] else { return }
                failingRecord.task = nil
                self.uploads[id] = failingRecord
                self.subject.send(.failed(failingRecord.request, .uploadFailed))
            }
            return false
        }
        // Gather files
        guard let enumerator = FileManager.default.enumerator(at: localDirectory, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles]) else {
            print("❌ [UploadService] Failed to enumerate directory at \(localDirectory.path)")
            self.queue.async {
                guard var failingRecord = self.uploads[id] else { return }
                failingRecord.task = nil
                self.uploads[id] = failingRecord
                self.subject.send(.failed(failingRecord.request, .uploadFailed))
            }
            return false
        }

        var files: [URL] = []
        var totalBytes: Int64 = 0
        let completionFilename = "capture_upload_complete.json"
        for case let url as URL in enumerator {
            var isRegular: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isRegular), !isRegular.boolValue {
                files.append(url)
                if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                    totalBytes += Int64(size)
                }
            }
        }
        files.sort { $0.path < $1.path }
        if let markerIndex = files.firstIndex(where: { $0.lastPathComponent == completionFilename }) {
            let marker = files.remove(at: markerIndex)
            files.append(marker)
        }
        guard !files.isEmpty, totalBytes > 0 else {
            print("❌ [UploadService] No files found to upload under \(localDirectory.path)")
            self.queue.async {
                guard var failingRecord = self.uploads[id] else { return }
                failingRecord.task = nil
                self.uploads[id] = failingRecord
                self.subject.send(.failed(failingRecord.request, .uploadFailed))
            }
            return false
        }

        var uploadedBytes: Int64 = 0
        print("📁 [UploadService] Uploading \(files.count) files (\(totalBytes) bytes) to basePath=\(remoteBasePath)")
        for file in files {
            if Task.isCancelled { return false }
            let relPath = file.path.replacingOccurrences(of: localDirectory.path + "/", with: "")
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

            let uploadTask = ref.putFile(from: file, metadata: md)

            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let progressHandle = uploadTask.observe(.progress) { [weak self] snapshot in
                    guard let self else { return }
                    let completed = snapshot.progress?.completedUnitCount ?? 0
                    let fraction = Double(uploadedBytes + completed) / Double(max(1, totalBytes))
                    self.subject.send(.progress(id: id, progress: min(max(fraction, 0.0), 0.999)))
                }
                let successHandle = uploadTask.observe(.success) { _ in
                    let completed = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? 0
                    uploadedBytes += completed
                    continuation.resume()
                }
                let failureHandle = uploadTask.observe(.failure) { [weak self] _ in
                    guard let self else { continuation.resume(); return }
                    self.queue.async {
                        guard var failingRecord = self.uploads[id] else { continuation.resume(); return }
                        failingRecord.task = nil
                        self.uploads[id] = failingRecord
                        self.subject.send(.failed(failingRecord.request, .uploadFailed))
                    }
                    continuation.resume()
                }
                _ = (progressHandle, successHandle, failureHandle)
            }
        }

        self.queue.async {
            guard var latestRecord = self.uploads[id] else { return }
            latestRecord.request.metadata.uploadedAt = Date()
            latestRecord.task = nil
            self.uploads[id] = latestRecord
            self.subject.send(.progress(id: id, progress: 1.0))
            self.subject.send(.completed(latestRecord.request))
            self.writeSubmissionRecord(for: latestRecord.request)
        }
        return true
    }

    /// Writes a `capture_submissions/{captureId}` document to Firestore when a capture
    /// is successfully uploaded. This is the record the `onCaptureApproved` Cloud Function
    /// watches — status starts as "submitted" and is updated to "approved"/"paid" by the
    /// backend via the `updateCaptureStatus` Cloud Function.
    private func writeSubmissionRecord(for request: CaptureUploadRequest) {
        #if canImport(FirebaseFirestore)
        let captureId = CaptureBundleContext.captureIdentifier(for: request)
        let sceneId = CaptureBundleContext.sceneIdentifier(for: request)
        let db = Firestore.firestore()
        let docRef = db.collection("capture_submissions").document(captureId)

        let payload: [String: Any] = [
            "capture_id": captureId,
            "scene_id": sceneId,
            "creator_id": request.metadata.creatorId,
            "job_id": request.metadata.jobId,
            "status": "submitted",
            "payout_cents": request.metadata.quotedPayoutCents ?? 0,
            "capture_source": request.metadata.captureSource.rawValue,
            "submitted_at": Timestamp(date: request.metadata.uploadedAt ?? Date()),
            "created_at": Timestamp(date: Date())
        ]
        docRef.setData(payload, merge: true) { error in
            if let error = error {
                print("⚠️ [UploadService] Failed to write capture_submissions record: \(error.localizedDescription)")
            } else {
                print("✅ [UploadService] capture_submissions/\(captureId) written")
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
    #endif
}
