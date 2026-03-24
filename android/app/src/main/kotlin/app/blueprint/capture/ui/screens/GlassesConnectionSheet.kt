package app.blueprint.capture.ui.screens

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
<<<<<<< HEAD
import app.blueprint.capture.data.glasses.GlassesCaptureState
=======
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat
>>>>>>> c020448d (Implement real Meta glasses DAT flows on iOS and Android)
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import app.blueprint.capture.data.glasses.GlassesCaptureState
import app.blueprint.capture.data.model.CaptureLaunch
import app.blueprint.capture.ui.theme.BlueprintAccent
import app.blueprint.capture.ui.theme.BlueprintBorder
import app.blueprint.capture.ui.theme.BlueprintBlack
import app.blueprint.capture.ui.theme.BlueprintSuccess
import app.blueprint.capture.ui.theme.BlueprintSurfaceCard
import app.blueprint.capture.ui.theme.BlueprintSurfaceInset
import app.blueprint.capture.ui.theme.BlueprintTeal
import app.blueprint.capture.ui.theme.BlueprintTealSurface
import app.blueprint.capture.ui.theme.BlueprintTextMuted
import app.blueprint.capture.ui.theme.BlueprintTextPrimary
import androidx.compose.foundation.Canvas
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.drawscope.DrawScope
import com.meta.wearable.dat.core.Wearables
import com.meta.wearable.dat.core.types.PermissionStatus

@Composable
fun GlassesConnectionSheet(
    viewModel: GlassesViewModel = hiltViewModel(),
<<<<<<< HEAD
    onScanRequest: () -> Unit = viewModel::startScanning,
=======
    captureLaunch: CaptureLaunch? = null,
>>>>>>> c020448d (Implement real Meta glasses DAT flows on iOS and Android)
) {
    val context = LocalContext.current
    val activity = context.findActivity()
    val state by viewModel.state.collectAsState()
    val captureState by viewModel.captureState.collectAsState()
<<<<<<< HEAD
=======
    val captureUiState by viewModel.captureUiState.collectAsState()

    val blePermissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestMultiplePermissions(),
    ) {
        viewModel.beginMetaSetup(activity)
    }
    val wearablesPermissionLauncher = rememberLauncherForActivityResult(
        contract = Wearables.RequestPermissionContract(),
    ) { result ->
        viewModel.onWearablesPermissionResolved(result.getOrDefault(PermissionStatus.Denied))
    }

    fun requestMetaSetup() {
        val required = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.BLUETOOTH_SCAN)
        } else {
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }
        val allGranted = required.all {
            ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED
        }
        if (allGranted) {
            viewModel.beginMetaSetup(activity)
        } else {
            blePermissionLauncher.launch(required)
        }
    }

    LaunchedEffect(captureLaunch) {
        viewModel.setCaptureContext(captureLaunch)
    }
    DisposableEffect(Unit) {
        onDispose { viewModel.setCaptureContext(null) }
    }
>>>>>>> c020448d (Implement real Meta glasses DAT flows on iOS and Android)

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(start = 24.dp, end = 24.dp, top = 4.dp, bottom = 40.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(modifier = Modifier.height(28.dp))

        // Glasses icon hero
        GlassesIcon(
            modifier = Modifier.size(86.dp),
            tint = BlueprintTeal,
        )

        Spacer(modifier = Modifier.height(20.dp))

        Text(
            text = "Smart Glasses",
            color = BlueprintTextPrimary,
            fontSize = 26.sp,
            fontWeight = FontWeight.Bold,
        )

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = "Connect once. Then one-tap scans.",
            color = BlueprintTextMuted,
            fontSize = 16.sp,
        )

        Spacer(modifier = Modifier.height(36.dp))

        // State-driven action area
        when (val s = state) {
            is GlassesConnectionState.SetupRequired -> {
                SetupRequiredCard(onClick = ::requestMetaSetup)
            }

            is GlassesConnectionState.Registering -> {
                RegisteringCard(onCancel = viewModel::stopScanning)
            }

            is GlassesConnectionState.Available -> {
                AvailabilityCard(
                    message = s.message,
                    hasDevices = s.devices.isNotEmpty(),
                    onPrimaryClick = ::requestMetaSetup,
                )
                if (s.devices.isNotEmpty()) {
                    Spacer(modifier = Modifier.height(12.dp))
                    s.devices.forEach { device ->
                        DeviceRow(device = device, onClick = { viewModel.connect(device) })
                        Spacer(modifier = Modifier.height(8.dp))
                    }
                }
            }

            is GlassesConnectionState.PermissionRequired -> {
                PermissionRequiredCard(
                    deviceName = s.device.name,
                    message = s.message,
                    onGrant = { wearablesPermissionLauncher.launch(com.meta.wearable.dat.core.types.Permission.CAMERA) },
                    onCancel = viewModel::stopScanning,
                )
            }

            is GlassesConnectionState.Connecting -> {
                ConnectingCard(deviceName = s.device.name)
            }

            is GlassesConnectionState.Connected -> {
                ConnectedCard(
                    deviceName = s.deviceName,
                    captureState = captureState,
                    onStartCapture = viewModel::startCapture,
                    onStopCapture = viewModel::stopCapture,
                    onDisconnect = viewModel::disconnect,
                )
            }

            is GlassesConnectionState.Error -> {
                ErrorCard(message = s.message, onRetry = ::requestMetaSetup)
            }
        }
    }
}

// ── Glasses icon ─────────────────────────────────────────────────────────────

@Composable
fun GlassesIcon(
    modifier: Modifier = Modifier,
    tint: Color = BlueprintTeal,
) {
    Canvas(modifier = modifier) {
        drawGlassesIcon(tint)
    }
}

private fun DrawScope.drawGlassesIcon(tint: Color) {
    val w = size.width
    val h = size.height
    val stroke = Stroke(width = w * 0.07f, cap = StrokeCap.Round)
    val r = w * 0.26f
    val cy = h * 0.52f
    val lx = w * 0.28f
    val rx = w * 0.72f

    // Left lens
    drawCircle(color = tint, radius = r, center = Offset(lx, cy), style = stroke)
    // Right lens
    drawCircle(color = tint, radius = r, center = Offset(rx, cy), style = stroke)
    // Bridge
    drawLine(tint, Offset(lx + r, cy), Offset(rx - r, cy), strokeWidth = w * 0.07f, cap = StrokeCap.Round)
    // Left arm
    drawLine(tint, Offset(lx - r, cy), Offset(0f, cy - h * 0.08f), strokeWidth = w * 0.07f, cap = StrokeCap.Round)
    // Right arm
    drawLine(tint, Offset(rx + r, cy), Offset(w, cy - h * 0.08f), strokeWidth = w * 0.07f, cap = StrokeCap.Round)
}

// ── Action components ─────────────────────────────────────────────────────────

@Composable
private fun SetupRequiredCard(onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(BlueprintAccent)
            .clickable(onClick = onClick)
            .padding(vertical = 18.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = "Connect with Meta AI",
            color = BlueprintBlack,
            fontSize = 17.sp,
            fontWeight = FontWeight.SemiBold,
        )
    }
}

@Composable
private fun RegisteringCard(onCancel: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(BlueprintSurfaceCard, RoundedCornerShape(16.dp))
            .border(1.dp, BlueprintBorder, RoundedCornerShape(16.dp))
            .padding(horizontal = 18.dp, vertical = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        CircularProgressIndicator(
            modifier = Modifier.size(22.dp),
            color = BlueprintTeal,
            strokeWidth = 2.5.dp,
            trackColor = BlueprintSurfaceInset,
        )
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                text = "Finishing Meta setup...",
                color = BlueprintTextPrimary,
                fontSize = 16.sp,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                text = "Approve Blueprint in Meta AI, then come back here.",
                color = BlueprintTextMuted,
                fontSize = 13.sp,
            )
        }
        Text(
            text = "Cancel",
            color = BlueprintTextMuted,
            fontSize = 15.sp,
            modifier = Modifier.clickable(onClick = onCancel),
        )
    }
}

@Composable
private fun AvailabilityCard(
    message: String,
    hasDevices: Boolean,
    onPrimaryClick: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(BlueprintSurfaceCard, RoundedCornerShape(16.dp))
            .border(1.dp, BlueprintBorder, RoundedCornerShape(16.dp))
            .padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            text = if (hasDevices) "Meta glasses available" else "Waiting for your glasses",
            color = BlueprintTextPrimary,
            fontSize = 16.sp,
            fontWeight = FontWeight.SemiBold,
        )
        Text(
            text = message,
            color = BlueprintTextMuted,
            fontSize = 13.sp,
        )
        if (!hasDevices) {
            CaptureActionButton(
                label = "Open Meta Setup Again",
                color = BlueprintTeal,
                onClick = onPrimaryClick,
            )
        }
    }
}

@Composable
private fun PermissionRequiredCard(
    deviceName: String,
    message: String,
    onGrant: () -> Unit,
    onCancel: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(BlueprintSurfaceCard, RoundedCornerShape(16.dp))
            .border(1.dp, BlueprintBorder, RoundedCornerShape(16.dp))
            .padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            text = "Camera permission needed",
            color = BlueprintTextPrimary,
            fontSize = 16.sp,
            fontWeight = FontWeight.SemiBold,
        )
        Text(
            text = "$message\n\nDevice: $deviceName",
            color = BlueprintTextMuted,
            fontSize = 13.sp,
        )
        CaptureActionButton(
            label = "Grant in Meta AI",
            color = BlueprintTeal,
            onClick = onGrant,
        )
        Text(
            text = "Cancel",
            color = BlueprintTextMuted,
            fontSize = 14.sp,
            modifier = Modifier.clickable(onClick = onCancel),
        )
    }
}

@Composable
private fun DeviceRow(
    device: GlassesDevice,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(BlueprintSurfaceCard, RoundedCornerShape(16.dp))
            .border(1.dp, BlueprintBorder, RoundedCornerShape(16.dp))
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Box(
            modifier = Modifier
                .size(44.dp)
                .clip(CircleShape)
                .background(BlueprintTealSurface),
            contentAlignment = Alignment.Center,
        ) {
            GlassesIcon(modifier = Modifier.size(26.dp), tint = BlueprintTeal)
        }
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                text = device.name,
                color = BlueprintTextPrimary,
                fontSize = 16.sp,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                text = if (device.isMock) "Debug mock device" else "Tap to connect",
                color = BlueprintTextMuted,
                fontSize = 13.sp,
            )
        }
        Icon(
            imageVector = Icons.AutoMirrored.Rounded.KeyboardArrowRight,
            contentDescription = null,
            tint = BlueprintTextMuted.copy(alpha = 0.4f),
            modifier = Modifier.size(22.dp),
        )
    }
}

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}

@Composable
private fun ConnectingCard(deviceName: String) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(BlueprintSurfaceCard, RoundedCornerShape(16.dp))
            .border(1.dp, BlueprintBorder, RoundedCornerShape(16.dp))
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        CircularProgressIndicator(
            modifier = Modifier.size(32.dp),
            color = BlueprintTeal,
            strokeWidth = 3.dp,
            trackColor = BlueprintSurfaceInset,
        )
        Text(
            text = "Connecting to $deviceName",
            color = BlueprintTextPrimary,
            fontSize = 16.sp,
            fontWeight = FontWeight.SemiBold,
        )
        Text(
            text = "Keep your glasses nearby",
            color = BlueprintTextMuted,
            fontSize = 13.sp,
        )
    }
}

@Composable
private fun ConnectedCard(
    deviceName: String,
    captureState: GlassesCaptureState,
    onStartCapture: () -> Unit,
    onStopCapture: () -> Unit,
    onDisconnect: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(BlueprintSuccess.copy(alpha = 0.12f), RoundedCornerShape(16.dp))
            .border(1.dp, BlueprintSuccess.copy(alpha = 0.25f), RoundedCornerShape(16.dp))
            .padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // Device header row
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Box(
                modifier = Modifier
                    .size(10.dp)
                    .clip(CircleShape)
                    .background(BlueprintSuccess),
            )
            Text(
                text = deviceName,
                color = BlueprintTextPrimary,
                fontSize = 16.sp,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.weight(1f),
            )
            Text(
                text = "Connected",
                color = BlueprintSuccess,
                fontSize = 13.sp,
                fontWeight = FontWeight.Medium,
            )
        }

        // Capture controls — driven by captureState
        when (captureState) {
            is GlassesCaptureState.Idle -> {
                CaptureActionButton(
                    label = "Start Capture",
                    color = BlueprintTeal,
                    onClick = onStartCapture,
                )
            }

            is GlassesCaptureState.Preparing -> {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(18.dp),
                        color = BlueprintTeal,
                        strokeWidth = 2.dp,
                        trackColor = BlueprintSurfaceInset,
                    )
                    Text(text = "Connecting...", color = BlueprintTextMuted, fontSize = 14.sp)
                }
            }

            is GlassesCaptureState.Streaming -> {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(18.dp),
                    ) {
                        StreamingStat(
                            label = "FPS",
                            value = "%.1f".format(captureState.fps),
                        )
                        StreamingStat(
                            label = "Frames",
                            value = "${captureState.framesReceived}",
                        )
                        StreamingStat(
                            label = "Duration",
                            value = "%.0fs".format(captureState.durationSec),
                        )
                    }
                    CaptureActionButton(
                        label = "Stop Capture",
                        color = BlueprintAccent,
                        onClick = onStopCapture,
                    )
                }
            }

            is GlassesCaptureState.Paused -> {
                CaptureActionButton(
                    label = "Resume Capture",
                    color = BlueprintTeal,
                    onClick = onStartCapture,
                )
            }

            is GlassesCaptureState.Finished -> {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(
                        text = "Capture complete — ${captureState.artifacts.frameCount} frames, " +
                            "%.1fs".format(captureState.artifacts.durationMs / 1000.0),
                        color = BlueprintSuccess,
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Medium,
                    )
                    CaptureActionButton(
                        label = "Start New Capture",
                        color = BlueprintTeal,
                        onClick = onStartCapture,
                    )
                }
            }

            is GlassesCaptureState.Error -> {
                Text(
                    text = captureState.message,
                    color = BlueprintAccent,
                    fontSize = 13.sp,
                )
                CaptureActionButton(
                    label = "Retry Capture",
                    color = BlueprintTeal,
                    onClick = onStartCapture,
                )
            }
        }

        Text(
            text = "Disconnect",
            color = BlueprintTextMuted,
            fontSize = 14.sp,
            modifier = Modifier
                .clickable(onClick = onDisconnect)
                .padding(top = 4.dp),
        )
    }
}

@Composable
private fun CaptureActionButton(label: String, color: androidx.compose.ui.graphics.Color, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(color.copy(alpha = 0.15f))
            .border(1.dp, color.copy(alpha = 0.35f), RoundedCornerShape(12.dp))
            .clickable(onClick = onClick)
            .padding(vertical = 12.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(text = label, color = color, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun StreamingStat(label: String, value: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(text = value, color = BlueprintTeal, fontSize = 18.sp, fontWeight = FontWeight.Bold)
        Text(text = label, color = BlueprintTextMuted, fontSize = 12.sp)
    }
}

@Composable
private fun ErrorCard(message: String, onRetry: () -> Unit) {
    Column(
        modifier = Modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text(
            text = message,
            color = BlueprintTextMuted,
            fontSize = 14.sp,
        )
        SetupRequiredCard(onClick = onRetry)
    }
}
