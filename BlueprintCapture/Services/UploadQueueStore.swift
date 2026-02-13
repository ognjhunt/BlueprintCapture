import Foundation

struct PendingUploadRecord: Codable, Equatable, Identifiable {
    let id: UUID
    let packagePath: String
    let metadata: CaptureUploadMetadata
    let targetName: String?
    let estimatedPayoutLowerUsd: Int?
    let estimatedPayoutUpperUsd: Int?

    init(id: UUID,
         packagePath: String,
         metadata: CaptureUploadMetadata,
         targetName: String?,
         estimatedPayoutRange: ClosedRange<Int>?) {
        self.id = id
        self.packagePath = packagePath
        self.metadata = metadata
        self.targetName = targetName
        self.estimatedPayoutLowerUsd = estimatedPayoutRange?.lowerBound
        self.estimatedPayoutUpperUsd = estimatedPayoutRange?.upperBound
    }

    var estimatedPayoutRange: ClosedRange<Int>? {
        guard let lo = estimatedPayoutLowerUsd, let hi = estimatedPayoutUpperUsd else { return nil }
        return lo...hi
    }
}

final class UploadQueueStore {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.blueprint.uploadQueueStore")

    init(fileURL: URL = UploadQueueStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    func load() -> [PendingUploadRecord] {
        queue.sync {
            guard let data = try? Data(contentsOf: fileURL) else { return [] }
            do {
                return try JSONDecoder().decode([PendingUploadRecord].self, from: data)
            } catch {
                return []
            }
        }
    }

    func save(_ records: [PendingUploadRecord]) {
        queue.async {
            do {
                let dir = self.fileURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let data = try JSONEncoder().encode(records)
                try data.write(to: self.fileURL, options: [.atomic])
            } catch {
                // Best-effort persistence only.
            }
        }
    }

    private static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("BlueprintCapture", isDirectory: true)
            .appendingPathComponent("upload-queue.json")
    }
}

