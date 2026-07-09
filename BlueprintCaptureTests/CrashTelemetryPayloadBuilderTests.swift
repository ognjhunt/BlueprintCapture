import Foundation
import Testing
@testable import BlueprintCapture

/// Unit tests for the pure crash/error telemetry payload builders (finding R051).
/// These exercise only the side-effect-free `CrashTelemetryPayloadBuilder` seam — no
/// Firebase, UIKit, crash handlers, or simulator — so CI runs them in the hermetic lane.
struct CrashTelemetryPayloadBuilderTests {

    private let sampleDate = Date(timeIntervalSince1970: 1_700_000_000)

    @Test
    func crashBreadcrumbIncludesEnvelopeFields() {
        let record = CrashTelemetryPayloadBuilder.crashBreadcrumb(
            kind: "signal",
            name: "SIGABRT",
            reason: "signal 6",
            callStack: ["0 frame", "1 frame"],
            appVersion: "1.2.3",
            buildNumber: "42",
            deviceModel: "iPhone",
            osVersion: "18.0",
            occurredAt: sampleDate
        )
        #expect(record["kind"] as? String == "signal")
        #expect(record["name"] as? String == "SIGABRT")
        #expect(record["reason"] as? String == "signal 6")
        #expect(record["appVersion"] as? String == "1.2.3")
        #expect(record["buildNumber"] as? String == "42")
        #expect(record["deviceModel"] as? String == "iPhone")
        #expect(record["osVersion"] as? String == "18.0")
        #expect(record["occurredAtEpoch"] as? Double == sampleDate.timeIntervalSince1970)
        #expect((record["callStack"] as? [String])?.count == 2)
    }

    @Test
    func crashBreadcrumbBoundsCallStackAndDropsEmptyReason() {
        let frames = (0..<100).map { "frame \($0)" }
        let record = CrashTelemetryPayloadBuilder.crashBreadcrumb(
            kind: "uncaughtException",
            name: "NSGenericException",
            reason: "",
            callStack: frames,
            appVersion: "1.0",
            buildNumber: "1",
            deviceModel: "iPhone",
            osVersion: "18.0",
            occurredAt: sampleDate
        )
        // Empty reason is omitted rather than stored as "".
        #expect(record["reason"] == nil)
        #expect((record["callStack"] as? [String])?.count == CrashTelemetryPayloadBuilder.maxCallStackFrames)
    }

    @Test
    func sanitizedMetadataKeepsScalarsAndDropsRawContent() {
        let metadata: [String: Any] = [
            "errorDomain": "FIRStorageErrorDomain",
            "retryable": true,
            "attempt": 3,
            "latency": 1.5,
            "rawFrame": Data(repeating: 0xAB, count: 4096),   // raw capture bytes -> dropped
            "nested": ["secret": "value"]                     // nested payload -> dropped
        ]
        let cleaned = CrashTelemetryPayloadBuilder.sanitizedMetadata(metadata)
        #expect(cleaned["errorDomain"] as? String == "FIRStorageErrorDomain")
        #expect(cleaned["retryable"] as? Bool == true)
        #expect(cleaned["attempt"] as? Int == 3)
        #expect(cleaned["latency"] as? Double == 1.5)
        #expect(cleaned["rawFrame"] == nil)
        #expect(cleaned["nested"] == nil)
    }

    @Test
    func sanitizedMetadataTruncatesLongStringsAndCapsKeys() {
        let longValue = String(repeating: "x", count: 5000)
        var metadata: [String: Any] = ["blob": longValue]
        for index in 0..<50 {
            metadata["k\(index)"] = index
        }
        let cleaned = CrashTelemetryPayloadBuilder.sanitizedMetadata(metadata)
        #expect(cleaned.count <= CrashTelemetryPayloadBuilder.maxMetadataKeys)
        // "blob" sorts before the "k*" keys, so it survives and must be truncated.
        let blob = cleaned["blob"] as? String
        #expect(blob != nil)
        #expect((blob?.count ?? 0) <= CrashTelemetryPayloadBuilder.maxMetadataValueLength)
    }

    @Test
    func sanitizedMetadataHandlesNilInput() {
        let cleaned = CrashTelemetryPayloadBuilder.sanitizedMetadata(nil)
        #expect(cleaned.isEmpty)
    }

    @Test
    func errorBreadcrumbExcludesRawCaptureContent() {
        let metadata: [String: Any] = [
            "reason": "timeout",
            "rawCaptureBytes": Data(repeating: 0x01, count: 2048)
        ]
        let record = CrashTelemetryPayloadBuilder.errorBreadcrumb(
            errorCode: "upload_failed",
            metadata: metadata,
            appVersion: "1.0",
            buildNumber: "1",
            deviceModel: "iPhone",
            osVersion: "18.0",
            occurredAt: sampleDate
        )
        #expect(record["errorCode"] as? String == "upload_failed")
        #expect(record["occurredAtEpoch"] as? Double == sampleDate.timeIntervalSince1970)
        let cleaned = record["metadata"] as? [String: Any]
        #expect(cleaned?["reason"] as? String == "timeout")
        #expect(cleaned?["rawCaptureBytes"] == nil)
    }
}
