package app.blueprint.capture.ui.screens

import android.annotation.SuppressLint
import android.bluetooth.BluetoothManager
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.Build
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.blueprint.capture.data.glasses.GlassesCaptureManager
import app.blueprint.capture.data.glasses.GlassesCaptureState
import com.meta.wearable.dat.core.DeviceIdentifier
import com.meta.wearable.dat.core.DeviceType
import com.meta.wearable.dat.core.Wearables
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.File
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
    object Idle : GlassesConnectionState()
    data class Scanning(val devices: List<GlassesDevice> = emptyList()) : GlassesConnectionState()
    data class Connecting(val device: GlassesDevice) : GlassesConnectionState()
    data class Connected(val deviceName: String) : GlassesConnectionState()
    data class Error(val message: String) : GlassesConnectionState()
}

@HiltViewModel
class GlassesViewModel @Inject constructor(
    @ApplicationContext private val context: Context,
    private val captureManager: GlassesCaptureManager,
) : ViewModel() {

    private val _state = MutableStateFlow<GlassesConnectionState>(GlassesConnectionState.Idle)
    val state: StateFlow<GlassesConnectionState> = _state.asStateFlow()

    /** Capture sub-state (Idle / Streaming / Paused / Finished / Error) — passed through from manager. */
    val captureState: StateFlow<GlassesCaptureState> = captureManager.captureState

    private var scanJob: Job? = null
    private var bleScanner: android.bluetooth.le.BluetoothLeScanner? = null
    private var scanCallback: ScanCallback? = null

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
        }

        scanJob = viewModelScope.launch {
            // Observe MWDAT registered devices from the SDK.
            Wearables.devices.collect { identifiers ->
                val mwdatDevices = identifiers.map { id ->
                    val meta = Wearables.devicesMetadata[id]?.value
                    val name = when (meta?.deviceType) {
                        DeviceType.RAY_BAN_DISPLAY -> "Ray-Ban Meta (Display)"
                        DeviceType.DISPLAYLESS_GLASSES -> "Ray-Ban Meta"
                        else -> "Meta Glasses"
                    }
                    GlassesDevice(id = id.toString(), name = name, mwdatIdentifier = id)
                }
                // Merge with any devices found via raw BLE scan (unregistered nearby glasses).
                val current = _state.value as? GlassesConnectionState.Scanning ?: return@collect
                val bleOnly = current.devices.filter { it.mwdatIdentifier == null }
                _state.value = GlassesConnectionState.Scanning(mwdatDevices + bleOnly)
            }
        }

        // Parallel raw BLE scan to surface nearby glasses that haven't been registered yet.
        startBleScan()
    }

    @SuppressLint("MissingPermission")
    private fun startBleScan() {
        val adapter = context.getSystemService(BluetoothManager::class.java)
            ?.adapter?.takeIf { it.isEnabled } ?: return

        val cb = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                val name = result.device?.name?.takeIf { it.isNotBlank() } ?: return
                val isGlasses = name.contains("Ray-Ban", ignoreCase = true) ||
                    name.contains("Meta", ignoreCase = true) ||
                    name.contains("Glass", ignoreCase = true) ||
                    name.contains("RBM", ignoreCase = true)
                if (!isGlasses) return

                val device = GlassesDevice(id = result.device.address, name = name)
                val current = _state.value as? GlassesConnectionState.Scanning ?: return
                if (current.devices.none { it.id == device.id }) {
                    _state.value = GlassesConnectionState.Scanning(current.devices + device)
                }
            }
        }
        val settings = ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build()
        scanCallback = cb
        bleScanner = adapter.bluetoothLeScanner
        bleScanner?.startScan(null, settings, cb)
    }

    private fun injectMock() {
        val current = _state.value as? GlassesConnectionState.Scanning ?: return
        if (current.devices.none { it.isMock }) {
            _state.value = GlassesConnectionState.Scanning(
                current.devices + GlassesDevice(id = "MOCK_001", name = "Ray-Ban Meta (Mock)", isMock = true),
            )
        }
    }

    @SuppressLint("MissingPermission")
    fun stopScanning() {
        scanJob?.cancel()
        scanJob = null
        scanCallback?.let { bleScanner?.stopScan(it) }
        bleScanner = null
        scanCallback = null
        _state.value = GlassesConnectionState.Idle
    }

    fun connect(device: GlassesDevice) {
        stopScanning()
        if (device.isMock) {
            // Mock path: stay on the fake connected state for emulator/demo use.
            _state.value = GlassesConnectionState.Connected(device.name)
            return
        }
        _state.value = GlassesConnectionState.Connecting(device)
        viewModelScope.launch {
            captureManager.connect(device.mwdatIdentifier)
                .onSuccess { _state.value = GlassesConnectionState.Connected(device.name) }
                .onFailure { _state.value = GlassesConnectionState.Error(it.message ?: "Connection failed") }
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
        stopScanning()
        _state.value = GlassesConnectionState.Idle
    }

    override fun onCleared() {
        super.onCleared()
        @SuppressLint("MissingPermission")
        val stopBle = { scanCallback?.let { bleScanner?.stopScan(it) } }
        stopBle()
        captureManager.disconnect()
    }
}
