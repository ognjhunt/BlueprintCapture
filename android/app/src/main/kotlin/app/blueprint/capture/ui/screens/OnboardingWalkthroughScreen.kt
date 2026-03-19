package app.blueprint.capture.ui.screens

import android.content.pm.PackageManager
import android.os.Build
import androidx.annotation.RawRes
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.DirectionsWalk
import androidx.compose.material.icons.rounded.CameraAlt
import androidx.compose.material.icons.rounded.Lightbulb
import androidx.compose.material.icons.rounded.MonetizationOn
import androidx.compose.material.icons.rounded.Radar
import androidx.compose.material.icons.rounded.RemoveCircleOutline
import androidx.compose.material.icons.rounded.Schedule
import androidx.compose.material.icons.rounded.StayCurrentPortrait
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import androidx.compose.ui.graphics.graphicsLayer
import app.blueprint.capture.R
import app.blueprint.capture.ui.theme.BlueprintActionBlue
import app.blueprint.capture.ui.theme.BlueprintBlack
import app.blueprint.capture.ui.theme.BlueprintTeal
import app.blueprint.capture.ui.theme.BlueprintTextPrimary
import app.blueprint.capture.ui.theme.BlueprintWalkthroughCard
import app.blueprint.capture.ui.theme.BlueprintWalkthroughCardSuccess
import app.blueprint.capture.ui.theme.BlueprintWalkthroughPill
import kotlinx.coroutines.launch
import kotlin.random.Random

private enum class WalkthroughVideo(@RawRes val rawRes: Int) {
    Cathedral(R.raw.onboarding_walkthrough_a),
    Villa(R.raw.onboarding_walkthrough_b),
}

private data class WalkthroughPage(
    val icon: ImageVector,
    val title: String,
    val body: String,
)

private data class DeviceCapability(
    val icon: ImageVector,
    val title: String,
    val subtitle: String,
    val highlighted: Boolean = false,
    val trailingText: String? = null,
)

@Composable
fun OnboardingWalkthroughScreen(
    onContinue: () -> Unit,
) {
    val context = LocalContext.current
    val pagerState = rememberPagerState(pageCount = { 5 })
    val scope = rememberCoroutineScope()
    val walkthroughVideo = rememberSaveable {
        WalkthroughVideo.entries[Random.nextInt(WalkthroughVideo.entries.size)]
    }
    val videoPages = remember {
        listOf(
            WalkthroughPage(
                icon = Icons.Rounded.StayCurrentPortrait,
                title = "Hold your phone upright",
                body = "Walk naturally with your phone in front of you, like you're taking a video.",
            ),
            WalkthroughPage(
                icon = Icons.AutoMirrored.Rounded.DirectionsWalk,
                title = "Move slowly and steadily",
                body = "Cover all areas of the space. Walk at a calm, even pace for the best results.",
            ),
            WalkthroughPage(
                icon = Icons.Rounded.Lightbulb,
                title = "Good lighting helps",
                body = "Well-lit spaces produce higher quality captures and bigger payouts.",
            ),
            WalkthroughPage(
                icon = Icons.Rounded.Schedule,
                title = "15-30 minutes",
                body = "A complete capture takes 15-30 minutes. Longer, thorough captures earn more.",
            ),
        )
    }
    val deviceName = remember {
        val model = Build.MODEL.orEmpty().trim()
        if (
            model.isBlank() ||
            model.contains("sdk", ignoreCase = true) ||
            model.contains("emulator", ignoreCase = true) ||
            Build.FINGERPRINT.contains("generic", ignoreCase = true)
        ) {
            "Simulator"
        } else {
            model
        }
    }
    val arCoreSupported = remember {
        context.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_AR)
    }
    val capabilities = remember(deviceName, arCoreSupported) {
        listOf(
            DeviceCapability(
                icon = Icons.Rounded.CameraAlt,
                title = "ARKit",
                subtitle = if (arCoreSupported) "Supported" else "Not supported",
            ),
            DeviceCapability(
                icon = Icons.Rounded.Radar,
                title = "LiDAR",
                subtitle = "Standard capture mode",
            ),
            DeviceCapability(
                icon = Icons.Rounded.MonetizationOn,
                title = "Earnings Multiplier",
                subtitle = "1x on every capture",
                highlighted = true,
                trailingText = "1x",
            ),
        )
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(BlueprintBlack),
    ) {
        if (pagerState.currentPage > 0) {
            WalkthroughVideoBackground(
                rawRes = walkthroughVideo.rawRes,
                modifier = Modifier.fillMaxSize(),
            )
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(
                        Brush.verticalGradient(
                            colors = listOf(
                                Color.Black.copy(alpha = 0.18f),
                                Color.Black.copy(alpha = 0.28f),
                                Color.Black.copy(alpha = 0.52f),
                                Color.Black.copy(alpha = 0.68f),
                            ),
                        ),
                    ),
            )
        }

        HorizontalPager(
            state = pagerState,
            modifier = Modifier.fillMaxSize(),
            beyondViewportPageCount = 1,
            contentPadding = PaddingValues(0.dp),
        ) { page ->
            when (page) {
                0 -> DeviceIntroPage(
                    deviceName = deviceName,
                    capabilities = capabilities,
                    onContinue = {
                        scope.launch { pagerState.animateScrollToPage(1) }
                    },
                )

                else -> WalkthroughMessagePage(
                    page = videoPages[page - 1],
                )
            }
        }

        if (pagerState.currentPage > 0) {
            Box(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .statusBarsPadding()
                    .padding(top = 76.dp, end = 36.dp)
                    .clip(RoundedCornerShape(999.dp))
                    .background(BlueprintWalkthroughPill)
                    .padding(horizontal = 18.dp, vertical = 10.dp),
            ) {
                Text(
                    text = "A Walkthrough",
                    color = BlueprintTextPrimary,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.SemiBold,
                )
            }
        }

        if (pagerState.currentPage > 0) {
            Column(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .navigationBarsPadding()
                    .padding(horizontal = 28.dp, vertical = 24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                OnboardingPageIndicators(
                    count = videoPages.size,
                    selectedIndex = pagerState.currentPage - 1,
                    selectedColor = Color.White,
                    unselectedColor = Color.White.copy(alpha = 0.34f),
                    modifier = Modifier.padding(bottom = 28.dp),
                )

                OnboardingPrimaryButton(
                    text = if (pagerState.currentPage == videoPages.lastIndex + 1) "Got It" else "Next",
                    containerColor = BlueprintActionBlue,
                    contentColor = Color.White,
                ) {
                    if (pagerState.currentPage == videoPages.lastIndex + 1) {
                        onContinue()
                    } else {
                        scope.launch { pagerState.animateScrollToPage(pagerState.currentPage + 1) }
                    }
                }

                OnboardingSecondaryAction(
                    text = "Skip Tutorial",
                    color = Color.White.copy(alpha = 0.7f),
                    modifier = Modifier.padding(top = 18.dp),
                    onClick = onContinue,
                )
            }
        }
    }
}

@Composable
private fun DeviceIntroPage(
    deviceName: String,
    capabilities: List<DeviceCapability>,
    onContinue: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .statusBarsPadding()
            .navigationBarsPadding()
            .padding(horizontal = 24.dp, vertical = 24.dp),
        verticalArrangement = Arrangement.SpaceBetween,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(modifier = Modifier.height(22.dp))
            Icon(
                imageVector = Icons.Rounded.StayCurrentPortrait,
                contentDescription = null,
                tint = BlueprintTeal,
                modifier = Modifier.size(82.dp),
            )
            Spacer(modifier = Modifier.height(22.dp))
            Text(
                text = "Your Device",
                color = BlueprintTextPrimary,
                fontSize = 32.sp,
                lineHeight = 36.sp,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center,
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = deviceName,
                color = Color(0xFF6F7078),
                fontSize = 22.sp,
                lineHeight = 26.sp,
                fontWeight = FontWeight.Medium,
                textAlign = TextAlign.Center,
            )
            Spacer(modifier = Modifier.height(18.dp))
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                capabilities.forEach { capability ->
                    DeviceCapabilityCard(capability = capability)
                }
            }
        }

        OnboardingPrimaryButton(
            text = "Continue",
            containerColor = BlueprintActionBlue,
            contentColor = Color.White,
            modifier = Modifier.padding(bottom = 6.dp),
            onClick = onContinue,
        )
    }
}

@Composable
private fun DeviceCapabilityCard(
    capability: DeviceCapability,
) {
    val backgroundColor = if (capability.highlighted) BlueprintWalkthroughCardSuccess else BlueprintWalkthroughCard
    val minCardHeight = if (capability.highlighted) 138.dp else 128.dp
    val verticalPadding = if (capability.highlighted) 18.dp else 14.dp
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = minCardHeight)
            .clip(RoundedCornerShape(22.dp))
            .background(backgroundColor)
            .padding(horizontal = 16.dp, vertical = verticalPadding),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(if (capability.highlighted) 40.dp else 36.dp)
                .clip(CircleShape)
                .background(if (capability.highlighted) Color(0xFF2AC67B) else Color.Transparent),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = capability.icon,
                contentDescription = null,
                tint = if (capability.highlighted) BlueprintBlack else Color(0xFFB1B1BA),
                modifier = Modifier.size(22.dp),
            )
        }

        Spacer(modifier = Modifier.width(16.dp))

        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = capability.title,
                color = BlueprintTextPrimary,
                fontSize = 17.sp,
                lineHeight = 21.sp,
                fontWeight = FontWeight.SemiBold,
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = capability.subtitle,
                color = Color(0xFF9898A1),
                fontSize = 14.sp,
                lineHeight = 18.sp,
            )
        }

        if (capability.trailingText != null) {
            Text(
                text = capability.trailingText,
                color = Color(0xFF2AC67B),
                fontSize = 20.sp,
                fontWeight = FontWeight.Bold,
            )
        } else {
            Icon(
                imageVector = Icons.Rounded.RemoveCircleOutline,
                contentDescription = null,
                tint = Color(0xFF8B8B93),
                modifier = Modifier.size(26.dp),
            )
        }
    }
}

@Composable
private fun WalkthroughMessagePage(
    page: WalkthroughPage,
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .statusBarsPadding()
            .navigationBarsPadding(),
    ) {
        Column(
            modifier = Modifier
                .align(Alignment.Center)
                .fillMaxWidth()
                .padding(horizontal = 34.dp)
                .padding(bottom = 108.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            GlowingIcon(
                icon = page.icon,
                size = 116.dp,
                iconSize = 82.dp,
            )
            Spacer(modifier = Modifier.height(34.dp))
            Text(
                text = page.title,
                color = Color.White,
                fontSize = 32.sp,
                lineHeight = 36.sp,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center,
            )
            Spacer(modifier = Modifier.height(18.dp))
            Text(
                text = page.body,
                color = Color.White.copy(alpha = 0.78f),
                fontSize = 18.sp,
                lineHeight = 26.sp,
                textAlign = TextAlign.Center,
            )
        }
    }
}

@Composable
private fun GlowingIcon(
    icon: ImageVector,
    size: Dp,
    iconSize: Dp,
) {
    Box(
        modifier = Modifier.size(size),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            modifier = Modifier
                .size(size * 0.84f)
                .clip(CircleShape)
                .background(BlueprintTeal.copy(alpha = 0.14f))
                .graphicsLayer {
                    scaleX = 1.18f
                    scaleY = 1.18f
                },
        )
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = BlueprintTeal,
            modifier = Modifier.size(iconSize),
        )
    }
}

@UnstableApi
@Composable
private fun WalkthroughVideoBackground(
    @RawRes rawRes: Int,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val exoPlayer = remember(context, rawRes) {
        ExoPlayer.Builder(context)
            .build()
            .apply {
                setMediaItem(MediaItem.fromUri("android.resource://${context.packageName}/$rawRes"))
                repeatMode = Player.REPEAT_MODE_ALL
                volume = 0f
                videoScalingMode = C.VIDEO_SCALING_MODE_SCALE_TO_FIT_WITH_CROPPING
                prepare()
                playWhenReady = true
            }
    }

    DisposableEffect(exoPlayer) {
        onDispose {
            exoPlayer.release()
        }
    }

    AndroidView(
        modifier = modifier,
        factory = { viewContext ->
            PlayerView(viewContext).apply {
                useController = false
                resizeMode = AspectRatioFrameLayout.RESIZE_MODE_ZOOM
                player = exoPlayer
                setShutterBackgroundColor(android.graphics.Color.TRANSPARENT)
            }
        },
        update = { view ->
            view.player = exoPlayer
        },
    )
}
