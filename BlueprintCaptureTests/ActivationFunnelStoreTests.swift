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
    func snapshotKeepsEveryRequiredFunnelStepInOrder() {
        let snapshot = ActivationFunnelStore.snapshot(from: [])

        #expect(snapshot.summaries.map(\.step) == ActivationFunnelStep.allCases)
        #expect(snapshot.dropOffStep == .onboardingStarted)
        #expect(!snapshot.activationCompleted)
    }
}
