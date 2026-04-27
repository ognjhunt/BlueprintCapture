import CoreLocation
import Testing
@testable import BlueprintCapture

struct NearbyCandidateReviewSubmissionServiceTests {

    @Test
    func cooldownStorageKeyIncludesUserIdentity() {
        let location = CLLocation(latitude: 37.7749, longitude: -122.4194)

        let keyA = NearbyCandidateReviewSubmissionService.cooldownStorageKey(
            userId: "user-a",
            sourceContext: "app_open_scan",
            userLocation: location
        )
        let keyB = NearbyCandidateReviewSubmissionService.cooldownStorageKey(
            userId: "user-b",
            sourceContext: "app_open_scan",
            userLocation: location
        )

        #expect(keyA != keyB)
        #expect(keyA.contains("user-a"))
        #expect(keyB.contains("user-b"))
        #expect(keyA.contains("app_open_scan"))
    }
}
