import Foundation
import Testing
@testable import BlueprintCapture

struct ResumableUploadPolicyTests {

    @Test
    func backoffIsZeroBeforeFirstRetry() {
        #expect(ResumableUploadPolicy.backoffDelay(forRetry: 0) == 0)
    }

    @Test
    func backoffGrowsExponentially() {
        #expect(ResumableUploadPolicy.backoffDelay(forRetry: 1) == 0.5)
        #expect(ResumableUploadPolicy.backoffDelay(forRetry: 2) == 1.0)
        #expect(ResumableUploadPolicy.backoffDelay(forRetry: 3) == 2.0)
        #expect(ResumableUploadPolicy.backoffDelay(forRetry: 4) == 4.0)
    }

    @Test
    func backoffIsCapped() {
        // 0.5 * 2^9 = 256, capped at the 30s default ceiling.
        #expect(ResumableUploadPolicy.backoffDelay(forRetry: 10) == 30.0)
    }

    @Test
    func transientHTTPStatusesAreRetryable() {
        #expect(ResumableUploadPolicy.isRetryable(httpStatus: 408))
        #expect(ResumableUploadPolicy.isRetryable(httpStatus: 429))
        #expect(ResumableUploadPolicy.isRetryable(httpStatus: 500))
        #expect(ResumableUploadPolicy.isRetryable(httpStatus: 502))
        #expect(ResumableUploadPolicy.isRetryable(httpStatus: 503))
        #expect(ResumableUploadPolicy.isRetryable(httpStatus: 504))
    }

    @Test
    func clientAndSuccessStatusesAreNotRetryable() {
        #expect(!ResumableUploadPolicy.isRetryable(httpStatus: 200))
        #expect(!ResumableUploadPolicy.isRetryable(httpStatus: 400))
        #expect(!ResumableUploadPolicy.isRetryable(httpStatus: 401))
        #expect(!ResumableUploadPolicy.isRetryable(httpStatus: 403))
        #expect(!ResumableUploadPolicy.isRetryable(httpStatus: 404))
    }

    @Test
    func remainingBytesReflectsCommittedOffset() {
        #expect(ResumableUploadPolicy.remainingBytes(committedOffset: 0, totalBytes: 1_000) == 1_000)
        #expect(ResumableUploadPolicy.remainingBytes(committedOffset: 250, totalBytes: 1_000) == 750)
        #expect(ResumableUploadPolicy.remainingBytes(committedOffset: 1_000, totalBytes: 1_000) == 0)
        // Guards against a server offset overshooting the local size.
        #expect(ResumableUploadPolicy.remainingBytes(committedOffset: 1_200, totalBytes: 1_000) == 0)
    }

    @Test
    func isCompleteWhenOffsetReachesTotal() {
        #expect(!ResumableUploadPolicy.isComplete(committedOffset: 999, totalBytes: 1_000))
        #expect(ResumableUploadPolicy.isComplete(committedOffset: 1_000, totalBytes: 1_000))
        #expect(ResumableUploadPolicy.isComplete(committedOffset: 1_001, totalBytes: 1_000))
    }

    @Test
    func clampOffsetStaysWithinBounds() {
        #expect(ResumableUploadPolicy.clampOffset(-5, totalBytes: 1_000) == 0)
        #expect(ResumableUploadPolicy.clampOffset(500, totalBytes: 1_000) == 500)
        #expect(ResumableUploadPolicy.clampOffset(5_000, totalBytes: 1_000) == 1_000)
    }
}
