package app.blueprint.capture.ui.screens

import android.app.Activity
import android.content.Context
import android.os.Build
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.blueprint.capture.data.glasses.GlassesCaptureManager
import app.blueprint.capture.data.glasses.GlassesCaptureState
import com.meta.wearable.dat.core.Wearables
import com.meta.wearable.dat.core.types.DeviceIdentifier
import com.meta.wearable.dat.core.types.DeviceType
import com.meta.wearable.dat.core.types.Permission
import com.meta.wearable.dat.core.types.PermissionStatus
import com.meta.wearable.dat.core.types.RegistrationState
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.collect
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

@HiltViewModel
class GlassesViewModel @Inject constructor(
    @ApplicationContext private val context: Context,
    private val captureManager: GlassesCaptureManager,
) : ViewModel() {
<<<<<<< HEAD
=======
    private val config = localConfigProvider.current()
    private val isEmulator = Build.FINGERPRINT.contains("generic", ignoreCase = true) ||
        Build.MODEL.contains("Emulator", ignoreCase = true) ||
        Build.HARDWARE.contains("ranchu", ignoreCase = true)
>>>>>>> c020448d (Implement real Meta glasses DAT flows on iOS and Android)

    private val _state = MutableStateFlow<GlassesConnectionState>(GlassesConnectionState.SetupRequired)
    val state: StateFlow<GlassesConnectionState> = _state.asStateFlow()

    /** Capture sub-state (Idle / Streaming / Paused / Finished / Error) — passed through from manager. */
    val captureState: StateFlow<GlassesCaptureState> = captureManager.captureState

    private var registrationJob: Job? = null
    private var registrationState: RegistrationState = RegistrationState.Unavailable()
    private var datDevices: List<GlassesDevice> = emptyList()
    private var pendingPermissionDevice: GlassesDevice? = null
    private var stickyError: String? = null

<<<<<<< HEAD
    @SuppressLint("MissingPermission")
    fun startScanning() {
        scanJob?.cancel()
        _state.value = GlassesConnectionState.Scanning(emptyList())

        val isEmulator = Build.FINGERPRINT.contains("generic", ignoreCase = true) ||
            Build.MODEL.contains("Emulator", ignoreCase = true) ||
            Build.HARDWARE.contains("ranchu", ignoreCase = true)

        if (isEmulator) {
            // Emulators have no BLE and no real glasses — inject a mock for UI testing.
            scanJob = viewModelScope.launch {
                kotlinx.coroutines.delay(2000)
                injectMock()
            }
            return
=======
    init {
        if (isEmulator && config.allowMockJobsFallback) {
            datDevices = listOf(GlassesDevice(id = "MOCK_001", name = "Ray-Ban Meta (Mock)", isMock = true))
            publishDerivedState(force = true)
        } else {
            observeWearables()
>>>>>>> c020448d (Implement real Meta glasses DAT flows on iOS and Android)
        }
    }

    private fun observeWearables() {
        viewModelScope.launch {
            Wearables.registrationState.collect { state ->
                registrationState = state
                if (state is RegistrationState.Registered) {
                    stickyError = null
                }
                publishDerivedState()
            }
        }
        viewModelScope.launch {
            Wearables.devices.collect { identifiers ->
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
                .onFailure {
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
        if (device.isMock) {
            // Mock path: stay on the fake connected state for emulator/demo use.
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
            permissionResult.onFailure { error, _ ->
                _state.value = GlassesConnectionState.Error(
                    "Camera permission check failed: ${error.description}",
                )
                return@launch
            }

            when (permissionResult.getOrNull()) {
                PermissionStatus.Granted -> connectAuthorized(device)
                PermissionStatus.Denied, null -> {
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
        _state.value = GlassesConnectionState.Connecting(device)
        viewModelScope.launch {
            captureManager.connect(device.mwdatIdentifier)
                .onSuccess { _state.value = GlassesConnectionState.Connected(device.name) }
                .onFailure {
                    stickyError = it.message ?: "Connection failed"
                    publishDerivedState(force = true)
                }
        }
    }

    fun startCapture() {
        val dir = context.filesDir
            .resolve("glasses_captures/${System.currentTimeMillis()}")
            .also { it.mkdirs() }
        viewModelScope.launch { captureManager.startCapture(dir) }
    }

    fun pauseCapture() = captureManager.pauseCapture()

    fun resumeCapture() = captureManager.resumeCapture()

    fun stopCapture() {
        viewModelScope.launch { captureManager.stopCapture() }
    }

    fun disconnect() {
        captureManager.disconnect()
        pendingPermissionDevice = null
        stickyError = null
        publishDerivedState(force = true)
    }

    override fun onCleared() {
        super.onCleared()
        registrationJob?.cancel()
        captureManager.disconnect()
    }
<<<<<<< HEAD
=======

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

>>>>>>> c020448d (Implement real Meta glasses DAT flows on iOS and Android)
}
