package app.blueprint.capture.ui.screens

import androidx.camera.video.Recorder
import androidx.camera.video.VideoCapture
import androidx.camera.view.PreviewView
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import app.blueprint.capture.data.capture.ARCoreSupportLevel
import app.blueprint.capture.data.model.CaptureLaunch
import app.blueprint.capture.ui.theme.BlueprintAccent
import app.blueprint.capture.ui.theme.BlueprintBlack
import app.blueprint.capture.ui.theme.BlueprintError
import app.blueprint.capture.ui.theme.BlueprintSurfaceRaised
import app.blueprint.capture.ui.theme.BlueprintTextMuted
import app.blueprint.capture.ui.theme.BlueprintTextPrimary

@Composable
internal fun CaptureRecorderHost(
    capture: CaptureLaunch,
    previewView: PreviewView,
    hasDetailsSurface: Boolean,
    permissionsGranted: Boolean,
    cameraError: String?,
    uiState: CaptureSessionUiState,
    isBusy: Boolean,
    isRecording: Boolean,
    elapsedSeconds: Long,
    videoCapture: VideoCapture<Recorder>?,
    arcoreSupportLevel: ARCoreSupportLevel,
    usingArcoreRuntime: Boolean,
    passBrief: SiteWorldPassBrief,
    routePlan: List<String>,
    requiredRules: List<String>,
    optionalRules: List<String>,
    highlightedAnchorTypes: Set<SiteWorldAnchorType>,
    onClose: () -> Unit,
    onRequestPermissions: () -> Unit,
    onUpdateSiteScale: (SiteWorldSiteScale) -> Unit,
    onToggleCriticalZone: (SiteWorldAnchorType) -> Unit,
    onMarkAnchor: (SiteWorldAnchorType) -> Unit,
    onMarkEntryLock: () -> Unit,
    onMarkWeakSignal: () -> Unit,
    onStartRecording: () -> Unit,
    onStopRecording: () -> Unit,
) {
    val workflowState = uiState.siteWorldRecordingState
    val livePrompt = remember(
        workflowState,
        passBrief,
        uiState.siteWorldCriticalZones,
    ) {
        when {
            !workflowState.entryLocked ->
                "Stand at the main entry point. Hold still for 3 seconds. Slowly pan left, center, right. Keep the door frame, floor edge, and nearby wall in view."
            workflowState.weakSignalEvents > 0 ->
                "Weak segment flagged. Reacquire fixed structure before moving deeper into the site."
            passBrief.role == "revisit" ->
                "Turn back and reacquire the last checkpoint from the reverse direction before leaving this zone."
            passBrief.role == "loop_closure" ->
                "Return to your start anchor. Match the original entrance view as closely as practical, then hold for 3 seconds."
            passBrief.role == "critical_zone_revisit" ->
                "Capture the static boundary, approach path, and exit path. Revisit once from the opposite direction."
            else ->
                "At the next doorway or intersection, stop at the threshold. Show left frame, center opening, right frame. Then continue."
        }
    }
    val liveSupportPrompts = remember(workflowState, uiState.siteWorldCriticalZones) {
        buildList {
            add("Prefer fixed building structure. Avoid following people, carts, pallets, or temporary clutter.")
            if (uiState.siteWorldCriticalZones.isNotEmpty()) {
                val remaining = uiState.siteWorldCriticalZones.subtract(workflowState.markedAnchors.toSet())
                if (remaining.isNotEmpty()) {
                    add("Still need critical zones: ${remaining.joinToString(", ") { it.label }}.")
                }
            }
        }.take(2)
    }
    val checkpointCount = workflowState.markedAnchors.count {
        it in setOf(
            SiteWorldAnchorType.Doorway,
            SiteWorldAnchorType.Intersection,
            SiteWorldAnchorType.DockTurn,
            SiteWorldAnchorType.HandoffPoint,
            SiteWorldAnchorType.FloorTransition,
            SiteWorldAnchorType.RestrictedBoundary,
        )
    }
    val arcoreStatusMessage = remember(arcoreSupportLevel, usingArcoreRuntime) {
        when {
            usingArcoreRuntime ->
                "ARCore recording is active. The on-screen camera preview is paused until a Camera2 SharedCamera pipeline is wired. walkthrough.mp4 and arcore/* evidence are still being recorded."
            arcoreSupportLevel == ARCoreSupportLevel.SupportedInstalled ->
                "Preview is live only during preflight. When recording starts, CameraX hands off to ARCore and the preview pauses because SharedCamera live preview is not wired yet."
            arcoreSupportLevel == ARCoreSupportLevel.SupportedNeedsInstall ->
                "This device needs the current ARCore service installed before ARCore-first capture can run."
            else -> null
        }
    }
    val canStartRecording = permissionsGranted && !isBusy && (videoCapture != null || arcoreSupportLevel == ARCoreSupportLevel.SupportedInstalled)

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(BlueprintBlack),
    ) {
        AndroidView(
            factory = { previewView },
            modifier = Modifier.fillMaxSize(),
        )

        if (usingArcoreRuntime) {
            Box(
                modifier = Modifier
                    .matchParentSize()
                    .background(BlueprintBlack.copy(alpha = 0.56f)),
                contentAlignment = Alignment.Center,
            ) {
                Column(
                    modifier = Modifier
                        .padding(horizontal = 24.dp)
                        .clip(RoundedCornerShape(24.dp))
                        .background(BlueprintSurfaceRaised.copy(alpha = 0.94f))
                        .padding(horizontal = 20.dp, vertical = 18.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Text(
                        text = "ARCore capture running",
                        style = TextStyle(
                            color = BlueprintTextPrimary,
                            fontSize = 18.sp,
                            lineHeight = 22.sp,
                            fontWeight = FontWeight.SemiBold,
                        ),
                    )
                    Text(
                        text = "Live camera preview is unavailable in this runtime until SharedCamera is integrated. Recording continues in the background.",
                        style = TextStyle(
                            color = BlueprintTextMuted,
                            fontSize = 14.sp,
                            lineHeight = 19.sp,
                            fontWeight = FontWeight.Medium,
                        ),
                    )
                }
            }
        }

        Box(
            modifier = Modifier
                .matchParentSize()
                .background(
                    brush = Brush.verticalGradient(
                        colors = listOf(
                            BlueprintBlack.copy(alpha = 0.42f),
                            Color.Transparent,
                            BlueprintBlack.copy(alpha = 0.30f),
                            BlueprintBlack.copy(alpha = 0.76f),
                        ),
                    ),
                ),
        )

        // Floating recording badges — shown when actively recording
        if (isRecording) {
            Row(
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .statusBarsPadding()
                    .padding(top = 14.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                RecordingIndicatorBadge()
                TimerBadge(elapsedSeconds = elapsedSeconds)
            }
        }

        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .navigationBarsPadding()
                .padding(horizontal = 20.dp, vertical = 16.dp),
            verticalArrangement = Arrangement.SpaceBetween,
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        text = if (hasDetailsSurface) capture.label else "Phone Capture",
                        style = TextStyle(
                            color = BlueprintTextPrimary,
                            fontSize = 20.sp,
                            lineHeight = 24.sp,
                            fontWeight = FontWeight.SemiBold,
                            letterSpacing = (-0.2).sp,
                        ),
                    )
                    if (!isRecording && !isBusy) {
                        OutlinedButton(onClick = onClose) {
                            Text(if (hasDetailsSurface) "Back" else "Close")
                        }
                    }
                }

                CaptureSessionSurfaceCard {
                    Text(capture.label)
                    Text(
                        when {
                            !permissionsGranted -> "Camera and microphone access are required before Android can record the walkthrough."
                            usingArcoreRuntime -> "ARCore recording is running. Keep walking the planned pass even though the preview is paused."
                            isRecording -> livePrompt
                            else -> "Plan the route, then start the next pass when you are ready."
                        },
                        color = BlueprintTextMuted,
                    )
                }

                arcoreStatusMessage?.let { message ->
                    CaptureSessionSurfaceCard {
                        Text("ARCore runtime")
                        Text(message, color = BlueprintTextMuted)
                    }
                }

                cameraError?.let { message ->
                    CaptureSessionSurfaceCard {
                        Text("Camera issue")
                        Text(message, color = BlueprintTextMuted)
                    }
                }

                uiState.errorMessage?.let { message ->
                    CaptureSessionSurfaceCard {
                        Text("Capture review issue")
                        Text(message, color = BlueprintTextMuted)
                    }
                }

                uiState.exportMessage?.let { message ->
                    CaptureSessionSurfaceCard {
                        Text("Export ready")
                        Text(message, color = BlueprintTextMuted)
                    }
                }

                if (!isRecording) {
                    SiteWorldPreflightCard(
                        siteScale = uiState.siteWorldSiteScale,
                        criticalZoneOptions = listOf(
                            SiteWorldAnchorType.DockTurn,
                            SiteWorldAnchorType.HandoffPoint,
                            SiteWorldAnchorType.ControlPanel,
                            SiteWorldAnchorType.FloorTransition,
                            SiteWorldAnchorType.RestrictedBoundary,
                        ),
                        selectedCriticalZones = uiState.siteWorldCriticalZones,
                        routePlan = routePlan,
                        requiredRules = requiredRules,
                        optionalRules = optionalRules,
                        passBrief = passBrief,
                        onUpdateSiteScale = onUpdateSiteScale,
                        onToggleCriticalZone = onToggleCriticalZone,
                    )
                } else {
                    SiteWorldLiveGuidanceCard(
                        passBrief = passBrief,
                        checkpointCount = checkpointCount,
                        entryLocked = workflowState.entryLocked,
                        weakSignalEvents = workflowState.weakSignalEvents,
                        criticalZoneCount = uiState.siteWorldCriticalZones.size,
                        matchedCriticalZones = uiState.siteWorldCriticalZones.intersect(workflowState.markedAnchors.toSet()).size,
                        prompt = livePrompt,
                        supportPrompts = liveSupportPrompts,
                    )
                    SiteWorldAnchorToolCard(
                        highlightedAnchorTypes = highlightedAnchorTypes,
                        onMarkAnchor = onMarkAnchor,
                        onMarkEntryLock = onMarkEntryLock,
                        onMarkWeakSignal = onMarkWeakSignal,
                    )
                }
            }

            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                CaptureSessionStatusPanel(
                    permissionsGranted = permissionsGranted,
                    isRecording = isRecording,
                    elapsedSeconds = elapsedSeconds,
                    uiState = uiState,
                    runtimeStatus = when {
                        usingArcoreRuntime -> "ARCore capture active"
                        arcoreSupportLevel == ARCoreSupportLevel.SupportedInstalled -> "ARCore preflight preview"
                        arcoreSupportLevel == ARCoreSupportLevel.SupportedNeedsInstall -> "ARCore install required"
                        else -> "CameraX video preview"
                    },
                )

                CapturePermissionGate(
                    permissionsGranted = permissionsGranted,
                    onRequestPermissions = onRequestPermissions,
                ) {
                    if (!isRecording) {
                        Button(
                            onClick = onStartRecording,
                            enabled = canStartRecording,
                            modifier = Modifier.fillMaxWidth(),
                            colors = ButtonDefaults.buttonColors(
                                containerColor = BlueprintAccent,
                                contentColor = BlueprintBlack,
                            ),
                        ) {
                            Text("Start walkthrough recording")
                        }
                    } else {
                        Button(
                            onClick = onStopRecording,
                            enabled = !isBusy,
                            modifier = Modifier.fillMaxWidth(),
                            colors = ButtonDefaults.buttonColors(
                                containerColor = BlueprintAccent,
                                contentColor = BlueprintBlack,
                            ),
                        ) {
                            Text("Finish pass and review")
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun RecordingIndicatorBadge() {
    val infiniteTransition = rememberInfiniteTransition(label = "rec-pulse")
    val alpha by infiniteTransition.animateFloat(
        initialValue = 1f,
        targetValue = 0.25f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 700, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "rec-alpha",
    )
    Row(
        modifier = Modifier
            .clip(RoundedCornerShape(999.dp))
            .background(Color(0xCC1A1A1C))
            .border(1.dp, BlueprintError.copy(alpha = 0.35f), RoundedCornerShape(999.dp))
            .padding(horizontal = 12.dp, vertical = 7.dp),
        horizontalArrangement = Arrangement.spacedBy(7.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(8.dp)
                .clip(CircleShape)
                .background(BlueprintError.copy(alpha = alpha)),
        )
        Text(
            text = "REC",
            color = BlueprintTextPrimary,
            fontSize = 13.sp,
            fontWeight = FontWeight.Bold,
            letterSpacing = 1.2.sp,
        )
    }
}

@Composable
private fun TimerBadge(elapsedSeconds: Long) {
    val minutes = elapsedSeconds / 60
    val seconds = elapsedSeconds % 60
    val label = "%d:%02d".format(minutes, seconds)
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(999.dp))
            .background(Color(0xCC1A1A1C))
            .border(1.dp, Color.White.copy(alpha = 0.12f), RoundedCornerShape(999.dp))
            .padding(horizontal = 12.dp, vertical = 7.dp),
    ) {
        Text(
            text = label,
            color = BlueprintTextPrimary,
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold,
            letterSpacing = 0.5.sp,
        )
    }
}
