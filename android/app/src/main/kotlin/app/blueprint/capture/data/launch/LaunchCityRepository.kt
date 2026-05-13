package app.blueprint.capture.data.launch

import app.blueprint.capture.data.config.LocalConfigProvider
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request

@Singleton
class LaunchCityRepository @Inject constructor(
    private val localConfigProvider: LocalConfigProvider,
) {
    private val httpClient = OkHttpClient()
    private val json = Json { ignoreUnknownKeys = true }

    suspend fun fetchLaunchStatus(city: String?, stateCode: String?): Result<CreatorLaunchStatusResponse> =
        withContext(Dispatchers.IO) {
            runCatching {
                val config = localConfigProvider.current()
                val baseUrl = config.backendBaseUrl.trim().ifBlank {
                    error("BLUEPRINT_BACKEND_BASE_URL is not configured.")
                }
                val builder = baseUrl.trimEnd('/')
                    .plus("/v1/creator/launch-status")
                    .toHttpUrlOrNull()
                    ?.newBuilder()
                    ?: error("BLUEPRINT_BACKEND_BASE_URL is invalid.")
                city?.takeIf(String::isNotBlank)?.let { builder.addQueryParameter("city", it) }
                stateCode?.takeIf(String::isNotBlank)?.let { builder.addQueryParameter("state_code", it) }

                val request = Request.Builder()
                    .url(builder.build())
                    .get()
                    .build()
                httpClient.newCall(request).execute().use { response ->
                    if (!response.isSuccessful) {
                        error("Launch status check failed with HTTP ${response.code}.")
                    }
                    json.decodeFromString<CreatorLaunchStatusResponse>(response.body?.string().orEmpty())
                }
            }
        }
}
