import Foundation
import Testing
@testable import BlueprintCapture

struct CaptureCrashTelemetryServiceTests {

    @Test
    func metadataSanitizerKeepsOperationalFieldsAndRedactsSensitiveValues() {
        let metadata = CaptureCrashTelemetryService.sanitizedMetadata([
            "capture_id": "cap-123",
            "message": "Upload failed",
            "upload_path": "/Users/example/private/walkthrough.mov",
            "authorization_token": "secret-token",
            "email": "capturer@example.com",
            "lat": 41.8781
        ])

        #expect(metadata["capture_id"] == "cap-123")
        #expect(metadata["message"] == "Upload failed")
        #expect(metadata["upload_path"] == "walkthrough.mov")
        #expect(metadata["authorization_token"] == nil)
        #expect(metadata["email"] == nil)
        #expect(metadata["lat"] == nil)
    }

    @Test
    func telemetrySubmissionEncodesBackendContractWithBreadcrumbs() throws {
        let payload = CaptureClientTelemetrySubmission(
            eventId: "event-123",
            eventType: "nonfatal_error",
            severity: "warning",
            operation: "upload_file",
            status: "failure",
            occurredAt: "2026-07-08T12:00:00Z",
            sessionId: "session-123",
            captureId: "capture-123",
            appVersion: "1.0",
            appBuild: "42",
            osVersion: "18.5",
            deviceModel: "iPhone",
            metadata: ["capture_id": "capture-123"],
            breadcrumbs: [
                CaptureTelemetryBreadcrumb(
                    name: "capture_recording_started",
                    status: "av_capture",
                    occurredAt: "2026-07-08T11:59:00Z",
                    metadata: ["thermal_state": "nominal"]
                )
            ]
        )

        let data = try JSONEncoder().encode(payload)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["event_id"] as? String == "event-123")
        #expect(object["event_type"] as? String == "nonfatal_error")
        #expect(object["capture_id"] as? String == "capture-123")
        let breadcrumbs = try #require(object["breadcrumbs"] as? [[String: Any]])
        #expect(breadcrumbs.first?["name"] as? String == "capture_recording_started")
    }

    @Test
    func metadataSanitizerRedactsCredentialsIdentityAndLocationKeys() {
        let metadata = CaptureCrashTelemetryService.sanitizedMetadata([
            "api_token": "tok-1",
            "authorization": "Bearer abc",
            "password": "hunter2",
            "client_secret": "shh",
            "aws_credential": "AKIA...",
            "email": "user@example.com",
            "contact_email": "user@example.com",
            "phone_number": "+19195551234",
            "lat": 35.99,
            "lng": -78.9,
            "street_address": "123 Main St",
            "current_location": "35.99,-78.90",
            "operation": "upload_file"
        ])

        #expect(metadata["operation"] == "upload_file")
        for redactedKey in [
            "api_token", "authorization", "password", "client_secret",
            "aws_credential", "email", "contact_email", "phone_number",
            "lat", "lng", "street_address", "current_location"
        ] {
            #expect(metadata[redactedKey] == nil, "Expected \(redactedKey) to be redacted")
        }
    }

    @Test
    func metadataSanitizerTruncatesOversizedValuesAndStripsFilesystemPaths() {
        let oversized = String(repeating: "x", count: 5_000)
        let metadata = CaptureCrashTelemetryService.sanitizedMetadata([
            "detail": oversized,
            "bundle_path": "/var/mobile/Containers/Data/Application/ABC/Documents/capture/walkthrough.mov"
        ])

        let detail = metadata["detail"] ?? ""
        #expect(detail.count <= 240)
        #expect(metadata["bundle_path"] == "walkthrough.mov")
    }

    @Test
    func metadataSanitizerCapsThePairCount() {
        var oversizedMap: [String: Any] = [:]
        for index in 0..<60 {
            oversizedMap["key_\(String(format: "%03d", index))"] = "value"
        }
        let metadata = CaptureCrashTelemetryService.sanitizedMetadata(oversizedMap)
        #expect(metadata.count <= 20)
    }

    @Test
    func uncaughtExceptionCacheRoundTripsThroughUserDefaults() throws {
        let suiteName = "capture-telemetry-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let deepStack = (0..<40).map { "frame_\($0) " + String(repeating: "s", count: 400) }
        CaptureCrashTelemetryService.cacheUncaughtException(
            name: "NSGenericException !!",
            reason: String(repeating: "r", count: 2_000),
            callStackSymbols: deepStack,
            userDefaults: defaults,
            occurredAt: Date(timeIntervalSince1970: 1_752_690_000)
        )

        let data = try #require(defaults.data(forKey: "blueprint.capture.pending_crash_report"))
        let report = try JSONDecoder().decode(CapturePendingCrashReport.self, from: data)
        #expect(report.name.hasPrefix("NSGenericException"))
        #expect(!report.name.contains("!"))
        #expect(report.reason.count <= 240)
        #expect(report.callStackSymbols.count <= 12)
        #expect(report.callStackSymbols.allSatisfy { $0.count <= 240 })

        // Caching again must overwrite, not accumulate (no crash-loop growth).
        CaptureCrashTelemetryService.cacheUncaughtException(
            name: "SecondCrash",
            reason: nil,
            callStackSymbols: [],
            userDefaults: defaults,
            occurredAt: Date(timeIntervalSince1970: 1_752_690_100)
        )
        let second = try JSONDecoder().decode(
            CapturePendingCrashReport.self,
            from: try #require(defaults.data(forKey: "blueprint.capture.pending_crash_report"))
        )
        #expect(second.name == "SecondCrash")
        #expect(second.reason == "unknown")
    }
}
