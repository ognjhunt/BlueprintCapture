import Foundation
import Testing
@testable import BlueprintCapture

struct APIServiceTests {

    @Test
    func apiErrorLocalizedDescriptionsAreActionable() {
        #expect(APIService.APIError.missingBaseURL.errorDescription == "BLUEPRINT_BACKEND_BASE_URL is not configured for this build.")
        #expect(APIService.APIError.invalidResponse(statusCode: 503).errorDescription == "The backend returned HTTP 503.")
        #expect(APIService.APIError.invalidResponse(statusCode: -1).errorDescription == "The backend returned an invalid non-HTTP response.")
    }
}
