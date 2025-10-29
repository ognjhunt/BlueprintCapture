import Foundation
import Combine
#if canImport(FirebaseStorage)
import FirebaseStorage
#endif

struct CaptureUploadMetadata: Identifiable, Equatable {
    let id: UUID
    let targetId: String?
    let reservationId: String?
    let jobId: String
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
        let path = makeStoragePath(for: record.request)
        let ref = storage.reference(withPath: path)

        let metadata = StorageMetadata()
        metadata.contentType = "application/zip"
        var custom: [String: String] = [:]
        custom["jobId"] = record.request.metadata.jobId
        custom["creatorId"] = record.request.metadata.creatorId
        custom["capturedAt"] = ISO8601DateFormatter().string(from: record.request.metadata.capturedAt)
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

            // Keep observers alive until continuation resumes
            _ = (progressHandle, successHandle, failureHandle)
        }
        #else
        // Fallback: simulate progress if FirebaseStorage is unavailable (e.g., in previews)
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

    #if canImport(FirebaseStorage)
    private func makeStoragePath(for request: CaptureUploadRequest) -> String {
        let placeId = (request.metadata.targetId?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "unknown"
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let ts = formatter.string(from: request.metadata.capturedAt).replacingOccurrences(of: ":", with: "-")
        let basename = request.packageURL.lastPathComponent
        return "targets/\(placeId)/\(ts)/\(basename)"
    }
    #endif
}
