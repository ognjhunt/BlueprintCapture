import Foundation
import Combine
#if canImport(FirebaseStorage)
import FirebaseStorage
#endif

struct CaptureUploadMetadata: Identifiable, Codable, Equatable {
    let id: UUID
    let submissionId: String
    let siteId: String
    let taskId: String
    let capturePassId: String
    let creatorId: String
    let capturedAt: Date
    var uploadedAt: Date?
}

struct CaptureUploadArtifact: Identifiable, Equatable {
    enum Role: String, Equatable {
        case legacyPackage
        case rawVideo
        case motionLog
        case capturePackageManifest
        case rawManifest
        case arKitFrameLog
        case arKitPoses
        case arKitIntrinsics
        case arKitDepth
        case arKitConfidence
        case arKitMesh
        case keyframe
        case framesIndex
        case qaReport
        case captureDescriptor
    }

    let localFileURL: URL
    let storagePath: String
    let contentType: String
    let role: Role
    let required: Bool

    var id: String { storagePath }

    static func legacyPackage(localFileURL: URL, storagePath: String) -> CaptureUploadArtifact {
        CaptureUploadArtifact(
            localFileURL: localFileURL,
            storagePath: storagePath,
            contentType: "application/zip",
            role: .legacyPackage,
            required: true
        )
    }
}

struct CaptureUploadRequest: Equatable {
    let packageURL: URL
    var metadata: CaptureUploadMetadata
    var artifacts: [CaptureUploadArtifact]

    init(packageURL: URL, metadata: CaptureUploadMetadata, artifacts: [CaptureUploadArtifact]? = nil) {
        self.packageURL = packageURL
        self.metadata = metadata
        self.artifacts = artifacts ?? [
            .legacyPackage(
                localFileURL: packageURL,
                storagePath: CaptureUploadService.storagePath(forLegacyPackageAt: packageURL, metadata: metadata)
            )
        ]
    }
}

protocol CaptureUploadServiceProtocol: AnyObject {
    var events: AnyPublisher<CaptureUploadService.Event, Never> { get }
    func enqueue(_ request: CaptureUploadRequest)
    func retryUpload(id: UUID)
    func cancelUpload(id: UUID)
}

final class CaptureUploadService: CaptureUploadServiceProtocol {
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

        var errorDescription: String? {
            switch self {
            case .fileMissing:
                return "The recorded file could not be found."
            case .cancelled:
                return "Upload cancelled."
            case .uploadFailed:
                return "Upload failed. Please try again."
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

    func enqueue(_ request: CaptureUploadRequest) {
        queue.async {
            self.storeAndBeginUpload(request: request)
        }
    }

    func retryUpload(id: UUID) {
        queue.async {
            guard var record = self.uploads[id] else { return }
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

    static func customMetadata(for metadata: CaptureUploadMetadata) -> [String: String] {
        [
            "submission_id": metadata.submissionId,
            "site_id": metadata.siteId,
            "task_id": metadata.taskId,
            "capture_pass_id": metadata.capturePassId,
            "creator_id": metadata.creatorId,
            "captured_at": ISO8601DateFormatter().string(from: metadata.capturedAt)
        ]
    }

    static func storagePath(for request: CaptureUploadRequest) -> String {
        storagePath(forLegacyPackageAt: request.packageURL, metadata: request.metadata)
    }

    static func storagePath(forLegacyPackageAt packageURL: URL, metadata: CaptureUploadMetadata) -> String {
        let timestampFormatter = ISO8601DateFormatter()
        timestampFormatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let ts = timestampFormatter.string(from: metadata.capturedAt).replacingOccurrences(of: ":", with: "-")
        let basename = packageURL.lastPathComponent
        return "site_submissions/\(metadata.submissionId)/sites/\(metadata.siteId)/tasks/\(metadata.taskId)/capture_passes/\(metadata.capturePassId)/\(ts)-\(basename)"
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
        let artifacts = record.request.artifacts

        guard !artifacts.isEmpty else {
            queue.async {
                guard var failingRecord = self.uploads[id] else { return }
                failingRecord.task = nil
                self.uploads[id] = failingRecord
                self.subject.send(.failed(failingRecord.request, .fileMissing))
            }
            return
        }

        let missingArtifact = artifacts.first {
            $0.required && !FileManager.default.fileExists(atPath: $0.localFileURL.path)
        }
        guard missingArtifact == nil else {
            queue.async {
                guard var failingRecord = self.uploads[id] else { return }
                failingRecord.task = nil
                self.uploads[id] = failingRecord
                self.subject.send(.failed(failingRecord.request, .fileMissing))
            }
            return
        }

        #if canImport(FirebaseStorage)
        do {
            for (index, artifact) in artifacts.enumerated() {
                if Task.isCancelled { return }
                try await uploadArtifact(
                    artifact,
                    metadata: record.request.metadata,
                    uploadID: id,
                    completedArtifactCount: index,
                    totalArtifactCount: artifacts.count
                )
            }
            queue.async {
                guard var latestRecord = self.uploads[id] else { return }
                latestRecord.request.metadata.uploadedAt = Date()
                latestRecord.task = nil
                self.uploads[id] = latestRecord
                self.subject.send(.progress(id: id, progress: 1.0))
                self.subject.send(.completed(latestRecord.request))
            }
        } catch {
            queue.async {
                guard var failingRecord = self.uploads[id] else { return }
                failingRecord.task = nil
                self.uploads[id] = failingRecord
                self.subject.send(.failed(failingRecord.request, .uploadFailed))
            }
        }
        #else
        let totalArtifactCount = max(artifacts.count, 1)
        for (artifactIndex, _) in artifacts.enumerated() {
            let steps = 6
            for step in 1...steps {
                try? await Task.sleep(nanoseconds: 100_000_000)
                if Task.isCancelled { return }
                let artifactProgress = Double(step) / Double(steps)
                let progress = (Double(artifactIndex) + artifactProgress) / Double(totalArtifactCount)
                subject.send(.progress(id: id, progress: min(progress, 0.999)))
            }
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
    private func uploadArtifact(
        _ artifact: CaptureUploadArtifact,
        metadata: CaptureUploadMetadata,
        uploadID: UUID,
        completedArtifactCount: Int,
        totalArtifactCount: Int
    ) async throws {
        let storage = Storage.storage()
        let ref = storage.reference(withPath: artifact.storagePath)
        let uploadMetadata = StorageMetadata()
        uploadMetadata.contentType = artifact.contentType
        uploadMetadata.customMetadata = Self.customMetadata(for: metadata)
        let uploadTask = ref.putFile(from: artifact.localFileURL, metadata: uploadMetadata)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var progressHandle = ""
            var successHandle = ""
            var failureHandle = ""

            progressHandle = uploadTask.observe(.progress) { [weak self] snapshot in
                guard let self else { return }
                let artifactProgress = Double(snapshot.progress?.fractionCompleted ?? 0)
                let overall = (Double(completedArtifactCount) + artifactProgress) / Double(max(totalArtifactCount, 1))
                self.subject.send(.progress(id: uploadID, progress: min(max(overall, 0.0), 0.999)))
            }

            successHandle = uploadTask.observe(.success) { _ in
                uploadTask.removeObserver(withHandle: progressHandle)
                uploadTask.removeObserver(withHandle: successHandle)
                uploadTask.removeObserver(withHandle: failureHandle)
                continuation.resume()
            }

            failureHandle = uploadTask.observe(.failure) { _ in
                uploadTask.removeObserver(withHandle: progressHandle)
                uploadTask.removeObserver(withHandle: successHandle)
                uploadTask.removeObserver(withHandle: failureHandle)
                continuation.resume(throwing: UploadError.uploadFailed)
            }

            _ = (progressHandle, successHandle, failureHandle)
        }
    }
    #endif
}
