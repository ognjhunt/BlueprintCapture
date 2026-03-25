package app.blueprint.capture.data.opportunities

import app.blueprint.capture.data.auth.AuthRepository
import app.blueprint.capture.data.config.LocalConfigProvider
import app.blueprint.capture.data.model.DemandOpportunityFeedRequest
import app.blueprint.capture.data.model.DemandOpportunityFeedResponse
import app.blueprint.capture.data.model.DemandSignalSubmissionReceipt
import app.blueprint.capture.data.model.RobotTeamDemandIntakePayload
import app.blueprint.capture.data.model.SiteOperatorDemandIntakePayload
import java.io.IOException
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

@Singleton
class DemandIntelligenceBackendApi @Inject constructor(
    private val localConfigProvider: LocalConfigProvider,
    private val authRepository: AuthRepository,
) {
    sealed class ApiError(message: String) : IOException(message) {
        data object MissingBaseUrl :
            ApiError("BLUEPRINT_BACKEND_BASE_URL is not configured for this build.")

        data class InvalidResponse(val statusCode: Int) :
            ApiError(
                if (statusCode == -1) {
                    "The backend returned an invalid non-HTTP response."
                } else {
                    "The backend returned HTTP $statusCode."
                },
            )
    }

    private val httpClient = OkHttpClient()
    private val json = Json {
        encodeDefaults = true
        ignoreUnknownKeys = true
        explicitNulls = false
    }
    private val jsonMediaType = "application/json".toMediaType()

    suspend fun submitRobotTeamDemand(
        creatorId: String,
        payload: RobotTeamDemandIntakePayload,
    ): DemandSignalSubmissionReceipt {
        val body = json.encodeToString(payload).toRequestBody(jsonMediaType)
        val responseBody = perform(
            creatorId = creatorId,
            path = "v1/demand/robot-team-requests",
            method = "POST",
            body = body,
            expectedStatus = 201,
        )
        return json.decodeFromString(responseBody)
    }

    suspend fun submitSiteOperatorDemand(
        creatorId: String,
        payload: SiteOperatorDemandIntakePayload,
    ): DemandSignalSubmissionReceipt {
        val body = json.encodeToString(payload).toRequestBody(jsonMediaType)
        val responseBody = perform(
            creatorId = creatorId,
            path = "v1/demand/site-operator-submissions",
            method = "POST",
            body = body,
            expectedStatus = 201,
        )
        return json.decodeFromString(responseBody)
    }

    suspend fun fetchDemandOpportunityFeed(
        creatorId: String,
        requestPayload: DemandOpportunityFeedRequest,
    ): DemandOpportunityFeedResponse {
        val body = json.encodeToString(requestPayload).toRequestBody(jsonMediaType)
        val responseBody = perform(
            creatorId = creatorId,
            path = "v1/opportunities/feed",
            method = "POST",
            body = body,
            expectedStatus = 200,
        )
        return json.decodeFromString(responseBody)
    }

    private suspend fun perform(
        creatorId: String,
        path: String,
        method: String,
        body: okhttp3.RequestBody? = null,
        expectedStatus: Int,
    ): String {
        val (responseBody, statusCode) = performWithStatus(
            creatorId = creatorId,
            path = path,
            method = method,
            body = body,
        )
        if (statusCode != expectedStatus && !(expectedStatus == 200 && statusCode in 200..299)) {
            throw ApiError.InvalidResponse(statusCode)
        }
        return responseBody
    }

    private suspend fun performWithStatus(
        creatorId: String,
        path: String,
        method: String,
        body: okhttp3.RequestBody? = null,
    ): Pair<String, Int> = withContext(Dispatchers.IO) {
        val config = localConfigProvider.current()
        val baseUrl = config.demandBackendBaseUrl.ifBlank { config.backendBaseUrl }.trim()
        if (baseUrl.isBlank()) {
            throw ApiError.MissingBaseUrl
        }

        val url = buildString {
            append(baseUrl.trimEnd('/'))
            append('/')
            append(path.trimStart('/'))
        }

        val request = Request.Builder()
            .url(url)
            .method(method, body)
            .header("Accept", "application/json")
            .header("X-Blueprint-Creator-Id", creatorId)
            .apply {
                authRepository.currentIdToken()?.let { token ->
                    header("Authorization", "Bearer $token")
                }
                if (body != null) {
                    header("Content-Type", "application/json")
                }
            }
            .build()

        httpClient.newCall(request).execute().use { response ->
            Pair(response.body?.string().orEmpty(), response.code)
        }
    }
}
