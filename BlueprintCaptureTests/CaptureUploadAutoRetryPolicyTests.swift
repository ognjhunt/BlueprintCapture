import Foundation
import Testing
@testable import BlueprintCapture

/// Policy tests for the bounded in-session upload auto-retry.
///
/// Only transient transport/registration failures may auto-retry; every
/// failure class that needs user action (auth, validation, disk, limits)
/// must surface immediately instead of burning retries on a deterministic
/// failure. The retry never touches the locally preserved bundle.
struct CaptureUploadAutoRetryPolicyTests {

    @Test
    func transientFailuresAreRetryableWithinBudget() {
        #expect(CaptureUploadService.shouldAutoRetry(error: .uploadFailed, retriesRemaining: 2))
        #expect(CaptureUploadService.shouldAutoRetry(error: .uploadFailed, retriesRemaining: 1))
        #expect(CaptureUploadService.shouldAutoRetry(error: .submissionRegistrationFailed, retriesRemaining: 1))
    }

    @Test
    func exhaustedBudgetStopsRetrying() {
        #expect(!CaptureUploadService.shouldAutoRetry(error: .uploadFailed, retriesRemaining: 0))
        #expect(!CaptureUploadService.shouldAutoRetry(error: .submissionRegistrationFailed, retriesRemaining: 0))
    }

    @Test
    func deterministicFailuresNeverAutoRetry() {
        let nonRetryable: [CaptureUploadService.UploadError] = [
            .fileMissing,
            .cancelled,
            .authenticationRequired,
            .missingStructuredIntake,
            .rawContractValidationFailed,
            .insufficientDiskSpace,
            .uploadLimitExceeded(reasons: ["duration"]),
            .captureLifecycleRegistrationFailed,
            .invalidBundle(reasons: ["missing manifest"])
        ]
        for error in nonRetryable {
            #expect(
                !CaptureUploadService.shouldAutoRetry(error: error, retriesRemaining: 2),
                "\(error) must not auto-retry"
            )
        }
    }

    @Test
    func backoffGrowsAndStaysBounded() {
        let first = CaptureUploadService.autoRetryDelaySeconds(forRetryNumber: 1)
        let second = CaptureUploadService.autoRetryDelaySeconds(forRetryNumber: 2)
        #expect(first > 0)
        #expect(second > first)
        for retry in 1...10 {
            #expect(CaptureUploadService.autoRetryDelaySeconds(forRetryNumber: retry) <= 60.0)
        }
    }
}
