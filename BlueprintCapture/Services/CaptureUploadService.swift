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
        let timestampFormatter = ISO8601DateFormatter()
        timestampFormatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let ts = timestampFormatter.string(from: request.metadata.capturedAt).replacingOccurrences(of: ":", with: "-")
        let basename = request.packageURL.lastPathComponent
        return "site_submissions/\(request.metadata.submissionId)/sites/\(request.metadata.siteId)/tasks/\(request.metadata.taskId)/capture_passes/\(request.metadata.capturePassId)/\(ts)-\(basename)"
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

        guard FileManager.default.fileExists(atPath: packageURL.path) else {
            queue.async {
                guard var failingRecord = self.uploads[id] else { return }
                failingRecord.task = nil
                self.uploads[id] = failingRecord
                self.subject.send(.failed(failingRecord.request, .fileMissing))
            }
            return
        }

        #if canImport(FirebaseStorage)
        let storage = Storage.storage()
        let path = Self.storagePath(for: record.request)
        let ref = storage.reference(withPath: path)

        let metadata = StorageMetadata()
        metadata.contentType = "application/zip"
        metadata.customMetadata = Self.customMetadata(for: record.request.metadata)

        let uploadTask = ref.putFile(from: packageURL, metadata: metadata)

        let progressHandle = uploadTask.observe(.progress) { [weak self] snapshot in
            guard let self else { return }
            let prog = Double(snapshot.progress?.fractionCompleted ?? 0)
            self.subject.send(.progress(id: id, progress: min(max(prog, 0.0), 0.999)))
        }

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
                }
                continuation.resume()
            }

            _ = (progressHandle, successHandle, failureHandle)
        }
        #else
        let steps = 12
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
}
