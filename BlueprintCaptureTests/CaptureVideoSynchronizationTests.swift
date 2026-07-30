import Foundation
import Testing
@testable import BlueprintCapture

struct CaptureVideoSynchronizationTests {

    @Test
    func retainedFramesBindToDecodedPTSAndDroppedAttemptsRemainExplicit() throws {
        let frameRows: [[String: Any]] = [
            ["frame_id": "000001", "timestamp": 100.0, "t_capture_sec": 0.0],
            ["frame_id": "000002", "timestamp": 100.033, "t_capture_sec": 0.033],
            ["frame_id": "000003", "timestamp": 100.066, "t_capture_sec": 0.066],
        ]
        let attempts: [[String: Any]] = [
            [
                "write_attempt_index": 0,
                "source_timestamp_sec": 100.0,
                "retention_status": "retained",
                "encoded_frame_index": 0,
            ],
            [
                "write_attempt_index": 1,
                "source_timestamp_sec": 100.033,
                "retention_status": "dropped_backpressure",
                "drop_reason": "asset_writer_input_not_ready",
            ],
            [
                "write_attempt_index": 2,
                "source_timestamp_sec": 100.066,
                "retention_status": "retained",
                "encoded_frame_index": 1,
            ],
        ]

        let result = try CaptureVideoSynchronization.build(
            frameRows: frameRows,
            writeAttemptRows: attempts,
            decodedPresentationTimes: [5.0, 5.066]
        )

        #expect(result.syncRows.count == 2)
        #expect(result.syncRows[0]["frame_id"] as? String == "000001")
        #expect(result.syncRows[1]["frame_id"] as? String == "000003")
        #expect(result.syncRows[0]["t_video_sec"] as? Double == 0.0)
        #expect(abs((result.syncRows[1]["t_video_sec"] as? Double ?? 0.0) - 0.066) < 0.000_001)
        #expect(result.syncRows.allSatisfy {
            ($0["sync_status"] as? String) == "encoded_decoded_pts_match"
        })
        #expect(result.retentionRows.count == 3)
        #expect(result.retentionRows[1]["retention_status"] as? String == "dropped_backpressure")
        #expect(result.retentionRows[1]["frame_id"] as? String == "000002")
        #expect(result.retentionRows[1]["t_video_sec"] is NSNull)
    }

    @Test
    func decodedFrameCountMismatchFailsClosed() {
        let frames: [[String: Any]] = [
            ["frame_id": "000001", "timestamp": 100.0, "t_capture_sec": 0.0],
        ]
        let attempts: [[String: Any]] = [
            [
                "write_attempt_index": 0,
                "source_timestamp_sec": 100.0,
                "retention_status": "retained",
            ],
        ]

        do {
            _ = try CaptureVideoSynchronization.build(
                frameRows: frames,
                writeAttemptRows: attempts,
                decodedPresentationTimes: [5.0, 5.033]
            )
            Issue.record("Expected decoded frame count mismatch")
        } catch let error as CaptureVideoSynchronizationError {
            #expect(error == .decodedFrameCountMismatch(expected: 1, actual: 2))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func missingARFrameForRetainedWriteFailsClosed() {
        let attempts: [[String: Any]] = [
            [
                "write_attempt_index": 0,
                "source_timestamp_sec": 100.0,
                "retention_status": "retained",
            ],
        ]

        do {
            _ = try CaptureVideoSynchronization.build(
                frameRows: [],
                writeAttemptRows: attempts,
                decodedPresentationTimes: [5.0]
            )
            Issue.record("Expected missing retained AR frame")
        } catch let error as CaptureVideoSynchronizationError {
            #expect(error == .retainedAttemptMissingFrame(sourceTimestampNs: 100_000_000_000))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func droppedAttemptWithoutSourceARFrameFailsClosed() {
        let frames: [[String: Any]] = [
            ["frame_id": "000001", "timestamp": 100.0, "t_capture_sec": 0.0],
        ]
        let attempts: [[String: Any]] = [
            [
                "write_attempt_index": 0,
                "source_timestamp_sec": 100.0,
                "retention_status": "retained",
            ],
            [
                "write_attempt_index": 1,
                "source_timestamp_sec": 100.033,
                "retention_status": "dropped_backpressure",
                "drop_reason": "asset_writer_input_not_ready",
            ],
        ]

        do {
            _ = try CaptureVideoSynchronization.build(
                frameRows: frames,
                writeAttemptRows: attempts,
                decodedPresentationTimes: [5.0]
            )
            Issue.record("Expected dropped attempt source-frame mismatch")
        } catch let error as CaptureVideoSynchronizationError {
            #expect(error == .writeAttemptMissingFrame(sourceTimestampNs: 100_033_000_000))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
