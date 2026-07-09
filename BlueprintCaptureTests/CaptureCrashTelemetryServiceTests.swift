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
}
