import Foundation
import Testing
@testable import BlueprintCapture

struct StripeConnectServiceTests {

    @Test
    func stateChangingStripeRequestsRequireFirebaseToken() {
        #expect(StripeConnectService.requiresFirebaseToken(httpMethod: "POST"))
        #expect(StripeConnectService.requiresFirebaseToken(httpMethod: "PUT"))
        #expect(StripeConnectService.requiresFirebaseToken(httpMethod: "PATCH"))
        #expect(StripeConnectService.requiresFirebaseToken(httpMethod: "DELETE"))
        #expect(!StripeConnectService.requiresFirebaseToken(httpMethod: "GET"))
        #expect(!StripeConnectService.requiresFirebaseToken(httpMethod: nil))
    }

    @Test
    func authenticationRequiredErrorPromptsRelogin() {
        #expect(
            StripeConnectService.StripeConnectError.authenticationRequired.errorDescription ==
            "Sign in again before changing payout settings."
        )
    }
}
