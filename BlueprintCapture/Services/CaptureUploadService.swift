import Foundation
import Combine
#if canImport(FirebaseStorage)
import FirebaseStorage
#endif
#if canImport(FirebaseCore)
import FirebaseCore
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
        print("🚀 [UploadService] performUpload start id=\(id) url=\(packageURL.path)")

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
        let storage = Storage.storage()
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
        for case let url as URL in enumerator {
            var isRegular: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isRegular), !isRegular.boolValue {
                files.append(url)
                if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                    totalBytes += Int64(size)
                }
            }
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
            if let t = request.metadata.targetId { custom["targetId"] = t }
            if let r = request.metadata.reservationId { custom["reservationId"] = r }
            md.customMetadata = custom

            // If manifest.json, patch scene_id and video_uri before uploading
            let uploadSourceURL: URL
            if relPath == "manifest.json" {
                let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("manifest-\(UUID().uuidString).json")
                do {
                    let data = try Data(contentsOf: file)
                    var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
                    let sceneId = (request.metadata.targetId?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? request.metadata.jobId
                    let bucket = (FirebaseApp.app()?.options.storageBucket).map { "gs://\($0)" } ?? ""
                    json["scene_id"] = sceneId
                    if !bucket.isEmpty {
                        json["video_uri"] = bucket + "/" + remoteBasePath + "walkthrough.mov"
                    }
                    let patched = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .withoutEscapingSlashes])
                    try patched.write(to: tempURL, options: .atomic)
                    uploadSourceURL = tempURL
                } catch {
                    uploadSourceURL = file
                }
            } else {
                uploadSourceURL = file
            }

            let uploadTask = ref.putFile(from: uploadSourceURL, metadata: md)

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
        }
        return true
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
        let placeId = (request.metadata.targetId?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "unknown"
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let ts = formatter.string(from: request.metadata.capturedAt).replacingOccurrences(of: ":", with: "-")
        let basename = request.packageURL.lastPathComponent
        return "targets/\(placeId)/\(ts)/\(basename)"
    }

    private func makeBaseDirectoryPath(for request: CaptureUploadRequest) -> String {
        let placeId = (request.metadata.targetId?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? request.metadata.jobId
        // Required layout: targets/<scene_id>/raw/
        return "targets/\(placeId)/raw/"
    }
    #endif
}
