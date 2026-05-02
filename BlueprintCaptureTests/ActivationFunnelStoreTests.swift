import Foundation
import Testing
@testable import BlueprintCapture

struct ActivationFunnelStoreTests {
    @Test
    func recordsNamedStepsAndSummarizesDropOff() {
        let suiteName = "activation-funnel-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ActivationFunnelStore(defaults: defaults)

        store.record(.onboardingStarted, metadata: ["reason": "test", "email": "person@example.com"])
        store.record(.accountCreatedOrSignedIn, metadata: ["auth_mode": "sign_up", "auth_provider": "email"])

        let snapshot = store.snapshot()
        #expect(snapshot.totalEvents == 2)
        #expect(snapshot.summaries.first(where: { $0.step == .onboardingStarted })?.count == 1)
        #expect(snapshot.summaries.first(where: { $0.step == .accountCreatedOrSignedIn })?.count == 1)
        #expect(snapshot.dropOffStep == .permissionsStepViewed)
        #expect(store.events().first?.metadata["email"] == nil)
    }

    @Test
    func uploadCompletionClassifiesFirstCaptureActivationOnce() {
        let suiteName = "activation-funnel-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ActivationFunnelStore(defaults: defaults)

        store.record(.uploadCompleted, captureId: "cap_001", metadata: ["capture_source": "iphone_video"])
        store.record(.uploadCompleted, captureId: "cap_001", metadata: ["capture_source": "iphone_video"])

        let snapshot = store.snapshot()
        #expect(snapshot.activationCompleted)
        #expect(snapshot.summaries.first(where: { $0.step == .uploadCompleted })?.count == 2)
        #expect(snapshot.summaries.first(where: { $0.step == .firstCaptureActivationCompleted })?.count == 1)
        #expect(store.events().last?.captureId == "cap_001")
    }

    @Test
    func repeatCaptureEventsStartOnlyAfterFirstActivation() {
        let suiteName = "activation-funnel-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ActivationFunnelStore(defaults: defaults)

        store.record(.captureStarted, captureId: "cap_001", metadata: ["capture_source": "iphone_video"])
        store.record(.captureCompletedLocally, captureId: "cap_001", metadata: ["capture_source": "iphone_video"])
        store.record(.uploadCompleted, captureId: "cap_001", metadata: ["capture_source": "iphone_video"])

        var snapshot = store.snapshot()
        #expect(snapshot.activationCompleted)
        #expect(snapshot.repeatCaptureStartedCount == 0)
        #expect(snapshot.repeatCaptureCompletedCount == 0)
        #expect(snapshot.repeatCaptureUploadedCount == 0)
        #expect(snapshot.repeatCaptureDropOffStep == .returnToStartCapture)

        store.record(.captureStarted, captureId: "cap_002", metadata: ["capture_source": "iphone_video"])
        snapshot = store.snapshot()
        #expect(snapshot.repeatCaptureStartedCount == 1)
        #expect(snapshot.repeatCaptureDropOffStep == .completeRepeatCapture)

        store.record(.captureCompletedLocally, captureId: "cap_002", metadata: ["capture_source": "iphone_video"])
        snapshot = store.snapshot()
        #expect(snapshot.repeatCaptureCompletedCount == 1)
        #expect(snapshot.repeatCaptureDropOffStep == .uploadRepeatCapture)

        store.record(.uploadCompleted, captureId: "cap_002", metadata: ["capture_source": "iphone_video"])
        snapshot = store.snapshot()
        #expect(snapshot.repeatCaptureUploadedCount == 1)
        #expect(snapshot.repeatCaptureDropOffStep == .completeThirdUpload)
        #expect(store.events().last(where: { $0.step == .repeatCaptureUploaded })?.metadata["capture_number"] == "2")
    }

    @Test
    func repeatDropOffClearsAfterThirdUploadedCapture() {
        let suiteName = "activation-funnel-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ActivationFunnelStore(defaults: defaults)

        for number in 1...3 {
            let captureId = "cap_00\(number)"
            store.record(.captureStarted, captureId: captureId, metadata: ["capture_source": "iphone_video"])
            store.record(.captureCompletedLocally, captureId: captureId, metadata: ["capture_source": "iphone_video"])
            store.record(.uploadCompleted, captureId: captureId, metadata: ["capture_source": "iphone_video"])
        }

        let snapshot = store.snapshot()
        #expect(snapshot.uploadedCaptureCount == 3)
        #expect(snapshot.repeatCaptureStartedCount == 2)
        #expect(snapshot.repeatCaptureCompletedCount == 2)
        #expect(snapshot.repeatCaptureUploadedCount == 2)
        #expect(snapshot.repeatCaptureDropOffStep == nil)
        #expect(snapshot.repeatCaptureProgressTitle == "Repeat capture habit active")
    }

    @Test
    func snapshotKeepsEveryRequiredFunnelStepInOrder() {
        let snapshot = ActivationFunnelStore.snapshot(from: [])

        #expect(snapshot.summaries.map(\.step) == ActivationFunnelStep.allCases)
        #expect(snapshot.dropOffStep == .onboardingStarted)
        #expect(!snapshot.activationCompleted)
        #expect(snapshot.repeatCaptureDropOffStep == nil)
    }
}
