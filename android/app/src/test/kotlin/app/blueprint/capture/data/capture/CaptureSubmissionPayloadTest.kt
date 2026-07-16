package app.blueprint.capture.data.capture

import com.google.common.truth.Truth.assertThat
import org.junit.Test

/**
 * Serialization-parity guard for the `capture_submissions` client contract.
 *
 * `firestore.rules` rejects any create/update whose payload contains a key
 * outside `captureSubmissionClientCreateKeys()`. These tests prove the Android
 * builder can only emit permitted keys, so a payload drift fails in CI instead
 * of failing every capture registration in the field. The rules side of the
 * same contract is covered by `cloud/firestore-rules-tests`.
 */
class CaptureSubmissionPayloadTest {

    private fun buildFullPayload(): MutableMap<String, Any> =
        CaptureSubmissionPayload.build(
            captureId = "capture-1",
            sceneId = "scene-1",
            creatorId = "creator-1",
            captureSource = "android",
            recordedAtEpochMs = 1_752_690_000_000L,
            captureStartEpochMs = 1_752_689_000_000L,
            uploadState = "uploaded",
            includeUploadStart = true,
            includeUploadCompletion = true,
            includeSubmittedAt = true,
            jobId = "job-1",
            captureJobId = "capture-job-1",
            siteSubmissionId = "site-submission-1",
            explicitBuyerRequestId = "buyer-request-1",
            quotedPayoutCents = 4500,
            requestedOutputs = listOf("frames"),
            registrationRawPrefix = "scenes/scene-1/captures/capture-1/raw/",
            siteIdentity = CaptureSubmissionSiteIdentity(
                siteId = "site-1",
                siteIdSource = "manual",
                siteName = "Main St Hardware",
                addressFull = "123 Main St, Durham, NC",
            ),
            workflowFit = "shelf restock",
            hasCaptureTopology = true,
        )

    private fun buildMinimalPayload(): MutableMap<String, Any> =
        CaptureSubmissionPayload.build(
            captureId = "capture-1",
            sceneId = "scene-1",
            creatorId = "creator-1",
            captureSource = "android",
            recordedAtEpochMs = 1_752_690_000_000L,
            captureStartEpochMs = 1_752_689_000_000L,
            uploadState = "uploading",
            includeUploadStart = true,
            includeUploadCompletion = false,
            includeSubmittedAt = false,
            jobId = null,
            captureJobId = null,
            siteSubmissionId = null,
            explicitBuyerRequestId = null,
            quotedPayoutCents = null,
            requestedOutputs = emptyList(),
            registrationRawPrefix = null,
            siteIdentity = null,
            workflowFit = null,
            hasCaptureTopology = false,
        )

    @Test
    fun `full payload serializes only rules-permitted keys`() {
        val payload = buildFullPayload()
        assertThat(payload.keys).containsNoneIn(
            payload.keys - CaptureSubmissionPayload.clientCreateKeys,
        )
        assertThat(CaptureSubmissionPayload.clientCreateKeys).containsAtLeastElementsIn(payload.keys)
    }

    @Test
    fun `minimal payload serializes only rules-permitted keys`() {
        val payload = buildMinimalPayload()
        assertThat(CaptureSubmissionPayload.clientCreateKeys).containsAtLeastElementsIn(payload.keys)
    }

    @Test
    fun `legacy motion and scheduling metadata keys are never emitted`() {
        // These keys are carried by the canonical raw bundle, not by
        // capture_submissions; the deployed rules reject them, which would
        // fail the entire registration write.
        val forbidden = setOf(
            "capture_start_epoch_ms",
            "capture_duration_ms",
            "motion_sample_count",
            "motion_provenance",
            "priority_weight",
            "reservation_id",
            "imu_samples_available",
        )
        assertThat(buildFullPayload().keys).containsNoneIn(forbidden)
        assertThat(buildMinimalPayload().keys).containsNoneIn(forbidden)
        assertThat(CaptureSubmissionPayload.clientCreateKeys).containsNoneIn(forbidden)
    }

    @Test
    fun `client payload never claims server-owned money or QA fields`() {
        val forbidden = setOf("payout_cents", "paid_at", "qa_outcome", "stats", "world_model_candidate")
        assertThat(CaptureSubmissionPayload.clientCreateKeys).containsNoneIn(forbidden)
        assertThat(buildFullPayload().keys).containsNoneIn(forbidden)
    }

    @Test
    fun `operational state stays within client-writable values`() {
        val payload = buildFullPayload()
        @Suppress("UNCHECKED_CAST")
        val operationalState = payload["operational_state"] as Map<String, Any>
        assertThat(operationalState.keys).containsExactly(
            "assignment_state",
            "upload_state",
            "qa_state",
            "repeat_ready",
        )
        assertThat(operationalState["assignment_state"]).isEqualTo("assigned_capture_job")
        assertThat(operationalState["upload_state"]).isEqualTo("uploaded")
        assertThat(operationalState["qa_state"]).isEqualTo("queued")
        assertThat(payload["status"]).isEqualTo("submitted")
    }

    @Test
    fun `completion payload carries submitted_at and uploaded lifecycle`() {
        val payload = buildFullPayload()
        assertThat(payload).containsKey("submitted_at")
        @Suppress("UNCHECKED_CAST")
        val lifecycle = payload["lifecycle"] as Map<String, Any>
        assertThat(lifecycle.keys).containsExactly(
            "capture_started_at",
            "upload_started_at",
            "capture_uploaded_at",
        )
    }

    @Test
    fun `minimal payload omits optional keys instead of writing placeholders`() {
        val payload = buildMinimalPayload()
        assertThat(payload.keys).containsExactly(
            "capture_id",
            "scene_id",
            "creator_id",
            "capture_source",
            "created_at",
            "status",
            "operational_state",
            "lifecycle",
        )
    }

    @Test
    fun `buyer request id resolves from buyer_request site identity`() {
        assertThat(
            CaptureSubmissionPayload.resolvedBuyerRequestId(
                CaptureSubmissionSiteIdentity(
                    siteId = "buyer-req-9",
                    siteIdSource = "buyer_request",
                    siteName = null,
                    addressFull = null,
                ),
            ),
        ).isEqualTo("buyer-req-9")
        assertThat(
            CaptureSubmissionPayload.resolvedBuyerRequestId(
                CaptureSubmissionSiteIdentity(
                    siteId = "site-1",
                    siteIdSource = "manual",
                    siteName = null,
                    addressFull = null,
                ),
            ),
        ).isNull()
    }
}
