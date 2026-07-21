package app.blueprint.capture.data.telemetry

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class CaptureClientTelemetryServiceTest {

    @Test
    fun `metadata sanitizer redacts secrets and raw location while preserving capture ids`() {
        val sanitized = CaptureClientTelemetryService.sanitizedMetadata(
            mapOf(
                "capture_id" to "cap-123",
                "authorization" to "Bearer secret",
                "operator_email" to "field@example.com",
                "address_full" to "123 Site Street",
                "local_bundle_path" to "/private/var/mobile/raw/capture-root",
                "motion_sample_count" to 42,
            ),
        )

        assertThat(sanitized).containsEntry("capture_id", "cap-123")
        assertThat(sanitized).containsEntry("local_bundle_path", "capture-root")
        assertThat(sanitized).containsEntry("motion_sample_count", "42")
        assertThat(sanitized).doesNotContainKey("authorization")
        assertThat(sanitized).doesNotContainKey("operator_email")
        assertThat(sanitized).doesNotContainKey("address_full")
        assertThat(sanitized["local_bundle_path"]).doesNotContain("/")
    }

    @Test
    fun `cached uncaught exception payload is critical and routes to crash collection`() {
        val breadcrumb = CaptureTelemetryBreadcrumb(
            name = "capture_recording_started",
            status = "android_phone",
            occurredAt = "2026-07-09T12:00:00Z",
            metadata = mapOf("capture_id" to "cap-123"),
        )
        val payload = CaptureClientTelemetryService.makeTelemetrySubmission(
            eventType = "cached_uncaught_exception",
            severity = "critical",
            operation = "java.lang.IllegalStateException",
            status = "flushed_after_launch",
            creatorId = "creator-123",
            sessionId = "session-123",
            metadata = mapOf("capture_id" to "cap-123", "reason" to "boom"),
            breadcrumbs = listOf(breadcrumb),
            deviceModel = "Pixel 9",
            osVersion = "Android 16",
            appVersion = "0.1.0",
            appBuild = "1",
            occurredAt = "2026-07-09T12:01:00Z",
        )
        val firestorePayload = CaptureClientTelemetryService.firestorePayload(payload)

        assertThat(CaptureClientTelemetryService.isCrashPayload(payload)).isTrue()
        assertThat(firestorePayload).containsEntry("platform", "android")
        assertThat(firestorePayload).containsEntry("beta_alert_candidate", true)
        assertThat(firestorePayload).containsEntry("capture_id", "cap-123")
        assertThat(payload.breadcrumbs).containsExactly(breadcrumb)
    }

    @Test
    fun `pending crash report stores stack and breadcrumbs without raw throwable message overflow`() {
        val error = IllegalStateException("x".repeat(300))
        val report = CaptureClientTelemetryService.makePendingCrashReport(
            throwable = error,
            threadName = "main",
            breadcrumbs = listOf(
                CaptureTelemetryBreadcrumb(
                    name = "capture_upload_attempt_started",
                    status = "attempt_1",
                    occurredAt = "2026-07-09T12:00:00Z",
                ),
            ),
            deviceModel = "Pixel 9",
            osVersion = "Android 16",
            appVersion = "0.1.0",
            appBuild = "1",
            occurredAt = "2026-07-09T12:02:00Z",
        )

        assertThat(report.name).isEqualTo("java.lang.IllegalStateException")
        assertThat(report.reason.length).isAtMost(240)
        assertThat(report.threadName).isEqualTo("main")
        assertThat(report.callStackSymbols.size).isAtMost(12)
        assertThat(report.breadcrumbs.single().name).isEqualTo("capture_upload_attempt_started")
    }
}
