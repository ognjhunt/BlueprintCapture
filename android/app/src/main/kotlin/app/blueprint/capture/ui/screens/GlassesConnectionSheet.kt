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
import androidx.compose.foundation.layout.weight
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
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat
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
import app.blueprint.capture.data.glasses.AndroidXrProjectedPlatform
import app.blueprint.capture.data.glasses.GlassesPlatformId
import app.blueprint.capture.data.glasses.MetaDatGlassesPlatform
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
    xrViewModel: AndroidXrViewModel = hiltViewModel(),
    captureLaunch: CaptureLaunch? = null,
) {
    val context = LocalContext.current
    val activity = context.findActivity()
    val state by viewModel.state.collectAsState()
    val captureState by viewModel.captureState.collectAsState()
    val captureUiState by viewModel.captureUiState.collectAsState()
    val xrState by xrViewModel.uiState.collectAsState()
    var selectedPlatform by rememberSaveable { mutableStateOf(GlassesPlatformId.AndroidXrProjected) }

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
        xrViewModel.setCaptureContext(captureLaunch)
    }
    DisposableEffect(Unit) {
        onDispose {
            viewModel.setCaptureContext(null)
            xrViewModel.setCaptureContext(null)
        }
    }

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

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            GlassesPlatformCard(
                title = AndroidXrProjectedPlatform.title,
                subtitle = AndroidXrProjectedPlatform.subtitle,
                isSelected = selectedPlatform == AndroidXrProjectedPlatform.id,
                onClick = { selectedPlatform = AndroidXrProjectedPlatform.id },
                modifier = Modifier.weight(1f),
            )
            GlassesPlatformCard(
                title = MetaDatGlassesPlatform.title,
                subtitle = MetaDatGlassesPlatform.subtitle,
                isSelected = selectedPlatform == MetaDatGlassesPlatform.id,
                onClick = { selectedPlatform = MetaDatGlassesPlatform.id },
                modifier = Modifier.weight(1f),
            )
        }

        Spacer(modifier = Modifier.height(18.dp))

        // State-driven action area
        if (selectedPlatform == GlassesPlatformId.AndroidXrProjected) {
            AndroidXrPanel(
                uiState = xrState,
                captureLaunch = captureLaunch,
                onLaunch = { xrViewModel.launchProjectedExperience(activity) },
            )
        } else {
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
                        captureLaunch = captureUiState.captureLaunch,
                        captureState = captureState,
                        captureUiState = captureUiState,
                        onStartCapture = viewModel::startCapture,
                        onStopCapture = viewModel::stopCapture,
                        onResumeCapture = viewModel::resumeCapture,
                        onDisconnect = viewModel::disconnect,
                    )
                }

                is GlassesConnectionState.Error -> {
                    ErrorCard(message = s.message, onRetry = ::requestMetaSetup)
                }
            }
        }
    }
}

@Composable
private fun GlassesPlatformCard(
    title: String,
    subtitle: String,
    isSelected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(16.dp))
            .background(if (isSelected) BlueprintTealSurface else BlueprintSurfaceInset)
            .border(
                width = 1.dp,
                color = if (isSelected) BlueprintTeal else BlueprintBorder,
                shape = RoundedCornerShape(16.dp),
            )
            .clickable(onClick = onClick)
            .padding(14.dp),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(
                text = title,
                color = BlueprintTextPrimary,
                fontSize = 15.sp,
                fontWeight = FontWeight.Bold,
            )
            Text(
                text = subtitle,
                color = BlueprintTextMuted,
                fontSize = 12.sp,
                lineHeight = 16.sp,
            )
        }
    }
}

@Composable
private fun AndroidXrPanel(
    uiState: AndroidXrUiState,
    captureLaunch: CaptureLaunch?,
    onLaunch: () -> Unit,
) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(BlueprintSurfaceInset)
            .border(1.dp, BlueprintBorder, RoundedCornerShape(18.dp))
            .padding(18.dp),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(
                text = if (uiState.isProjectedDeviceConnected) {
                    "Android XR glasses detected"
                } else {
                    "Waiting for Android XR glasses"
                },
                color = BlueprintTextPrimary,
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
            )
            Text(
                text = uiState.launchMessage,
                color = BlueprintTextMuted,
                fontSize = 14.sp,
                lineHeight = 20.sp,
            )
            Text(
                text = buildString {
                    append(if (uiState.capabilities.supportsProjectedCamera) "Projected camera" else "No projected camera")
                    append(" • ")
                    append(if (uiState.capabilities.supportsProjectedMic) "Projected mic" else "No projected mic")
                    append(" • ")
                    append(if (uiState.capabilities.supportsGeospatial) "Geospatial-ready" else "No geospatial")
                },
                color = BlueprintTextMuted,
                fontSize = 13.sp,
                lineHeight = 18.sp,
            )
            uiState.launchError?.let {
                Text(
                    text = it,
                    color = Color(0xFFFF8A80),
                    fontSize = 13.sp,
                    lineHeight = 18.sp,
                )
            }
            uiState.queuedUploadId?.let {
                Text(
                    text = "Queued projected capture: $it",
                    color = BlueprintSuccess,
                    fontSize = 13.sp,
                    lineHeight = 18.sp,
                )
            }
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(16.dp))
                    .background(BlueprintAccent)
                    .clickable(onClick = onLaunch)
                    .padding(vertical = 16.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = if (captureLaunch != null) "Launch Android XR capture" else "Open Android XR readiness mode",
                    color = BlueprintBlack,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Bold,
                )
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
    captureLaunch: CaptureLaunch?,
    captureState: GlassesCaptureState,
    captureUiState: GlassesCaptureUiState,
    onStartCapture: () -> Unit,
    onStopCapture: () -> Unit,
    onResumeCapture: () -> Unit,
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

        val captureContextLabel = captureLaunch?.label
        if (captureContextLabel != null) {
            Text(
                text = "Capture target: $captureContextLabel",
                color = BlueprintTextMuted,
                fontSize = 13.sp,
            )
        } else {
            Text(
                text = "Connection only. Start glasses capture from a live target so the upload keeps truthful site metadata.",
                color = BlueprintTextMuted,
                fontSize = 13.sp,
            )
        }

        // Capture controls — driven by captureState
        when (captureState) {
            is GlassesCaptureState.Idle -> {
                if (captureLaunch != null) {
                    CaptureActionButton(
                        label = "Start Capture",
                        color = BlueprintTeal,
                        enabled = !captureUiState.isFinalizing,
                        onClick = onStartCapture,
                    )
                }
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
                        label = if (captureUiState.isFinalizing) "Finalizing…" else "Stop Capture",
                        color = BlueprintAccent,
                        enabled = !captureUiState.isFinalizing,
                        onClick = onStopCapture,
                    )
                }
            }

            is GlassesCaptureState.Paused -> {
                CaptureActionButton(
                    label = "Resume Capture",
                    color = BlueprintTeal,
                    enabled = !captureUiState.isFinalizing,
                    onClick = onResumeCapture,
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
                    when {
                        captureUiState.isFinalizing -> Row(
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(18.dp),
                                color = BlueprintTeal,
                                strokeWidth = 2.dp,
                                trackColor = BlueprintSurfaceInset,
                            )
                            Text(
                                text = captureUiState.statusMessage ?: "Queueing upload…",
                                color = BlueprintTextMuted,
                                fontSize = 13.sp,
                            )
                        }
                        captureUiState.queuedUploadId != null -> Text(
                            text = captureUiState.statusMessage
                                ?: "Capture bundled and queued for upload.",
                            color = BlueprintSuccess,
                            fontSize = 13.sp,
                        )
                        captureLaunch != null -> CaptureActionButton(
                            label = "Start New Capture",
                            color = BlueprintTeal,
                            onClick = onStartCapture,
                        )
                    }
                }
            }

            is GlassesCaptureState.Error -> {
                Text(
                    text = captureState.message,
                    color = BlueprintAccent,
                    fontSize = 13.sp,
                )
                if (captureLaunch != null) {
                    CaptureActionButton(
                        label = "Retry Capture",
                        color = BlueprintTeal,
                        enabled = !captureUiState.isFinalizing,
                        onClick = onStartCapture,
                    )
                }
            }
        }

        captureUiState.errorMessage?.let { message ->
            Text(
                text = message,
                color = BlueprintAccent,
                fontSize = 13.sp,
            )
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
private fun CaptureActionButton(
    label: String,
    color: androidx.compose.ui.graphics.Color,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(color.copy(alpha = if (enabled) 0.15f else 0.08f))
            .border(1.dp, color.copy(alpha = if (enabled) 0.35f else 0.18f), RoundedCornerShape(12.dp))
            .clickable(enabled = enabled, onClick = onClick)
            .padding(vertical = 12.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = label,
            color = if (enabled) color else color.copy(alpha = 0.55f),
            fontSize = 15.sp,
            fontWeight = FontWeight.SemiBold,
        )
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
