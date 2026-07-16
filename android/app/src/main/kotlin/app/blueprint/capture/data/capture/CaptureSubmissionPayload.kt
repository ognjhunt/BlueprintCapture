package app.blueprint.capture.data.capture

import com.google.firebase.Timestamp
import java.util.Date

/** Site identity extracted from the raw bundle's `raw/site_identity.json`. */
internal data class CaptureSubmissionSiteIdentity(
    val siteId: String?,
    val siteIdSource: String?,
    val siteName: String?,
    val addressFull: String?,
)

/**
 * Builds the `capture_submissions/{captureId}` client payload.
 *
 * The payload may serialize ONLY keys permitted by
 * `captureSubmissionClientCreateKeys()` in `firestore.rules` (kept in parity
 * with the iOS builder in `CaptureUploadService.captureSubmissionPayload`);
 * any extra key fails the whole registration write under the deployed rules.
 *
 * Capture timing, motion samples, and motion provenance are deliberately NOT
 * serialized here: the canonical raw bundle (manifest + motion files) is the
 * authoritative carrier of that capture truth.
 */
internal object CaptureSubmissionPayload {

    /**
     * Mirror of `captureSubmissionClientCreateKeys()` in `firestore.rules`.
     * `CaptureSubmissionPayloadTest` asserts every built payload stays within
     * this set, and the Firebase-emulator suite in
     * `cloud/firestore-rules-tests` asserts the rules enforce it.
     */
    val clientCreateKeys: Set<String> = setOf(
        "capture_id",
        "scene_id",
        "creator_id",
        "job_id",
        "capture_source",
        "status",
        "requested_outputs",
        "has_site_identity",
        "has_capture_topology",
        "created_at",
        "submitted_at",
        "capture_job_id",
        "buyer_request_id",
        "site_submission_id",
        "region_id",
        "estimated_payout_cents",
        "rights_profile",
        "target_address",
        "site_identity",
        "city_context",
        "target_context",
        "raw_prefix",
        "operational_state",
        "lifecycle",
        "upload_error",
    )

    fun build(
        captureId: String,
        sceneId: String,
        creatorId: String,
        captureSource: String,
        recordedAtEpochMs: Long,
        captureStartEpochMs: Long,
        uploadState: String,
        includeUploadStart: Boolean,
        includeUploadCompletion: Boolean,
        includeSubmittedAt: Boolean,
        jobId: String?,
        captureJobId: String?,
        siteSubmissionId: String?,
        explicitBuyerRequestId: String?,
        quotedPayoutCents: Int?,
        requestedOutputs: List<String>,
        registrationRawPrefix: String?,
        siteIdentity: CaptureSubmissionSiteIdentity?,
        workflowFit: String?,
        hasCaptureTopology: Boolean,
    ): MutableMap<String, Any> {
        val recordedAt = Timestamp(Date(recordedAtEpochMs))

        val lifecycle = linkedMapOf<String, Any>(
            "capture_started_at" to Timestamp(Date(captureStartEpochMs)),
        )
        if (includeUploadStart) {
            lifecycle["upload_started_at"] = recordedAt
        }
        if (includeUploadCompletion) {
            lifecycle["capture_uploaded_at"] = recordedAt
        }

        val payload = linkedMapOf<String, Any>(
            "capture_id" to captureId,
            "scene_id" to sceneId,
            "creator_id" to creatorId,
            "capture_source" to captureSource,
            "created_at" to recordedAt,
            "status" to "submitted",
            "operational_state" to linkedMapOf(
                "assignment_state" to if (captureJobId.isNullOrBlank()) {
                    "unassigned_or_open_capture"
                } else {
                    "assigned_capture_job"
                },
                "upload_state" to uploadState,
                "qa_state" to "queued",
                "repeat_ready" to false,
            ),
            "lifecycle" to lifecycle,
        )

        if (includeSubmittedAt) {
            payload["submitted_at"] = recordedAt
        }
        jobId?.takeIf(String::isNotBlank)?.let { payload["job_id"] = it }
        captureJobId?.takeIf(String::isNotBlank)?.let { payload["capture_job_id"] = it }
        siteSubmissionId?.takeIf(String::isNotBlank)?.let { payload["site_submission_id"] = it }
        val buyerRequestId = explicitBuyerRequestId?.takeIf(String::isNotBlank)
            ?: resolvedBuyerRequestId(siteIdentity)
        buyerRequestId?.let { payload["buyer_request_id"] = it }
        quotedPayoutCents?.let { payload["estimated_payout_cents"] = it }
        if (requestedOutputs.isNotEmpty()) {
            payload["requested_outputs"] = requestedOutputs
        }
        registrationRawPrefix?.takeIf(String::isNotBlank)?.let { payload["raw_prefix"] = it }

        if (siteIdentity != null) {
            payload["has_site_identity"] = true
            payload["site_identity"] = linkedMapOf<String, Any?>(
                "site_id" to siteIdentity.siteId,
                "site_id_source" to siteIdentity.siteIdSource,
                "site_name" to siteIdentity.siteName,
                "address_full" to siteIdentity.addressFull,
            )
            siteIdentity.addressFull?.takeIf(String::isNotBlank)?.let { payload["target_address"] = it }
            buildCityContext(siteIdentity.addressFull)?.let { payload["city_context"] = it }
            val targetId = siteIdentity.siteId?.takeIf(String::isNotBlank)
            val resolvedWorkflowFit = workflowFit?.takeIf(String::isNotBlank)
            if (targetId != null || resolvedWorkflowFit != null) {
                payload["target_context"] = linkedMapOf<String, Any>().apply {
                    targetId?.let { put("target_id", it) }
                    resolvedWorkflowFit?.let { put("workflow_fit", it) }
                }
            }
        }

        if (hasCaptureTopology) {
            payload["has_capture_topology"] = true
        }

        return payload
    }

    fun resolvedBuyerRequestId(siteIdentity: CaptureSubmissionSiteIdentity?): String? {
        val source = siteIdentity?.siteIdSource?.trim().orEmpty()
        val siteId = siteIdentity?.siteId?.trim().orEmpty()
        return if (source == "buyer_request" && siteId.isNotEmpty()) siteId else null
    }

    fun buildCityContext(addressFull: String?): Map<String, Any>? {
        val normalized = addressFull?.trim().orEmpty()
        if (normalized.isEmpty()) {
            return null
        }

        if (normalized.contains("·")) {
            val city = normalized.substringAfterLast("·").trim()
            if (city.isNotEmpty()) {
                return mapOf(
                    "city" to city,
                    "city_slug" to slugifyCity(city),
                )
            }
        }

        val commaParts = normalized.split(",").map { it.trim() }.filter { it.isNotEmpty() }
        if (commaParts.size >= 2) {
            val city = commaParts[commaParts.size - 2]
            if (city.isNotEmpty()) {
                return mapOf(
                    "city" to city,
                    "city_slug" to slugifyCity(city),
                )
            }
        }

        return null
    }

    fun slugifyCity(value: String): String = value
        .trim()
        .lowercase()
        .replace(Regex("[^a-z0-9]+"), "-")
        .trim('-')
}
