import Foundation

enum AbandonedCaptureReason: String, Codable, Equatable, Identifiable {
    case appBackgrounded = "app_backgrounded"
    case viewDismissed = "view_dismissed"
    case uploadLater = "upload_later"
    case recordingError = "recording_error"

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .appBackgrounded:
            return "App left before upload"
        case .viewDismissed:
            return "Capture flow closed"
        case .uploadLater:
            return "Saved for later upload"
        case .recordingError:
            return "Recording interrupted"
        }
    }
}

struct AbandonedCaptureRecoveryRecord: Codable, Equatable, Identifiable {
    enum State: String, Codable, Equatable {
        case recordingInterrupted = "recording_interrupted"
        case localBundleReady = "local_bundle_ready"
    }

    let id: String
    let state: State
    let reason: AbandonedCaptureReason
    let recordedAt: Date
    let startedAt: Date?
    let packageURL: URL?
    let videoURL: URL?
    let workingDirectoryURL: URL?
    let request: CaptureUploadRequest?
    let targetName: String?
    let address: String?
    let captureSource: String

    var hasRecoverableBundle: Bool {
        request != nil && packageURL != nil
    }

    var title: String {
        targetName ?? address ?? reason.displayTitle
    }

    var subtitle: String {
        switch state {
        case .localBundleReady:
            return "A truthful local bundle is still on this device. Upload it or dismiss the saved recovery."
        case .recordingInterrupted:
            return "Recording stopped before a valid bundle was completed. Local traces were preserved for review."
        }
    }
}

final class AbandonedCaptureRecoveryStore {
    static let shared = AbandonedCaptureRecoveryStore()
    static let changedNotification = Notification.Name("AbandonedCaptureRecoveryStore.changed")

    private let defaults: UserDefaults
    private let storageKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let queue = DispatchQueue(label: "com.blueprint.abandoned-capture-recovery")

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "com.blueprint.abandonedCaptureRecovery.records"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func save(_ record: AbandonedCaptureRecoveryRecord) {
        queue.sync {
            var records = loadLocked()
            records.removeAll { $0.id == record.id }
            records.append(record)
            records.sort { $0.recordedAt > $1.recordedAt }
            if let data = try? encoder.encode(records) {
                defaults.set(data, forKey: storageKey)
            }
        }
        SessionEventManager.shared.logOperationalEvent(
            operation: "capture_abandoned",
            status: record.state.rawValue,
            metadata: [
                "capture_id": record.id,
                "reason": record.reason.rawValue,
                "capture_source": record.captureSource,
                "has_recoverable_bundle": "\(record.hasRecoverableBundle)"
            ]
        )
        NotificationCenter.default.post(name: Self.changedNotification, object: nil)
    }

    func latest() -> AbandonedCaptureRecoveryRecord? {
        queue.sync { loadLocked().first }
    }

    func all() -> [AbandonedCaptureRecoveryRecord] {
        queue.sync { loadLocked() }
    }

    func remove(id: String) {
        queue.sync {
            let records = loadLocked().filter { $0.id != id }
            if let data = try? encoder.encode(records) {
                defaults.set(data, forKey: storageKey)
            }
        }
        NotificationCenter.default.post(name: Self.changedNotification, object: nil)
    }

    func clear() {
        queue.sync {
            defaults.removeObject(forKey: storageKey)
        }
        NotificationCenter.default.post(name: Self.changedNotification, object: nil)
    }

    private func loadLocked() -> [AbandonedCaptureRecoveryRecord] {
        guard let data = defaults.data(forKey: storageKey) else { return [] }
        return (try? decoder.decode([AbandonedCaptureRecoveryRecord].self, from: data)) ?? []
    }
}
