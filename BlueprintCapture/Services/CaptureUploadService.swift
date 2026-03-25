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
    let siteVisitId: String?
    let coordinateFrameSessionId: String?
    let arkitSessionId: String?

    init(
        captureSessionId: String,
        routeId: String,
        passId: String,
        passIndex: Int,
        intendedPassRole: String,
        entryAnchorId: String?,
        returnAnchorId: String?,
        entryAnchorTCaptureSec: Double?,
        entryAnchorHoldDurationSec: Double?,
        siteVisitId: String? = nil,
        coordinateFrameSessionId: String? = nil,
        arkitSessionId: String? = nil
    ) {
        self.captureSessionId = captureSessionId
        self.routeId = routeId
        self.passId = passId
        self.passIndex = passIndex
        self.intendedPassRole = intendedPassRole
        self.entryAnchorId = entryAnchorId
        self.returnAnchorId = returnAnchorId
        self.entryAnchorTCaptureSec = entryAnchorTCaptureSec
        self.entryAnchorHoldDurationSec = entryAnchorHoldDurationSec
        self.siteVisitId = siteVisitId
        self.coordinateFrameSessionId = coordinateFrameSessionId
        self.arkitSessionId = arkitSessionId
    }
}

struct CaptureModeMetadata: Equatable, Codable {
    let requestedMode: String    // "qualification_only" | "site_world_candidate"
    let resolvedMode: String     // may be downgraded at finalization
    let downgradeReason: String?
}

enum CaptureSemanticAnchorType: String, Codable, CaseIterable {
    case entrance
    case doorway
    case corridorIntersection = "corridor_intersection"
    case dockTurn = "dock_turn"
    case handoffPoint = "handoff_point"
    case controlPanel = "control_panel"
    case floorTransition = "floor_transition"
    case restrictedBoundary = "restricted_boundary"
    case exitPoint = "exit_point"

    var displayLabel: String {
        switch self {
        case .entrance:
            return "Entrance"
        case .doorway:
            return "Doorway"
        case .corridorIntersection:
            return "Intersection"
        case .dockTurn:
            return "Dock Turn"
        case .handoffPoint:
            return "Handoff"
        case .controlPanel:
            return "Control Panel"
        case .floorTransition:
            return "Floor Transition"
        case .restrictedBoundary:
            return "Restricted Boundary"
        case .exitPoint:
            return "Exit"
        }
    }
}

struct CaptureSemanticAnchorEvent: Equatable, Codable, Identifiable {
    let id: String
    let anchorType: CaptureSemanticAnchorType
    let label: String?
    let frameId: String?
    let tCaptureSec: Double?
    let coordinateFrameSessionId: String?
    let notes: String?

    init(
        id: String = UUID().uuidString,
        anchorType: CaptureSemanticAnchorType,
        label: String? = nil,
        frameId: String? = nil,
        tCaptureSec: Double? = nil,
        coordinateFrameSessionId: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.anchorType = anchorType
        self.label = label
        self.frameId = frameId
        self.tCaptureSec = tCaptureSec
        self.coordinateFrameSessionId = coordinateFrameSessionId
        self.notes = notes
    }
}

struct SceneMemoryCaptureMetadata: Equatable, Codable {
    let continuityScore: Double?
    let lightingConsistency: String?
    let dynamicObjectDensity: String?
    let operatorNotes: [String]
    let inaccessibleAreas: [String]
    let semanticAnchorsObserved: [String]
    let relocalizationCount: Int?
    let overlapCheckpointCount: Int?

    init(
        continuityScore: Double? = nil,
        lightingConsistency: String? = nil,
        dynamicObjectDensity: String? = nil,
        operatorNotes: [String] = [],
        inaccessibleAreas: [String] = [],
        semanticAnchorsObserved: [String] = [],
        relocalizationCount: Int? = nil,
        overlapCheckpointCount: Int? = nil
    ) {
        self.continuityScore = continuityScore
        self.lightingConsistency = lightingConsistency
        self.dynamicObjectDensity = dynamicObjectDensity
        self.operatorNotes = operatorNotes
        self.inaccessibleAreas = inaccessibleAreas
        self.semanticAnchorsObserved = semanticAnchorsObserved
        self.relocalizationCount = relocalizationCount
        self.overlapCheckpointCount = overlapCheckpointCount
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

enum CaptureAuthorityLevel: String, Codable {
    case authoritativeRaw = "authoritative_raw"
    case rawTrackingOnly = "raw_tracking_only"
    case diagnosticOnly = "diagnostic_only"
    case notAvailable = "not_available"
    case derivedLaterExpected = "derived_later_expected"
}

struct CaptureCapabilitiesMetadata: Equatable, Codable {
    let cameraPose: Bool
    let cameraIntrinsics: Bool
    let depth: Bool
    let depthConfidence: Bool
    let mesh: Bool
    let pointCloud: Bool
    let planes: Bool
    let featurePoints: Bool
    let trackingState: Bool
    let relocalizationEvents: Bool
    let lightEstimate: Bool
    let motion: Bool
    let motionAuthoritative: Bool
    let companionPhonePose: Bool
    let companionPhoneIntrinsics: Bool
    let companionPhoneCalibration: Bool
    let poseRows: Int
    let intrinsicsValid: Bool
    let depthFrames: Int
    let confidenceFrames: Int
    let meshFiles: Int
    let pointCloudSamples: Int
    let planeRows: Int
    let featurePointRows: Int
    let trackingStateRows: Int
    let relocalizationEventRows: Int
    let lightEstimateRows: Int
    let motionSamples: Int
    let poseAuthority: CaptureAuthorityLevel
    let intrinsicsAuthority: CaptureAuthorityLevel
    let depthAuthority: CaptureAuthorityLevel
    let motionAuthority: CaptureAuthorityLevel
    let motionProvenance: String?
    let geometrySource: String?
    let geometryExpectedDownstream: Bool
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
    let semanticAnchors: [CaptureSemanticAnchorEvent]

    init(
        id: UUID,
        targetId: String?,
        reservationId: String?,
        jobId: String,
        captureJobId: String?,
        buyerRequestId: String?,
        siteSubmissionId: String?,
        regionId: String?,
        creatorId: String,
        capturedAt: Date,
        uploadedAt: Date?,
        captureSource: CaptureSource,
        specialTaskType: SpecialTaskType?,
        priorityWeight: Double?,
        quotedPayoutCents: Int?,
        rightsProfile: String?,
        requestedOutputs: [String],
        intakePacket: QualificationIntakePacket?,
        intakeMetadata: CaptureIntakeMetadata?,
        taskHypothesis: CaptureTaskHypothesis?,
        scaffoldingPacket: CaptureScaffoldingPacket?,
        captureModality: String?,
        evidenceTier: String?,
        captureContextHint: String?,
        sceneMemory: SceneMemoryCaptureMetadata?,
        captureRights: CaptureRightsMetadata?,
        siteIdentity: SiteIdentity?,
        captureTopology: CaptureTopologyMetadata?,
        captureMode: CaptureModeMetadata?,
        semanticAnchors: [CaptureSemanticAnchorEvent] = []
    ) {
        self.id = id
        self.targetId = targetId
        self.reservationId = reservationId
        self.jobId = jobId
        self.captureJobId = captureJobId
        self.buyerRequestId = buyerRequestId
        self.siteSubmissionId = siteSubmissionId
        self.regionId = regionId
        self.creatorId = creatorId
        self.capturedAt = capturedAt
        self.uploadedAt = uploadedAt
        self.captureSource = captureSource
        self.specialTaskType = specialTaskType
        self.priorityWeight = priorityWeight
        self.quotedPayoutCents = quotedPayoutCents
        self.rightsProfile = rightsProfile
        self.requestedOutputs = requestedOutputs
        self.intakePacket = intakePacket
        self.intakeMetadata = intakeMetadata
        self.taskHypothesis = taskHypothesis
        self.scaffoldingPacket = scaffoldingPacket
        self.captureModality = captureModality
        self.evidenceTier = evidenceTier
        self.captureContextHint = captureContextHint
        self.sceneMemory = sceneMemory
        self.captureRights = captureRights
        self.siteIdentity = siteIdentity
        self.captureTopology = captureTopology
        self.captureMode = captureMode
        self.semanticAnchors = semanticAnchors
    }
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
        case submissionRegistrationFailed

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
            case .submissionRegistrationFailed:
                return "Upload reached storage but Blueprint could not register the capture submission. Check Firebase Auth and Firestore production config before retrying."
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
            markUploadFailed(id: id, attempt: attempt, error: uploadError)
            return false
        } catch {
            markUploadFailed(id: id, attempt: attempt, error: .uploadFailed)
            return false
        }
        // Gather files
        guard let enumerator = FileManager.default.enumerator(at: localDirectory, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles]) else {
            print("❌ [UploadService] Failed to enumerate directory at \(localDirectory.path)")
            markUploadFailed(id: id, attempt: attempt, error: .uploadFailed)
            return false
        }

        var files: [URL] = []
        var totalBytes: Int64 = 0
        let completionFilename = "capture_upload_complete.json"
        var completionMarkerFile: URL?
        for case let url as URL in enumerator {
            var isRegular: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isRegular), !isRegular.boolValue {
                if url.lastPathComponent == completionFilename {
                    completionMarkerFile = url
                } else {
                    files.append(url)
                    if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                        totalBytes += Int64(size)
                    }
                }
            }
        }
        files.sort { $0.path < $1.path }
        guard !files.isEmpty || completionMarkerFile != nil else {
            print("❌ [UploadService] No files found to upload under \(localDirectory.path)")
            markUploadFailed(id: id, attempt: attempt, error: .uploadFailed)
            return false
        }

        var uploadedBytes: Int64 = 0
        print("📁 [UploadService] Uploading \(files.count + (completionMarkerFile == nil ? 0 : 1)) files (\(totalBytes) bytes + completion marker) to basePath=\(remoteBasePath)")
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
                print("❌ [UploadService] File upload failed path=\(remotePath) error=\(uploadError?.localizedDescription ?? "unknown")")
                markUploadFailed(id: id, attempt: attempt, error: .uploadFailed)
                return false
            }
            let completed = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? 0
            uploadedBytes += completed
        }

        if let completionMarkerFile {
            let completionRemotePath = remoteBasePath + completionFilename
            let completionRef = storage.reference(withPath: completionRemotePath)
            let completionUploaded = await uploadCompletionMarker(
                at: completionMarkerFile,
                to: completionRef,
                id: id,
                attempt: attempt
            )
            guard completionUploaded else {
                print("❌ [UploadService] Completion marker upload failed path=\(completionRemotePath)")
                markUploadFailed(id: id, attempt: attempt, error: .uploadFailed)
                return false
            }
        }

        return true
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
        let sceneId = CaptureBundleContext.sceneIdentifier(for: request)
        let db = Firestore.firestore()
        let docRef = db.collection("capture_submissions").document(captureId)

        let payload: [String: Any] = [
            "capture_id": captureId,
            "scene_id": sceneId,
            "creator_id": request.metadata.creatorId,
            "job_id": request.metadata.jobId,
            "capture_source": request.metadata.captureSource.rawValue,
            "submitted_at": Timestamp(date: request.metadata.uploadedAt ?? Date()),
            "created_at": Timestamp(date: Date())
        ]
        return await withCheckedContinuation { continuation in
            docRef.setData(payload, merge: true) { error in
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
        }
    }
}

enum CaptureUploadErrorClassifier {
    static func isAlreadyFinalized(_ error: Error) -> Bool {
        errorMessages(from: error).contains { message in
            let normalized = message.lowercased()
            return normalized.contains("already been finalized") || normalized.contains("already finalized")
        }
    }

    private static func errorMessages(from error: Error) -> [String] {
        let nsError = error as NSError
        var messages: [String] = [nsError.localizedDescription]

        if let failureReason = nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String {
            messages.append(failureReason)
        }
        if let recoverySuggestion = nsError.userInfo[NSLocalizedRecoverySuggestionErrorKey] as? String {
            messages.append(recoverySuggestion)
        }
        if let payload = nsError.userInfo["data"] as? Data,
           let body = String(data: payload, encoding: .utf8) {
            messages.append(body)
        }
        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            messages.append(contentsOf: errorMessages(from: underlyingError))
        }

        return messages
    }
}
