package app.blueprint.capture.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
enum class DemandSourceKind {
    @SerialName("explicit_request") ExplicitRequest,
    @SerialName("operator_offer") OperatorOffer,
    @SerialName("cited_web_signal") CitedWebSignal,
    @SerialName("inferred_signal") InferredSignal,
    @SerialName("internal_behavioral_signal") InternalBehavioralSignal,
}

@Serializable
enum class DemandEvidenceStrength {
    @SerialName("low") Low,
    @SerialName("medium") Medium,
    @SerialName("high") High,
    @SerialName("critical") Critical,
}

@Serializable
data class RobotTeamDemandIntakePayload(
    @SerialName("requester_name") val requesterName: String? = null,
    @SerialName("requester_email") val requesterEmail: String? = null,
    @SerialName("company_name") val companyName: String,
    @SerialName("company_domain") val companyDomain: String? = null,
    @SerialName("company_id") val companyId: String? = null,
    @SerialName("target_geography") val targetGeography: String? = null,
    @SerialName("target_metros") val targetMetros: List<String> = emptyList(),
    @SerialName("site_types") val siteTypes: List<String>,
    val workflows: List<String> = emptyList(),
    val constraints: List<String> = emptyList(),
    @SerialName("target_kpis") val targetKpis: List<String> = emptyList(),
    val urgency: DemandEvidenceStrength = DemandEvidenceStrength.High,
    val notes: String? = null,
    val citations: List<String> = emptyList(),
)

@Serializable
data class SiteOperatorDemandIntakePayload(
    @SerialName("operator_name") val operatorName: String,
    @SerialName("operator_email") val operatorEmail: String? = null,
    @SerialName("company_name") val companyName: String? = null,
    @SerialName("site_name") val siteName: String,
    @SerialName("site_address") val siteAddress: String,
    val latitude: Double? = null,
    val longitude: Double? = null,
    @SerialName("site_types") val siteTypes: List<String>,
    val workflows: List<String> = emptyList(),
    @SerialName("access_readiness") val accessReadiness: DemandEvidenceStrength = DemandEvidenceStrength.Medium,
    @SerialName("consent_readiness") val consentReadiness: DemandEvidenceStrength = DemandEvidenceStrength.Medium,
    @SerialName("allowed_capture_windows") val allowedCaptureWindows: List<String> = emptyList(),
    val restrictions: List<String> = emptyList(),
    val notes: String? = null,
)

@Serializable
data class DemandSignalSubmissionReceipt(
    @SerialName("submission_id") val submissionId: String,
    @SerialName("demand_signal_ids") val demandSignalIds: List<String>,
    @SerialName("created_at") val createdAt: String? = null,
)

@Serializable
data class OpportunityCandidatePlace(
    @SerialName("place_id") val placeId: String,
    @SerialName("display_name") val displayName: String,
    @SerialName("formatted_address") val formattedAddress: String? = null,
    val lat: Double,
    val lng: Double,
    @SerialName("place_types") val placeTypes: List<String> = emptyList(),
)

@Serializable
data class DemandOpportunityFeedRequest(
    val lat: Double,
    val lng: Double,
    @SerialName("radius_m") val radiusMeters: Int,
    val limit: Int,
    @SerialName("candidate_places") val candidatePlaces: List<OpportunityCandidatePlace> = emptyList(),
)

@Serializable
data class RankedNearbyOpportunity(
    @SerialName("place_id") val placeId: String,
    @SerialName("display_name") val displayName: String,
    @SerialName("formatted_address") val formattedAddress: String? = null,
    val lat: Double,
    val lng: Double,
    @SerialName("place_types") val placeTypes: List<String> = emptyList(),
    @SerialName("site_type") val siteType: String? = null,
    @SerialName("site_type_confidence") val siteTypeConfidence: Double? = null,
    @SerialName("demand_score") val demandScore: Double,
    @SerialName("opportunity_score") val opportunityScore: Double,
    @SerialName("demand_summary") val demandSummary: String? = null,
    @SerialName("ranking_explanation") val rankingExplanation: String? = null,
    @SerialName("suggested_workflows") val suggestedWorkflows: List<String> = emptyList(),
    @SerialName("demand_source_kinds") val demandSourceKinds: List<DemandSourceKind> = emptyList(),
    @SerialName("top_signal_ids") val topSignalIds: List<String> = emptyList(),
)

@Serializable
data class DemandOpportunityFeedResponse(
    @SerialName("generated_at") val generatedAt: String? = null,
    @SerialName("nearby_opportunities") val nearbyOpportunities: List<RankedNearbyOpportunity> = emptyList(),
)
