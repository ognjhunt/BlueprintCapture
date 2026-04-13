import Testing
@testable import BlueprintCapture

struct GlassesCaptureManagerTests {

    @Test
    func simulatorBuildsDisableRealWearables() {
        #if targetEnvironment(simulator)
        #expect(GlassesCaptureManager.supportsRealWearables == false)
        #endif
    }
}
