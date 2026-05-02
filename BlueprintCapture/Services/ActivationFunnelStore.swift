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
    case repeatCaptureStarted = "repeat_capture_started"
    case repeatCaptureCompleted = "repeat_capture_completed"
    case repeatCaptureUploaded = "repeat_capture_uploaded"

    var id: String { rawValue }
}

enum RepeatCaptureDropOffStep: String, Codable, Equatable, Identifiable {
    case returnToStartCapture = "return_to_start_capture"
    case completeRepeatCapture = "complete_repeat_capture"
    case uploadRepeatCapture = "upload_repeat_capture"
    case completeThirdUpload = "complete_third_upload"

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
    let repeatCaptureStartedCount: Int
    let repeatCaptureCompletedCount: Int
    let repeatCaptureUploadedCount: Int
    let repeatCaptureDropOffStep: RepeatCaptureDropOffStep?

    var dropOffStep: ActivationFunnelStep? { firstIncompleteStep }

    var uploadedCaptureCount: Int {
        summaries.first(where: { $0.step == .uploadCompleted })?.count ?? 0
    }

    var repeatCaptureProgressTitle: String {
        guard activationCompleted else { return "First capture not complete" }
        switch uploadedCaptureCount {
        case 0:
            return "First capture not complete"
        case 1:
            return "Second capture ready"
        case 2:
            return "Third capture ready"
        default:
            return "Repeat capture habit active"
        }
    }

    var repeatCaptureProgressSubtitle: String {
        guard activationCompleted else {
            return "Upload the first valid bundle before the repeat loop starts."
        }
        switch repeatCaptureDropOffStep {
        case .returnToStartCapture:
            return "Activated capturer has not started another capture yet."
        case .completeRepeatCapture:
            return "Repeat capture started but no local completion is recorded."
        case .uploadRepeatCapture:
            return "Repeat capture completed locally but has not uploaded."
        case .completeThirdUpload:
            return "Second upload landed. One more valid upload completes the third-capture goal."
        case nil:
            return "Second and third valid uploads are complete."
        }
    }
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
        var loggedRepeatStep: ActivationFunnelStep?
        var loggedRepeatMetadata: [String: String] = [:]
        queue.sync {
            var events = loadEventsLocked()
            let repeatStep = Self.repeatStep(for: step, captureId: captureId, existingEvents: events)
            let repeatMetadata = Self.repeatMetadata(for: step, captureId: captureId, existingEvents: events, metadata: safeMetadata)
            loggedRepeatStep = repeatStep
            loggedRepeatMetadata = repeatMetadata
            events.append(
                ActivationFunnelEventRecord(
                    id: UUID(),
                    step: step,
                    occurredAt: Date(),
                    captureId: captureId?.nilIfEmpty,
                    metadata: safeMetadata
                )
            )
            if let repeatStep {
                events.append(
                    ActivationFunnelEventRecord(
                        id: UUID(),
                        step: repeatStep,
                        occurredAt: Date(),
                        captureId: captureId?.nilIfEmpty,
                        metadata: repeatMetadata
                    )
                )
            }

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
        if let loggedRepeatStep {
            SessionEventManager.shared.logOperationalEvent(
                operation: loggedRepeatStep.rawValue,
                status: "recorded",
                metadata: loggedRepeatMetadata.merging(["capture_id": captureId ?? ""], uniquingKeysWith: { current, _ in current })
            )
        }
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
        let repeatStarted = summaries.first(where: { $0.step == .repeatCaptureStarted })?.count ?? 0
        let repeatCompleted = summaries.first(where: { $0.step == .repeatCaptureCompleted })?.count ?? 0
        let repeatUploaded = summaries.first(where: { $0.step == .repeatCaptureUploaded })?.count ?? 0
        let uploadCompleted = summaries.first(where: { $0.step == .uploadCompleted })?.count ?? 0
        let activationCompleted = summaries.first(where: { $0.step == .firstCaptureActivationCompleted })?.count ?? 0 > 0
        return ActivationFunnelSnapshot(
            summaries: summaries,
            totalEvents: events.count,
            firstIncompleteStep: firstIncomplete,
            activationCompleted: activationCompleted,
            repeatCaptureStartedCount: repeatStarted,
            repeatCaptureCompletedCount: repeatCompleted,
            repeatCaptureUploadedCount: repeatUploaded,
            repeatCaptureDropOffStep: Self.repeatDropOffStep(
                activationCompleted: activationCompleted,
                repeatStarted: repeatStarted,
                repeatCompleted: repeatCompleted,
                repeatUploaded: repeatUploaded,
                uploadCompleted: uploadCompleted
            )
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

    private static func repeatStep(
        for step: ActivationFunnelStep,
        captureId: String?,
        existingEvents: [ActivationFunnelEventRecord]
    ) -> ActivationFunnelStep? {
        guard existingEvents.contains(where: { $0.step == .firstCaptureActivationCompleted }) else { return nil }
        switch step {
        case .captureStarted:
            return .repeatCaptureStarted
        case .captureCompletedLocally:
            return .repeatCaptureCompleted
        case .uploadCompleted:
            if let captureId = captureId?.nilIfEmpty,
               existingEvents.contains(where: { $0.step == .uploadCompleted && $0.captureId == captureId }) {
                return nil
            }
            return .repeatCaptureUploaded
        default:
            return nil
        }
    }

    private static func repeatMetadata(
        for step: ActivationFunnelStep,
        captureId: String?,
        existingEvents: [ActivationFunnelEventRecord],
        metadata: [String: String]
    ) -> [String: String] {
        guard step == .uploadCompleted else { return metadata }
        var uploadedCaptureIds = Set(existingEvents.filter { $0.step == .uploadCompleted }.compactMap(\.captureId))
        if let captureId = captureId?.nilIfEmpty {
            uploadedCaptureIds.insert(captureId)
        }
        let nextUploadNumber = max(uploadedCaptureIds.count, existingEvents.filter { $0.step == .uploadCompleted }.count + 1)
        return metadata.merging(["capture_number": "\(nextUploadNumber)"], uniquingKeysWith: { current, _ in current })
    }

    private static func repeatDropOffStep(
        activationCompleted: Bool,
        repeatStarted: Int,
        repeatCompleted: Int,
        repeatUploaded: Int,
        uploadCompleted: Int
    ) -> RepeatCaptureDropOffStep? {
        guard activationCompleted else { return nil }
        if uploadCompleted >= 3 { return nil }
        if repeatStarted == 0 { return .returnToStartCapture }
        if repeatCompleted < repeatStarted { return .completeRepeatCapture }
        if repeatUploaded < repeatCompleted { return .uploadRepeatCapture }
        return .completeThirdUpload
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
            "capture_number",
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
