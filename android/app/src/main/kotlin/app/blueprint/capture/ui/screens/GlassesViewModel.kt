package app.blueprint.capture.ui.screens

import android.app.Activity
import android.content.Context
import android.media.MediaMetadataRetriever
import android.os.Build
import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.blueprint.capture.BuildConfig
import app.blueprint.capture.data.auth.AuthRepository
import app.blueprint.capture.data.capture.AndroidCaptureBundleBuilder
import app.blueprint.capture.data.capture.AndroidCaptureBundleRequest
import app.blueprint.capture.data.capture.AndroidCaptureSource
import app.blueprint.capture.data.capture.CaptureIntakeMetadata
import app.blueprint.capture.data.capture.CaptureIntakeSource
import app.blueprint.capture.data.capture.CaptureModeMetadata
import app.blueprint.capture.data.capture.CaptureScaffoldingPacket
import app.blueprint.capture.data.capture.CaptureTopologyMetadata
import app.blueprint.capture.data.capture.CaptureUploadRepository
import app.blueprint.capture.data.capture.QualificationIntakePacket
import app.blueprint.capture.data.capture.SiteIdentity
import app.blueprint.capture.data.glasses.GlassesCaptureManager
import app.blueprint.capture.data.glasses.GlassesCaptureArtifacts
import app.blueprint.capture.data.glasses.GlassesCaptureState
import app.blueprint.capture.data.model.CaptureLaunch
import app.blueprint.capture.data.config.LocalConfigProvider
import com.meta.wearable.dat.core.Wearables
import com.meta.wearable.dat.core.types.DeviceIdentifier
import com.meta.wearable.dat.core.types.DeviceType
import com.meta.wearable.dat.core.types.Permission
import com.meta.wearable.dat.core.types.PermissionStatus
import com.meta.wearable.dat.core.types.RegistrationState
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.File
import java.util.Locale
import java.util.UUID
import javax.inject.Inject
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class GlassesDevice(
    val id: String,
    val name: String,
    val isMock: Boolean = false,
    val mwdatIdentifier: DeviceIdentifier? = null,
)

sealed class GlassesConnectionState {
    object SetupRequired : GlassesConnectionState()
    object Registering : GlassesConnectionState()
    data class Available(
        val message: String,
        val devices: List<GlassesDevice> = emptyList(),
    ) : GlassesConnectionState()
    data class PermissionRequired(
        val device: GlassesDevice,
        val message: String,
    ) : GlassesConnectionState()
    data class Connecting(val device: GlassesDevice) : GlassesConnectionState()
    data class Connected(val deviceName: String) : GlassesConnectionState()
    data class Error(val message: String) : GlassesConnectionState()
}

data class GlassesCaptureUiState(
    val captureLaunch: CaptureLaunch? = null,
    val isFinalizing: Boolean = false,
    val statusMessage: String? = null,
    val queuedUploadId: String? = null,
    val errorMessage: String? = null,
)

@HiltViewModel
class GlassesViewModel @Inject constructor(
    @ApplicationContext private val context: Context,
    private val authRepository: AuthRepository,
    private val bundleBuilder: AndroidCaptureBundleBuilder,
    private val uploadRepository: CaptureUploadRepository,
    private val captureManager: GlassesCaptureManager,
    localConfigProvider: LocalConfigProvider,
) : ViewModel() {
    private companion object {
        const val TAG = "BlueprintGlasses"
        const val MWDAT_DISABLED_MESSAGE =
            "Meta DAT private SDK is disabled in this build. Add GitHub Packages credentials and set MWDAT_ENABLE_PRIVATE_SDK=true to verify Meta glasses."
    }

    private val config = localConfigProvider.current()
    private val isEmulator = Build.FINGERPRINT.contains("generic", ignoreCase = true) ||
        Build.MODEL.contains("Emulator", ignoreCase = true) ||
        Build.HARDWARE.contains("ranchu", ignoreCase = true)

    private val _state = MutableStateFlow<GlassesConnectionState>(GlassesConnectionState.SetupRequired)
    val state: StateFlow<GlassesConnectionState> = _state.asStateFlow()

    /** Capture sub-state (Idle / Streaming / Paused / Finished / Error) — passed through from manager. */
    val captureState: StateFlow<GlassesCaptureState> = captureManager.captureState
    private val _captureUiState = MutableStateFlow(GlassesCaptureUiState())
    val captureUiState: StateFlow<GlassesCaptureUiState> = _captureUiState.asStateFlow()

    private var registrationJob: Job? = null
    private var registrationState: RegistrationState = RegistrationState.Unavailable()
    private var datDevices: List<GlassesDevice> = emptyList()
    private var pendingPermissionDevice: GlassesDevice? = null
    private var stickyError: String? = null

    init {
        if (isEmulator && config.allowMockJobsFallback) {
            datDevices = listOf(GlassesDevice(id = "MOCK_001", name = "Ray-Ban Meta (Mock)", isMock = true))
            publishDerivedState(force = true)
        } else if (!BuildConfig.MWDAT_PRIVATE_SDK_ENABLED) {
            stickyError = MWDAT_DISABLED_MESSAGE
            publishDerivedState(force = true)
        } else {
            observeWearables()
        }
    }

    private fun observeWearables() {
        viewModelScope.launch {
            Wearables.registrationState.collect { state ->
                registrationState = state
                Log.d(TAG, "registrationState=$state")
                if (state is RegistrationState.Registered) {
                    stickyError = null
                }
                publishDerivedState()
            }
        }
        viewModelScope.launch {
            Wearables.devices.collect { identifiers ->
                Log.d(TAG, "devices.count=${identifiers.size}")
                datDevices = identifiers.map { id ->
                    val meta = Wearables.devicesMetadata[id]?.value
                    val name = when (meta?.deviceType) {
                        DeviceType.META_RAYBAN_DISPLAY -> "Ray-Ban Meta (Display)"
                        DeviceType.RAYBAN_META -> "Ray-Ban Meta"
                        DeviceType.OAKLEY_META_HSTN -> "Oakley Meta HSTN"
                        DeviceType.OAKLEY_META_VANGUARD -> "Oakley Meta Vanguard"
                        else -> meta?.name ?: "Meta Glasses"
                    }
                    GlassesDevice(id = id.toString(), name = name, mwdatIdentifier = id)
                }
                publishDerivedState()
            }
        }
    }

    fun startScanning() {
        publishDerivedState(force = true)
    }

    fun beginMetaSetup(activity: Activity?) {
        stickyError = null
        pendingPermissionDevice = null
        Log.d(TAG, "beginMetaSetup isEmulator=$isEmulator activityPresent=${activity != null}")
        if (!BuildConfig.MWDAT_PRIVATE_SDK_ENABLED) {
            stickyError = MWDAT_DISABLED_MESSAGE
            publishDerivedState(force = true)
            return
        }
        if (isEmulator) {
            publishDerivedState(force = true)
            return
        }
        if (activity == null) {
            _state.value = GlassesConnectionState.Error("Unable to open Meta setup from this screen.")
            return
        }
        if (registrationState is RegistrationState.Registered) {
            publishDerivedState(force = true)
            return
        }
        _state.value = GlassesConnectionState.Registering
        registrationJob?.cancel()
        registrationJob = viewModelScope.launch {
            runCatching { Wearables.startRegistration(activity) }
                .onSuccess { Log.d(TAG, "Wearables.startRegistration launched") }
                .onFailure {
                    Log.w(TAG, "Wearables.startRegistration failed", it)
                    stickyError = it.message ?: "Meta registration could not be started."
                    publishDerivedState(force = true)
                }
        }
    }

    fun stopScanning() {
        stickyError = null
        pendingPermissionDevice = null
        publishDerivedState(force = true)
    }

    fun connect(device: GlassesDevice) {
        Log.d(TAG, "connect requested device=${device.name} hasIdentifier=${device.mwdatIdentifier != null} isMock=${device.isMock}")
        if (device.isMock) {
            if (!config.allowMockJobsFallback) {
                _state.value = GlassesConnectionState.Error("Mock glasses are disabled in this alpha build.")
                return
            }
            // Mock path is dev-only and explicitly config-gated.
            _state.value = GlassesConnectionState.Connected(device.name)
            return
        }
        viewModelScope.launch {
            if (device.mwdatIdentifier == null) {
                _state.value = GlassesConnectionState.Error(
                    "This device was not provided by Meta DAT. Finish Meta AI setup before connecting.",
                )
                return@launch
            }

            val permissionResult = Wearables.checkPermissionStatus(Permission.CAMERA)
            var permissionError: String? = null
            permissionResult.onFailure { error, _ ->
                permissionError = error.description
            }
            if (permissionError != null && permissionResult.getOrNull() == null) {
                Log.w(TAG, "checkPermissionStatus failed: $permissionError")
                _state.value = GlassesConnectionState.Error(
                    "Camera permission check failed: $permissionError",
                )
                return@launch
            }

            when (permissionResult.getOrNull()) {
                PermissionStatus.Granted -> {
                    Log.d(TAG, "cameraPermission=granted for ${device.name}")
                    connectAuthorized(device)
                }
                PermissionStatus.Denied, null -> {
                    Log.d(TAG, "cameraPermission=denied_or_unknown for ${device.name}")
                    pendingPermissionDevice = device
                    _state.value = GlassesConnectionState.PermissionRequired(
                        device = device,
                        message = "Meta AI must grant camera access before ${device.name} can stream.",
                    )
                }
            }
        }
    }

    fun onWearablesPermissionResolved(status: PermissionStatus) {
        val device = pendingPermissionDevice ?: return
        pendingPermissionDevice = null
        Log.d(TAG, "wearablesPermissionResolved status=$status device=${device.name}")
        when (status) {
            PermissionStatus.Granted -> connectAuthorized(device)
            PermissionStatus.Denied -> {
                stickyError = "Camera permission wasn't granted in Meta AI."
                publishDerivedState(force = true)
            }
        }
    }

    private fun connectAuthorized(device: GlassesDevice) {
        stickyError = null
        Log.d(TAG, "connectAuthorized device=${device.name}")
        _state.value = GlassesConnectionState.Connecting(device)
        viewModelScope.launch {
            captureManager.connect(device.mwdatIdentifier)
                .onSuccess {
                    Log.d(TAG, "captureManager.connect success device=${device.name}")
                    _state.value = GlassesConnectionState.Connected(device.name)
                }
                .onFailure {
                    Log.w(TAG, "captureManager.connect failed device=${device.name}", it)
                    stickyError = it.message ?: "Connection failed"
                    publishDerivedState(force = true)
                }
        }
    }

    fun startCapture() {
        val activeLaunch = _captureUiState.value.captureLaunch
        if (activeLaunch == null) {
            _captureUiState.value = GlassesCaptureUiState(
                errorMessage = "Choose a live capture target before starting glasses capture.",
            )
            return
        }
        val dir = context.filesDir
            .resolve("glasses_captures/${System.currentTimeMillis()}")
            .also { it.mkdirs() }
        _captureUiState.value = GlassesCaptureUiState(
            captureLaunch = activeLaunch,
            statusMessage = "Recording ${activeLaunch.label}",
        )
        viewModelScope.launch { captureManager.startCapture(dir) }
    }

    fun pauseCapture() = captureManager.pauseCapture()

    fun resumeCapture() = captureManager.resumeCapture()

    fun stopCapture() {
        val captureLaunch = _captureUiState.value.captureLaunch
        if (captureLaunch == null) {
            _captureUiState.value = GlassesCaptureUiState(
                errorMessage = "Choose a live capture target before finalizing glasses capture.",
            )
            return
        }
        viewModelScope.launch {
            _captureUiState.value = GlassesCaptureUiState(
                captureLaunch = captureLaunch,
                isFinalizing = true,
                statusMessage = "Finalizing raw glasses capture and queueing upload…",
            )
            runCatching {
                authRepository.ensureAnonymousSession()
                val artifacts = captureManager.stopCapture()
                finalizeCaptureUpload(captureLaunch, artifacts)
            }.onSuccess { uploadId ->
                _captureUiState.value = GlassesCaptureUiState(
                    captureLaunch = captureLaunch,
                    queuedUploadId = uploadId,
                    statusMessage = "Capture bundled and queued for upload.",
                )
            }.onFailure { error ->
                _captureUiState.value = GlassesCaptureUiState(
                    captureLaunch = captureLaunch,
                    errorMessage = error.message ?: "Glasses capture could not be finalized.",
                )
            }
        }
    }

    fun disconnect() {
        Log.d(TAG, "disconnect requested")
        captureManager.disconnect()
        pendingPermissionDevice = null
        stickyError = null
        publishDerivedState(force = true)
    }

    fun setCaptureContext(captureLaunch: CaptureLaunch?) {
        if (_captureUiState.value.captureLaunch == captureLaunch) return
        _captureUiState.value = GlassesCaptureUiState(captureLaunch = captureLaunch)
    }

    override fun onCleared() {
        super.onCleared()
        registrationJob?.cancel()
        captureManager.disconnect()
    }

    private fun publishDerivedState(force: Boolean = false) {
        if (!force) {
            when (_state.value) {
                is GlassesConnectionState.Connecting,
                is GlassesConnectionState.Connected,
                is GlassesConnectionState.PermissionRequired,
                -> return
                else -> Unit
            }
        }

        stickyError?.let {
            _state.value = GlassesConnectionState.Error(it)
            return
        }

        if (isEmulator && config.allowMockJobsFallback) {
            _state.value = GlassesConnectionState.Available(
                message = "Debug build: mock Meta glasses are ready.",
                devices = datDevices,
            )
            return
        }

        _state.value = when (registrationState) {
            is RegistrationState.Registering,
            is RegistrationState.Unregistering,
            -> GlassesConnectionState.Registering

            is RegistrationState.Registered -> GlassesConnectionState.Available(
                message = if (datDevices.isEmpty()) {
                    "No active Meta glasses found. Open Meta AI, confirm your glasses are connected, powered on, nearby, and approved for this app."
                } else {
                    "Choose your Meta glasses to continue."
                },
                devices = datDevices,
            )

            else -> GlassesConnectionState.SetupRequired
        }
        Log.d(TAG, "uiState=${_state.value}")
    }

    private fun finalizeCaptureUpload(
        captureLaunch: CaptureLaunch,
        artifacts: GlassesCaptureArtifacts,
    ): String {
        require(artifacts.videoFile.exists() && artifacts.videoFile.length() > 0L) {
            "Glasses capture finished without a walkthrough video. Nothing was queued."
        }

        val creatorId = authRepository.currentUserId()
            ?: error("Unable to resolve a signed or guest capture session for upload.")
        val captureId = UUID.randomUUID().toString()
        val videoMetadata = readVideoMetadata(
            file = artifacts.videoFile,
            frameCount = artifacts.frameCount,
            durationMs = artifacts.durationMs,
        )
        val request = captureLaunch.toGlassesBundleRequest(
            creatorId = creatorId,
            captureId = captureId,
            captureStartEpochMs = artifacts.videoFile.lastModified().takeIf { it > 0L }
                ?: System.currentTimeMillis(),
            captureDurationMs = artifacts.durationMs,
            width = videoMetadata.width,
            height = videoMetadata.height,
            frameRate = videoMetadata.frameRate,
        )
        val outputRoot = context.filesDir.resolve("capture_bundles").also(File::mkdirs)
        val bundle = bundleBuilder.writeBundle(
            outputRoot = outputRoot,
            request = request,
            walkthroughSource = artifacts.videoFile,
            glassesEvidenceDirectory = artifacts.glassesEvidenceDirectory,
            companionPhoneDirectory = artifacts.companionPhoneDirectory,
        )
        return uploadRepository.enqueueBundleUpload(
            label = captureLaunch.label,
            bundleRoot = bundle.captureRoot,
            request = request,
        )
    }

    private fun readVideoMetadata(
        file: File,
        frameCount: Int,
        durationMs: Long,
    ): GlassesVideoMetadata {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(file.absolutePath)
            val width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                ?.toIntOrNull() ?: 1920
            val height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                ?.toIntOrNull() ?: 1080
            val frameRate = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_CAPTURE_FRAMERATE)
                ?.toDoubleOrNull()
                ?: if (durationMs > 0L && frameCount > 0) {
                    frameCount * 1000.0 / durationMs.toDouble()
                } else {
                    30.0
                }
            GlassesVideoMetadata(width = width, height = height, frameRate = frameRate)
        } finally {
            retriever.release()
        }
    }

}

private data class GlassesVideoMetadata(
    val width: Int,
    val height: Int,
    val frameRate: Double,
)

private fun CaptureLaunch.toGlassesBundleRequest(
    creatorId: String,
    captureId: String,
    captureStartEpochMs: Long,
    captureDurationMs: Long,
    width: Int,
    height: Int,
    frameRate: Double,
): AndroidCaptureBundleRequest {
    val sceneId = jobId ?: targetId ?: glassesFallbackSceneId(label)
    val siteId = siteSubmissionId ?: targetId ?: jobId ?: sceneId
    val workflowStepsValue = workflowSteps.ifEmpty {
        listOf(
            "Record the full walkthrough path hands-free with smooth pace and continuous coverage.",
            "Hold key thresholds and transitions briefly so downstream review can anchor the route.",
            "Avoid private people, screens, paperwork, and restricted zones throughout the capture.",
        )
    }
    return AndroidCaptureBundleRequest(
        sceneId = sceneId,
        captureId = captureId,
        creatorId = creatorId,
        jobId = jobId ?: targetId,
        siteSubmissionId = siteSubmissionId,
        deviceModel = "${Build.MANUFACTURER} ${Build.MODEL}".trim(),
        osVersion = "Android ${Build.VERSION.RELEASE ?: Build.VERSION.SDK_INT}",
        fpsSource = frameRate,
        width = width,
        height = height,
        captureStartEpochMs = captureStartEpochMs,
        captureDurationMs = captureDurationMs,
        captureSource = AndroidCaptureSource.MetaGlasses,
        captureContextHint = label.ifBlank { null },
        workflowName = workflowName,
        taskSteps = workflowStepsValue,
        zone = zone,
        owner = owner,
        operatorNotes = listOfNotNull(
            "capture_origin:meta_glasses",
            addressText?.takeIf(String::isNotBlank)?.let { "address:$it" },
        ),
        intakePacket = QualificationIntakePacket(
            workflowName = workflowName,
            taskSteps = workflowStepsValue,
            zone = zone,
            owner = owner,
        ),
        intakeMetadata = CaptureIntakeMetadata(source = CaptureIntakeSource.HumanManual),
        quotedPayoutCents = quotedPayoutCents,
        rightsProfile = rightsProfile,
        requestedOutputs = requestedOutputs.ifEmpty { listOf("qualification", "review_intake") },
        siteIdentity = SiteIdentity(
            siteId = siteId,
            siteIdSource = if (!siteSubmissionId.isNullOrBlank()) {
                "site_submission"
            } else if (!targetId.isNullOrBlank()) {
                "buyer_request"
            } else {
                "open_capture"
            },
            siteName = label.takeIf(String::isNotBlank),
            addressFull = addressText?.takeIf(String::isNotBlank),
        ),
        captureTopology = CaptureTopologyMetadata(
            captureSessionId = captureId,
            routeId = siteId,
            passId = captureId,
            passIndex = 1,
            intendedPassRole = "primary",
        ),
        captureMode = CaptureModeMetadata(
            requestedMode = "site_world_candidate",
            resolvedMode = "site_world_candidate",
        ),
        scaffoldingPacket = CaptureScaffoldingPacket(
            scaffoldingUsed = listOf("site_world_candidate", "glasses_hands_free_capture"),
            coveragePlan = workflowStepsValue,
        ),
    )
}

private fun glassesFallbackSceneId(label: String): String =
    label.lowercase(Locale.US)
        .replace("[^a-z0-9]+".toRegex(), "-")
        .trim('-')
        .ifBlank { "open-capture" }
