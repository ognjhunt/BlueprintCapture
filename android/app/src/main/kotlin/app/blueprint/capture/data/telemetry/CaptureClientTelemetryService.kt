package app.blueprint.capture.data.telemetry

import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import android.os.Process
import android.util.Log
import androidx.core.content.edit
import app.blueprint.capture.BuildConfig
import app.blueprint.capture.data.auth.AuthRepository
import app.blueprint.capture.data.config.LocalConfigProvider
import com.google.firebase.crashlytics.FirebaseCrashlytics
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.SetOptions
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.File
import java.time.Instant
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.system.exitProcess
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

@Serializable
data class CaptureTelemetryBreadcrumb(
    val name: String,
    val status: String,
    @SerialName("occurred_at") val occurredAt: String,
    val metadata: Map<String, String> = emptyMap(),
)

@Serializable
data class CapturePendingCrashReport(
    val id: String,
    val name: String,
    val reason: String,
    @SerialName("occurred_at") val occurredAt: String,
    @SerialName("app_version") val appVersion: String,
    @SerialName("app_build") val appBuild: String,
    @SerialName("os_version") val osVersion: String,
    @SerialName("device_model") val deviceModel: String,
    @SerialName("thread_name") val threadName: String,
    @SerialName("call_stack_symbols") val callStackSymbols: List<String>,
    val breadcrumbs: List<CaptureTelemetryBreadcrumb>,
)

@Serializable
data class CaptureClientTelemetrySubmission(
    @SerialName("event_id") val eventId: String,
    @SerialName("event_type") val eventType: String,
    val severity: String,
    val operation: String,
    val status: String,
    @SerialName("occurred_at") val occurredAt: String,
    @SerialName("creator_id") val creatorId: String?,
    @SerialName("session_id") val sessionId: String?,
    @SerialName("capture_id") val captureId: String?,
    @SerialName("app_version") val appVersion: String,
    @SerialName("app_build") val appBuild: String,
    @SerialName("os_version") val osVersion: String,
    @SerialName("device_model") val deviceModel: String,
    val metadata: Map<String, String>,
    val breadcrumbs: List<CaptureTelemetryBreadcrumb>,
    val source: String = "blueprint_capture_android_client",
)

@Singleton
class CaptureClientTelemetryService @Inject constructor(
    @ApplicationContext context: Context,
    private val firestore: FirebaseFirestore,
    private val authRepository: AuthRepository,
    private val localConfigProvider: LocalConfigProvider,
) {
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val httpClient = OkHttpClient()
    private val json = Json {
        encodeDefaults = true
        explicitNulls = false
        ignoreUnknownKeys = true
    }
    private val jsonMediaType = "application/json".toMediaType()
    private val preferences: SharedPreferences =
        context.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)
    private val lock = Any()
    private var configured = false
    private var previousHandler: Thread.UncaughtExceptionHandler? = null
    private var breadcrumbs: List<CaptureTelemetryBreadcrumb> = loadBreadcrumbs(preferences, json)

    fun configure() {
        synchronized(lock) {
            if (configured) return
            configured = true
        }

        runCatching {
            FirebaseCrashlytics.getInstance().setCustomKey("blueprint_client_telemetry", "android_capture")
        }.onFailure {
            Log.w(TAG, "Crashlytics is unavailable; Firestore/backend telemetry remains active.", it)
        }

        previousHandler = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            cacheUncaughtException(thread, throwable)
            runCatching {
                FirebaseCrashlytics.getInstance().recordException(throwable)
            }
            previousHandler?.uncaughtException(thread, throwable) ?: run {
                Process.killProcess(Process.myPid())
                exitProcess(10)
            }
        }

        flushPendingCrashReport()
        recordBreadcrumb(
            name = "client_telemetry_configured",
            status = "crashlytics_firestore_backend_linked",
            metadata = mapOf("transport" to "firebase_crashlytics_firestore_backend"),
        )
    }

    fun recordBreadcrumb(
        name: String,
        status: String,
        metadata: Map<String, Any?> = emptyMap(),
    ) {
        val breadcrumb = CaptureTelemetryBreadcrumb(
            name = safeIdentifier(name),
            status = safeIdentifier(status),
            occurredAt = nowIsoString(),
            metadata = sanitizedMetadata(metadata),
        )
        val snapshot = synchronized(lock) {
            breadcrumbs = (breadcrumbs + breadcrumb).takeLast(maxBreadcrumbs)
            breadcrumbs
        }
        persistBreadcrumbs(preferences, json, snapshot)
        runCatching {
            FirebaseCrashlytics.getInstance().log("${breadcrumb.name}:${breadcrumb.status}")
        }
    }

    fun recordOperationalBreadcrumb(
        operation: String,
        status: String,
        metadata: Map<String, Any?> = emptyMap(),
    ) {
        recordBreadcrumb(name = operation, status = status, metadata = metadata)
        if (!isFailureStatus(status)) return
        emitTelemetryEvent(
            eventType = "operational_failure",
            severity = if (status.lowercase().contains("critical")) "critical" else "warning",
            operation = operation,
            status = status,
            metadata = metadata,
        )
    }

    fun recordErrorCode(
        errorCode: String,
        metadata: Map<String, Any?> = emptyMap(),
    ) {
        recordBreadcrumb(name = "error_$errorCode", status = "failure", metadata = metadata)
        emitTelemetryEvent(
            eventType = "nonfatal_error",
            severity = "warning",
            operation = errorCode,
            status = "failure",
            metadata = metadata,
        )
    }

    private fun flushPendingCrashReport() {
        val report = consumePendingCrashReport(preferences, json) ?: return
        emitTelemetryEvent(
            eventType = "cached_uncaught_exception",
            severity = "critical",
            operation = report.name,
            status = "flushed_after_launch",
            metadata = mapOf(
                "pending_crash_id" to report.id,
                "reason" to report.reason,
                "thread_name" to report.threadName,
                "cached_at_launch" to true,
                "call_stack_top" to report.callStackSymbols.firstOrNull().orEmpty(),
            ),
            breadcrumbsOverride = report.breadcrumbs,
            deviceOverride = report.deviceModel,
            osVersionOverride = report.osVersion,
            appVersionOverride = report.appVersion,
            appBuildOverride = report.appBuild,
            occurredAtOverride = report.occurredAt,
        )
    }

    private fun emitTelemetryEvent(
        eventType: String,
        severity: String,
        operation: String,
        status: String,
        metadata: Map<String, Any?>,
        breadcrumbsOverride: List<CaptureTelemetryBreadcrumb>? = null,
        deviceOverride: String? = null,
        osVersionOverride: String? = null,
        appVersionOverride: String? = null,
        appBuildOverride: String? = null,
        occurredAtOverride: String? = null,
    ) {
        val payload = makeTelemetrySubmission(
            eventType = eventType,
            severity = severity,
            operation = operation,
            status = status,
            creatorId = authRepository.currentUserId() ?: "anonymous",
            sessionId = sanitizedMetadata(metadata)["session_id"],
            metadata = metadata,
            breadcrumbs = breadcrumbsOverride ?: currentBreadcrumbs(),
            deviceModel = deviceOverride ?: deviceModel(),
            osVersion = osVersionOverride ?: osVersion(),
            appVersion = appVersionOverride ?: BuildConfig.VERSION_NAME,
            appBuild = appBuildOverride ?: BuildConfig.VERSION_CODE.toString(),
            occurredAt = occurredAtOverride ?: nowIsoString(),
        )
        writeToCrashlytics(payload)
        writeToFirestore(payload)
        forwardToBackendAlerting(payload)
    }

    private fun writeToCrashlytics(payload: CaptureClientTelemetrySubmission) {
        runCatching {
            val crashlytics = FirebaseCrashlytics.getInstance()
            crashlytics.setCustomKey("blueprint_event_id", payload.eventId)
            crashlytics.setCustomKey("blueprint_event_type", payload.eventType)
            payload.captureId?.let { crashlytics.setCustomKey("blueprint_capture_id", it) }
            payload.sessionId?.let { crashlytics.setCustomKey("blueprint_session_id", it) }
            crashlytics.recordException(
                IllegalStateException("${payload.eventType}:${payload.operation}:${payload.status}"),
            )
        }.onFailure {
            Log.w(TAG, "Crashlytics write failed for ${payload.eventId}", it)
        }
    }

    private fun writeToFirestore(payload: CaptureClientTelemetrySubmission) {
        val firestorePayload = firestorePayload(payload).toMutableMap()
        firestorePayload["created_at"] = FieldValue.serverTimestamp()
        firestore.collection(telemetryCollection)
            .document(payload.eventId)
            .set(firestorePayload, SetOptions.merge())
            .addOnFailureListener { error ->
                Log.w(TAG, "Failed to write capture client telemetry ${payload.eventId}", error)
            }

        val collection = if (isCrashPayload(payload)) crashReportsCollection else errorTelemetryCollection
        firestore.collection(collection)
            .document(payload.eventId)
            .set(firestorePayload, SetOptions.merge())
            .addOnFailureListener { error ->
                Log.w(TAG, "Failed to write $collection/${payload.eventId}", error)
            }
    }

    private fun forwardToBackendAlerting(payload: CaptureClientTelemetrySubmission) {
        serviceScope.launch {
            val baseUrl = localConfigProvider.current().backendBaseUrl.trim()
            if (baseUrl.isBlank()) {
                Log.i(TAG, "Skipping backend client telemetry forward because BLUEPRINT_BACKEND_BASE_URL is not configured.")
                return@launch
            }
            val requestBody = json.encodeToString(payload).toRequestBody(jsonMediaType)
            val idToken = authRepository.currentIdToken()
            val request = Request.Builder()
                .url("${baseUrl.trimEnd('/')}/v1/creator/client-telemetry")
                .post(requestBody)
                .header("Accept", "application/json")
                .header("Content-Type", "application/json")
                .header("X-Blueprint-Creator-Id", payload.creatorId ?: "anonymous")
                .apply {
                    idToken?.let { token ->
                        header("Authorization", "Bearer $token")
                    }
                }
                .build()

            runCatching {
                withContext(Dispatchers.IO) {
                    httpClient.newCall(request).execute().use { response ->
                        if (!response.isSuccessful) {
                            throw IllegalStateException("Backend telemetry returned HTTP ${response.code}")
                        }
                    }
                }
            }.onFailure { error ->
                Log.w(TAG, "Failed to forward client telemetry ${payload.eventId} to backend alerting.", error)
                runCatching {
                    FirebaseCrashlytics.getInstance().log("client_telemetry_backend_forward_failed")
                }
            }
        }
    }

    private fun cacheUncaughtException(thread: Thread, throwable: Throwable) {
        val report = makePendingCrashReport(
            throwable = throwable,
            threadName = thread.name,
            breadcrumbs = currentBreadcrumbs(),
            deviceModel = deviceModel(),
            osVersion = osVersion(),
            appVersion = BuildConfig.VERSION_NAME,
            appBuild = BuildConfig.VERSION_CODE.toString(),
            occurredAt = nowIsoString(),
        )
        preferences.edit {
            putString(pendingCrashKey, json.encodeToString(report))
        }
    }

    private fun currentBreadcrumbs(): List<CaptureTelemetryBreadcrumb> =
        synchronized(lock) { breadcrumbs }

    companion object {
        internal const val telemetryCollection = "captureClientTelemetry"
        internal const val crashReportsCollection = "clientCrashReports"
        internal const val errorTelemetryCollection = "clientErrorTelemetry"
        private const val TAG = "CaptureClientTelemetry"
        private const val preferencesName = "blueprint_capture_client_telemetry"
        private const val pendingCrashKey = "pending_crash_report"
        private const val breadcrumbsKey = "telemetry_breadcrumbs"
        private const val maxBreadcrumbs = 24
        private const val maxMetadataPairs = 20
        private const val maxMetadataValueLength = 240

        internal fun makeTelemetrySubmission(
            eventType: String,
            severity: String,
            operation: String,
            status: String,
            creatorId: String?,
            sessionId: String?,
            metadata: Map<String, Any?>,
            breadcrumbs: List<CaptureTelemetryBreadcrumb>,
            deviceModel: String,
            osVersion: String,
            appVersion: String,
            appBuild: String,
            occurredAt: String,
        ): CaptureClientTelemetrySubmission {
            val safeMetadata = sanitizedMetadata(metadata)
            val captureId = safeMetadata["capture_id"]
            return CaptureClientTelemetrySubmission(
                eventId = UUID.randomUUID().toString().lowercase(),
                eventType = safeIdentifier(eventType),
                severity = safeIdentifier(severity),
                operation = safeIdentifier(operation),
                status = safeIdentifier(status),
                occurredAt = occurredAt,
                creatorId = creatorId?.takeIf(String::isNotBlank),
                sessionId = sessionId?.takeIf(String::isNotBlank) ?: safeMetadata["session_id"],
                captureId = captureId,
                appVersion = appVersion,
                appBuild = appBuild,
                osVersion = osVersion,
                deviceModel = deviceModel,
                metadata = safeMetadata,
                breadcrumbs = breadcrumbs.takeLast(maxBreadcrumbs),
            )
        }

        internal fun makePendingCrashReport(
            throwable: Throwable,
            threadName: String,
            breadcrumbs: List<CaptureTelemetryBreadcrumb>,
            deviceModel: String,
            osVersion: String,
            appVersion: String,
            appBuild: String,
            occurredAt: String,
        ): CapturePendingCrashReport = CapturePendingCrashReport(
            id = UUID.randomUUID().toString().lowercase(),
            name = safeIdentifier(throwable::class.java.name),
            reason = sanitizeMetadataValue(throwable.message ?: "unknown", key = "reason"),
            occurredAt = occurredAt,
            appVersion = appVersion,
            appBuild = appBuild,
            osVersion = osVersion,
            deviceModel = deviceModel,
            threadName = sanitizeMetadataValue(threadName, key = "thread_name"),
            callStackSymbols = throwable.stackTrace
                .take(12)
                .map { sanitizeMetadataValue(it.toString(), key = "call_stack") },
            breadcrumbs = breadcrumbs.takeLast(maxBreadcrumbs),
        )

        internal fun isFailureStatus(status: String): Boolean {
            val normalized = status.lowercase()
            return normalized.contains("fail") ||
                normalized.contains("error") ||
                normalized.contains("expired") ||
                normalized.contains("blocked") ||
                normalized.contains("crash")
        }

        internal fun isCrashPayload(payload: CaptureClientTelemetrySubmission): Boolean {
            val eventType = payload.eventType.lowercase()
            return payload.severity == "critical" ||
                eventType.contains("crash") ||
                eventType.contains("uncaught")
        }

        internal fun sanitizedMetadata(metadata: Map<String, Any?>?): Map<String, String> {
            if (metadata.isNullOrEmpty()) return emptyMap()
            return metadata.keys.sorted().take(maxMetadataPairs).mapNotNull { key ->
                val cleanKey = safeIdentifier(key)
                if (shouldRedactMetadataKey(cleanKey)) return@mapNotNull null
                val value = metadata[key] ?: return@mapNotNull null
                val cleanValue = sanitizeMetadataValue(value, cleanKey)
                if (cleanValue.isBlank()) null else cleanKey to cleanValue
            }.toMap()
        }

        internal fun firestorePayload(payload: CaptureClientTelemetrySubmission): Map<String, Any> {
            val firestorePayload = linkedMapOf<String, Any>(
                "event_id" to payload.eventId,
                "event_type" to payload.eventType,
                "severity" to payload.severity,
                "operation" to payload.operation,
                "status" to payload.status,
                "occurred_at" to payload.occurredAt,
                "app_version" to payload.appVersion,
                "app_build" to payload.appBuild,
                "os_version" to payload.osVersion,
                "device_model" to payload.deviceModel,
                "metadata" to payload.metadata,
                "breadcrumbs" to payload.breadcrumbs.map { breadcrumb ->
                    linkedMapOf<String, Any>(
                        "name" to breadcrumb.name,
                        "status" to breadcrumb.status,
                        "occurred_at" to breadcrumb.occurredAt,
                        "metadata" to breadcrumb.metadata,
                    )
                },
                "source" to payload.source,
                "beta_alert_candidate" to true,
                "platform" to "android",
            )
            payload.creatorId?.let { firestorePayload["creator_id"] = it }
            payload.sessionId?.let { firestorePayload["session_id"] = it }
            payload.captureId?.let { firestorePayload["capture_id"] = it }
            return firestorePayload
        }

        private fun shouldRedactMetadataKey(key: String): Boolean {
            val lower = key.lowercase()
            if (
                lower.contains("token") ||
                lower.contains("authorization") ||
                lower.contains("password") ||
                lower.contains("secret") ||
                lower.contains("credential")
            ) {
                return true
            }
            if (lower == "email" || lower.endsWith("_email") || lower.contains("phone")) {
                return true
            }
            if (lower == "lat" || lower == "lng" || lower.contains("address") || lower.contains("location")) {
                return true
            }
            return false
        }

        private fun sanitizeMetadataValue(value: Any, key: String): String {
            val raw = when (value) {
                is Boolean -> if (value) "true" else "false"
                is Number -> value.toString()
                else -> value.toString()
            }
            val sanitized = if (key.lowercase().contains("path")) {
                File(raw).name.ifBlank { "redacted_path" }
            } else {
                raw
            }
            return sanitized.take(maxMetadataValueLength)
        }

        private fun safeIdentifier(value: String): String {
            val normalized = value.trim().ifBlank { "unknown" }
            val allowed = Regex("[^a-zA-Z0-9._:-]")
            return normalized.replace(allowed, "_").take(120)
        }

        private fun loadBreadcrumbs(
            preferences: SharedPreferences,
            json: Json,
        ): List<CaptureTelemetryBreadcrumb> {
            val raw = preferences.getString(breadcrumbsKey, null) ?: return emptyList()
            return runCatching {
                json.decodeFromString<List<CaptureTelemetryBreadcrumb>>(raw).takeLast(maxBreadcrumbs)
            }.getOrDefault(emptyList())
        }

        private fun persistBreadcrumbs(
            preferences: SharedPreferences,
            json: Json,
            breadcrumbs: List<CaptureTelemetryBreadcrumb>,
        ) {
            preferences.edit {
                putString(breadcrumbsKey, json.encodeToString(breadcrumbs.takeLast(maxBreadcrumbs)))
            }
        }

        private fun consumePendingCrashReport(
            preferences: SharedPreferences,
            json: Json,
        ): CapturePendingCrashReport? {
            val raw = preferences.getString(pendingCrashKey, null) ?: return null
            preferences.edit { remove(pendingCrashKey) }
            return runCatching {
                json.decodeFromString<CapturePendingCrashReport>(raw)
            }.getOrNull()
        }

        private fun nowIsoString(): String = Instant.now().toString()

        private fun deviceModel(): String = "${Build.MANUFACTURER} ${Build.MODEL}".trim().ifBlank { "android" }

        private fun osVersion(): String = "Android ${Build.VERSION.RELEASE ?: Build.VERSION.SDK_INT}"
    }
}
