import Foundation

enum ActivationFunnelStep: String, CaseIterable, Codable, Identifiable {
    case onboardingStarted = "onboarding_started"
    case accountCreatedOrSignedIn = "account_created_or_signed_in"
    case permissionsStepViewed = "permissions_step_viewed"
    case permissionsGrantedOrBlocked = "permissions_granted_or_blocked"
    case captureGoalSelected = "capture_goal_selected"
    case captureStarted = "capture_started"
    case captureCompletedLocally = "capture_completed_locally"
    case bundleFinalized = "bundle_finalized"
    case uploadStarted = "upload_started"
    case uploadCompleted = "upload_completed"
    case uploadFailed = "upload_failed"
    case firstCaptureActivationCompleted = "first_capture_activation_completed"

    var id: String { rawValue }
}

struct ActivationFunnelEventRecord: Codable, Equatable, Identifiable {
    let id: UUID
    let step: ActivationFunnelStep
    let occurredAt: Date
    let captureId: String?
    let metadata: [String: String]
}

struct ActivationFunnelStepSummary: Equatable, Identifiable {
    let step: ActivationFunnelStep
    let count: Int
    let lastOccurredAt: Date?

    var id: String { step.rawValue }
}

struct ActivationFunnelSnapshot: Equatable {
    let summaries: [ActivationFunnelStepSummary]
    let totalEvents: Int
    let firstIncompleteStep: ActivationFunnelStep?
    let activationCompleted: Bool

    var dropOffStep: ActivationFunnelStep? { firstIncompleteStep }
}

protocol ActivationFunnelRecording {
    func record(_ step: ActivationFunnelStep, captureId: String?, metadata: [String: String])
}

final class ActivationFunnelStore: ActivationFunnelRecording {
    static let shared = ActivationFunnelStore()
    static let changedNotification = Notification.Name("ActivationFunnelStore.changed")

    private let defaults: UserDefaults
    private let storageKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let queue = DispatchQueue(label: "com.blueprint.activationFunnelStore")

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "com.blueprint.activationFunnel.events"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func record(_ step: ActivationFunnelStep, captureId: String? = nil, metadata: [String: String] = [:]) {
        let safeMetadata = Self.privacySafe(metadata)
        queue.sync {
            var events = loadEventsLocked()
            events.append(
                ActivationFunnelEventRecord(
                    id: UUID(),
                    step: step,
                    occurredAt: Date(),
                    captureId: captureId?.nilIfEmpty,
                    metadata: safeMetadata
                )
            )

            if shouldRecordActivationCompletion(afterAppending: events) {
                let completedCaptureId = captureId ?? latestCaptureId(in: events)
                events.append(
                    ActivationFunnelEventRecord(
                        id: UUID(),
                        step: .firstCaptureActivationCompleted,
                        occurredAt: Date(),
                        captureId: completedCaptureId?.nilIfEmpty,
                        metadata: ["basis": "upload_completed"]
                    )
                )
            }

            saveEventsLocked(events)
        }
        NotificationCenter.default.post(name: Self.changedNotification, object: nil)
        SessionEventManager.shared.logOperationalEvent(
            operation: step.rawValue,
            status: "recorded",
            metadata: safeMetadata.merging(["capture_id": captureId ?? ""], uniquingKeysWith: { current, _ in current })
        )
    }

    func snapshot() -> ActivationFunnelSnapshot {
        queue.sync {
            let events = loadEventsLocked()
            return Self.snapshot(from: events)
        }
    }

    func events() -> [ActivationFunnelEventRecord] {
        queue.sync { loadEventsLocked() }
    }

    func reset() {
        queue.sync {
            defaults.removeObject(forKey: storageKey)
        }
        NotificationCenter.default.post(name: Self.changedNotification, object: nil)
    }

    static func snapshot(from events: [ActivationFunnelEventRecord]) -> ActivationFunnelSnapshot {
        let summaries = ActivationFunnelStep.allCases.map { step in
            let matches = events.filter { $0.step == step }
            return ActivationFunnelStepSummary(
                step: step,
                count: matches.count,
                lastOccurredAt: matches.map(\.occurredAt).max()
            )
        }
        let firstIncomplete = summaries.first(where: { $0.count == 0 })?.step
        return ActivationFunnelSnapshot(
            summaries: summaries,
            totalEvents: events.count,
            firstIncompleteStep: firstIncomplete,
            activationCompleted: summaries.first(where: { $0.step == .firstCaptureActivationCompleted })?.count ?? 0 > 0
        )
    }

    private func shouldRecordActivationCompletion(afterAppending events: [ActivationFunnelEventRecord]) -> Bool {
        guard events.contains(where: { $0.step == .uploadCompleted }) else { return false }
        guard !events.contains(where: { $0.step == .firstCaptureActivationCompleted }) else { return false }
        return true
    }

    private func latestCaptureId(in events: [ActivationFunnelEventRecord]) -> String? {
        events.reversed().first(where: { $0.captureId?.isEmpty == false })?.captureId
    }

    private func loadEventsLocked() -> [ActivationFunnelEventRecord] {
        guard let data = defaults.data(forKey: storageKey) else { return [] }
        return (try? decoder.decode([ActivationFunnelEventRecord].self, from: data)) ?? []
    }

    private func saveEventsLocked(_ events: [ActivationFunnelEventRecord]) {
        guard let data = try? encoder.encode(events) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private static func privacySafe(_ metadata: [String: String]) -> [String: String] {
        let allowedKeys: Set<String> = [
            "auth_mode",
            "auth_provider",
            "camera",
            "capture_source",
            "goal",
            "location",
            "microphone",
            "motion",
            "notifications",
            "reason",
            "upload_error"
        ]
        return metadata.reduce(into: [:]) { result, pair in
            guard allowedKeys.contains(pair.key) else { return }
            result[pair.key] = String(pair.value.prefix(80))
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
