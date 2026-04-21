import Testing
@testable import BlueprintCapture

struct GlassesCaptureManagerTests {

    @Test
    @MainActor
    func simulatorBuildsDisableRealWearables() {
        #if targetEnvironment(simulator)
        #expect(GlassesCaptureManager.supportsRealWearables == false)
        #endif
    }
}
