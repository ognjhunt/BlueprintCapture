package app.blueprint.capture.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ArrowOutward
import androidx.compose.material.icons.rounded.ArrowUpward
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material.icons.rounded.MonetizationOn
import androidx.compose.material.icons.rounded.NearMe
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.Schedule
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Visibility
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.hilt.navigation.compose.hiltViewModel
import app.blueprint.capture.data.model.CaptureLaunch
import app.blueprint.capture.data.model.CapturePermissionTone
import app.blueprint.capture.data.model.ScanTarget
import app.blueprint.capture.ui.theme.BlueprintBlack
import app.blueprint.capture.ui.theme.BlueprintBorder
import app.blueprint.capture.ui.theme.BlueprintBorderStrong
import app.blueprint.capture.ui.theme.BlueprintError
import app.blueprint.capture.ui.theme.BlueprintSuccess
import app.blueprint.capture.ui.theme.BlueprintSurface
import app.blueprint.capture.ui.theme.BlueprintSurfaceRaised
import app.blueprint.capture.ui.theme.BlueprintTeal
import app.blueprint.capture.ui.theme.BlueprintTealDeep
import app.blueprint.capture.ui.theme.BlueprintTextPrimary
import app.blueprint.capture.ui.theme.BlueprintTextSecondary
import app.blueprint.capture.ui.theme.BlueprintTextMuted
import app.blueprint.capture.ui.theme.BlueprintWarning
import coil.compose.SubcomposeAsyncImage
import coil.compose.SubcomposeAsyncImageContent

@Composable
fun ScanScreen(
    onStartCapture: (CaptureLaunch) -> Unit,
    viewModel: ScanViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsState()

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(BlueprintBlack)
            .statusBarsPadding(),
        contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 14.dp, bottom = 28.dp),
        verticalArrangement = Arrangement.spacedBy(22.dp),
    ) {
        item {
            ScanHeader()
        }

        if (state.showGlassesBanner || state.showPayoutBanner) {
            item {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    if (state.showGlassesBanner) {
                        StatusBanner(
                            icon = Icons.Rounded.Visibility,
                            title = "Connect capture glasses",
                            subtitle = "Required for approved capture opportunities.",
                            accentColor = BlueprintTeal,
                            actionTitle = "Connect",
                            onClick = {},
                        )
                    }
                    if (state.showPayoutBanner) {
                        StatusBanner(
                            icon = Icons.Rounded.Lock,
                            title = state.payoutBannerTitle,
                            subtitle = state.payoutBannerBody,
                            accentColor = BlueprintTeal,
                            actionTitle = null,
                            onClick = {},
                        )
                    }
                }
            }
        }

        item {
            CapturePolicySection()
        }

        item {
            NearbySpacesSection(
                targets = state.targets,
                onTargetClick = { target -> onStartCapture(target.toLaunch()) },
            )
        }

        item {
            SubmitSpaceCard(
                onClick = {
                    onStartCapture(
                        CaptureLaunch(
                            label = "Open capture review",
                            requestedOutputs = listOf("qualification", "review_intake"),
                        ),
                    )
                },
            )
        }
    }
}

@Composable
private fun ScanHeader() {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(
                text = "Captures",
                style = TextStyle(
                    color = BlueprintTextPrimary,
                    fontSize = 50.sp,
                    lineHeight = 52.sp,
                    fontWeight = FontWeight.ExtraBold,
                    letterSpacing = (-1.2).sp,
                ),
            )
            Text(
                text = "Capture spaces for Blueprint review",
                style = TextStyle(
                    color = BlueprintTextMuted,
                    fontSize = 16.sp,
                    lineHeight = 21.sp,
                    fontWeight = FontWeight.Medium,
                ),
            )
        }

        Row(
            modifier = Modifier.padding(top = 14.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            HeaderActionButton(Icons.Rounded.Search, "Search")
            HeaderActionButton(Icons.Rounded.Refresh, "Refresh")
        }
    }
}

@Composable
private fun HeaderActionButton(
    icon: ImageVector,
    contentDescription: String,
) {
    Box(
        modifier = Modifier
            .size(56.dp)
            .clip(CircleShape)
            .background(BlueprintSurfaceRaised)
            .clickable(onClick = {})
            .border(1.dp, BlueprintBorder, CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = contentDescription,
            tint = BlueprintTextSecondary,
            modifier = Modifier.size(28.dp),
        )
    }
}

@Composable
private fun StatusBanner(
    icon: ImageVector,
    title: String,
    subtitle: String,
    accentColor: Color,
    actionTitle: String?,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(IntrinsicSize.Min)
            .clip(RoundedCornerShape(22.dp))
            .background(BlueprintSurface)
            .border(1.dp, accentColor.copy(alpha = 0.22f), RoundedCornerShape(22.dp)),
    ) {
        Box(
            modifier = Modifier
                .fillMaxHeight()
                .width(4.dp)
                .background(accentColor),
        )

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 18.dp, vertical = 18.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = accentColor,
                modifier = Modifier.size(28.dp),
            )

            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Text(
                    text = title,
                    style = TextStyle(
                        color = BlueprintTextPrimary,
                        fontSize = 17.sp,
                        lineHeight = 22.sp,
                        fontWeight = FontWeight.Bold,
                    ),
                )
                Text(
                    text = subtitle,
                    style = TextStyle(
                        color = BlueprintTextMuted,
                        fontSize = 14.sp,
                        lineHeight = 20.sp,
                        fontWeight = FontWeight.Medium,
                    ),
                )
            }

            if (actionTitle != null) {
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(24.dp))
                        .background(BlueprintTealDeep)
                        .clickable(onClick = onClick)
                        .padding(horizontal = 20.dp, vertical = 12.dp),
                ) {
                    Text(
                        text = actionTitle,
                        style = TextStyle(
                            color = BlueprintTeal,
                            fontSize = 16.sp,
                            fontWeight = FontWeight.Bold,
                        ),
                    )
                }
            }
        }
    }
}

@Composable
private fun CapturePolicySection() {
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Text(
            text = "What you may capture",
            style = TextStyle(
                color = BlueprintTextPrimary,
                fontSize = 24.sp,
                lineHeight = 28.sp,
                fontWeight = FontWeight.ExtraBold,
                letterSpacing = (-0.3).sp,
            ),
        )
        Text(
            text = "Common areas and approved opportunities are fine. Faces, screens, paperwork, and restricted zones are not.",
            style = TextStyle(
                color = BlueprintTextMuted,
                fontSize = 18.sp,
                lineHeight = 22.sp,
                fontWeight = FontWeight.Medium,
            ),
        )

        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                PolicyCard(
                    modifier = Modifier.weight(1f),
                    color = BlueprintSuccess,
                    title = "Approved",
                    subtitle = "Clear to capture",
                )
                PolicyCard(
                    modifier = Modifier.weight(1f),
                    color = BlueprintTeal,
                    title = "Review",
                    subtitle = "Needs Blueprint review",
                )
            }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                PolicyCard(
                    modifier = Modifier.weight(1f),
                    color = BlueprintWarning,
                    title = "Permission",
                    subtitle = "Check site access",
                )
                PolicyCard(
                    modifier = Modifier.weight(1f),
                    color = BlueprintError,
                    title = "Blocked",
                    subtitle = "Do not capture",
                )
            }
        }
    }
}

@Composable
private fun PolicyCard(
    modifier: Modifier = Modifier,
    color: Color,
    title: String,
    subtitle: String,
) {
    Column(
        modifier = modifier
            .heightIn(min = 126.dp)
            .clip(RoundedCornerShape(22.dp))
            .background(BlueprintSurface)
            .border(1.dp, color.copy(alpha = 0.32f), RoundedCornerShape(22.dp))
            .padding(horizontal = 16.dp, vertical = 18.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                modifier = Modifier
                    .size(18.dp)
                    .clip(CircleShape)
                    .background(color),
            )
            Text(
                text = title,
                style = TextStyle(
                    color = BlueprintTextPrimary,
                    fontSize = 18.sp,
                    lineHeight = 22.sp,
                    fontWeight = FontWeight.Bold,
                ),
            )
        }
        Text(
            text = subtitle,
            style = TextStyle(
                color = BlueprintTextMuted,
                fontSize = 16.sp,
                lineHeight = 21.sp,
                fontWeight = FontWeight.Medium,
            ),
        )
    }
}

@Composable
private fun NearbySpacesSection(
    targets: List<ScanTarget>,
    onTargetClick: (ScanTarget) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text(
            text = "Nearby Spaces",
            style = TextStyle(
                color = BlueprintTextPrimary,
                fontSize = 24.sp,
                lineHeight = 28.sp,
                fontWeight = FontWeight.ExtraBold,
                letterSpacing = (-0.3).sp,
            ),
        )

        LazyRow(
            horizontalArrangement = Arrangement.spacedBy(14.dp),
            contentPadding = PaddingValues(end = 10.dp),
        ) {
            items(targets, key = ScanTarget::id) { target ->
                NearbySpaceCard(
                    target = target,
                    onClick = { onTargetClick(target) },
                )
            }
        }
    }
}

@Composable
private fun NearbySpaceCard(
    target: ScanTarget,
    onClick: () -> Unit,
) {
    Box(
        modifier = Modifier
            .width(318.dp)
            .height(328.dp)
            .clip(RoundedCornerShape(30.dp))
            .background(BlueprintSurfaceRaised)
            .border(1.dp, BlueprintBorderStrong.copy(alpha = 0.9f), RoundedCornerShape(30.dp))
            .clickable(onClick = onClick),
    ) {
        TargetArtwork(target = target)

        Box(
            modifier = Modifier
                .matchParentSize()
                .background(
                    brush = Brush.verticalGradient(
                        colors = listOf(
                            Color.Black.copy(alpha = 0.10f),
                            Color.Black.copy(alpha = 0.18f),
                            Color.Black.copy(alpha = 0.86f),
                        ),
                    ),
                ),
        )

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(16.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Pill(
                    label = target.categoryLabel ?: "SPACE",
                    leadingDotColor = null,
                )
                Pill(
                    label = target.permissionLabel,
                    leadingDotColor = target.permissionColor,
                )
            }

            Box(modifier = Modifier.weight(1f))

            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    text = target.title,
                    style = TextStyle(
                        color = BlueprintTextPrimary,
                        fontSize = 24.sp,
                        lineHeight = 28.sp,
                        fontWeight = FontWeight.Bold,
                        letterSpacing = (-0.4).sp,
                    ),
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    text = target.addressText,
                    style = TextStyle(
                        color = BlueprintTextSecondary,
                        fontSize = 18.sp,
                        lineHeight = 22.sp,
                        fontWeight = FontWeight.Medium,
                    ),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )

                Row(
                    horizontalArrangement = Arrangement.spacedBy(16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    MetricChip(
                        icon = Icons.Rounded.MonetizationOn,
                        iconTint = BlueprintSuccess,
                        text = target.payoutText,
                    )
                    MetricChip(
                        icon = Icons.Rounded.NearMe,
                        iconTint = BlueprintTextSecondary,
                        text = target.distanceText,
                    )
                    if (target.shouldShowMinutes) {
                        MetricChip(
                            icon = Icons.Rounded.Schedule,
                            iconTint = BlueprintTextSecondary,
                            text = "${target.estimatedMinutes ?: 20} min",
                        )
                    }
                }

                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        text = if (target.readyNow) {
                            "Ready now · Start capture"
                        } else {
                            "Nearby · Tap to submit"
                        },
                        style = TextStyle(
                            color = BlueprintTextSecondary,
                            fontSize = 16.sp,
                            lineHeight = 20.sp,
                            fontWeight = FontWeight.SemiBold,
                        ),
                    )
                    Icon(
                        imageVector = Icons.Rounded.ArrowOutward,
                        contentDescription = null,
                        tint = BlueprintTextSecondary,
                        modifier = Modifier.size(18.dp),
                    )
                }
            }
        }
    }
}

@Composable
private fun TargetArtwork(target: ScanTarget) {
    val fallbackBrush = Brush.linearGradient(
        colors = listOf(
            target.permissionColor.copy(alpha = 0.35f),
            BlueprintSurfaceRaised,
            BlueprintBlack,
        ),
    )

    if (target.imageUrl.isNullOrBlank()) {
        FallbackArtwork(target = target, brush = fallbackBrush)
        return
    }

    SubcomposeAsyncImage(
        model = target.imageUrl,
        contentDescription = null,
        modifier = Modifier.fillMaxSize(),
        contentScale = ContentScale.Crop,
        loading = {
            FallbackArtwork(target = target, brush = fallbackBrush)
        },
        error = {
            FallbackArtwork(target = target, brush = fallbackBrush)
        },
        success = {
            SubcomposeAsyncImageContent()
        },
    )
}

@Composable
private fun FallbackArtwork(
    target: ScanTarget,
    brush: Brush,
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(brush),
            contentAlignment = Alignment.BottomStart,
    ) {
        Text(
            text = target.categoryLabel ?: "SPACE",
            modifier = Modifier.padding(start = 16.dp, bottom = 16.dp),
            style = TextStyle(
                color = BlueprintTextPrimary.copy(alpha = 0.18f),
                fontSize = 42.sp,
                fontWeight = FontWeight.ExtraBold,
                letterSpacing = (-0.8).sp,
            ),
        )
    }
}

@Composable
private fun Pill(
    label: String,
    leadingDotColor: Color?,
) {
    Row(
        modifier = Modifier
            .clip(RoundedCornerShape(18.dp))
            .background(Color(0xCC2C2C31))
            .padding(horizontal = 14.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (leadingDotColor != null) {
            Box(
                modifier = Modifier
                    .size(14.dp)
                    .clip(CircleShape)
                    .background(leadingDotColor),
            )
        }
        Text(
            text = label,
            style = TextStyle(
                color = BlueprintTextPrimary,
                fontSize = 17.sp,
                fontWeight = FontWeight.Bold,
            ),
        )
    }
}

@Composable
private fun MetricChip(
    icon: ImageVector,
    iconTint: Color,
    text: String,
) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = iconTint,
            modifier = Modifier.size(22.dp),
        )
        Text(
            text = text,
            style = TextStyle(
                color = BlueprintTextPrimary.copy(alpha = 0.92f),
                fontSize = 17.sp,
                lineHeight = 21.sp,
                fontWeight = FontWeight.Bold,
            ),
        )
    }
}

@Composable
private fun SubmitSpaceCard(
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(28.dp))
            .background(BlueprintSurface)
            .border(1.dp, BlueprintBorder, RoundedCornerShape(28.dp))
            .clickable(onClick = onClick)
            .padding(horizontal = 18.dp, vertical = 22.dp),
        horizontalArrangement = Arrangement.spacedBy(16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(48.dp)
                .clip(CircleShape)
                .background(BlueprintTeal),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = Icons.Rounded.ArrowUpward,
                contentDescription = null,
                tint = BlueprintBlack,
                modifier = Modifier.size(28.dp),
            )
        }

        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(
                text = "Submit a new space",
                style = TextStyle(
                    color = BlueprintTextPrimary,
                    fontSize = 22.sp,
                    lineHeight = 26.sp,
                    fontWeight = FontWeight.ExtraBold,
                    letterSpacing = (-0.3).sp,
                ),
            )
            Text(
                text = "Address first · Workflow notes · Review-gated",
                style = TextStyle(
                    color = BlueprintTextMuted,
                    fontSize = 17.sp,
                    lineHeight = 22.sp,
                    fontWeight = FontWeight.Medium,
                ),
            )
        }

        Icon(
            imageVector = Icons.Rounded.ChevronRight,
            contentDescription = null,
            tint = BlueprintTextMuted,
            modifier = Modifier.size(34.dp),
        )
    }
}

private val ScanTarget.permissionColor: Color
    get() = when (permissionTone) {
        CapturePermissionTone.Approved -> BlueprintSuccess
        CapturePermissionTone.Review -> BlueprintTeal
        CapturePermissionTone.Permission -> BlueprintWarning
        CapturePermissionTone.Blocked -> BlueprintError
    }

private val ScanTarget.permissionLabel: String
    get() = when (permissionTone) {
        CapturePermissionTone.Approved -> "Approved"
        CapturePermissionTone.Review -> "Review"
        CapturePermissionTone.Permission -> "Permission"
        CapturePermissionTone.Blocked -> "Blocked"
    }

private val ScanTarget.shouldShowMinutes: Boolean
    get() = estimatedMinutes != null && !distanceText.contains("min", ignoreCase = true)

private fun ScanTarget.toLaunch(): CaptureLaunch {
    return CaptureLaunch(
        label = title,
        targetId = id,
        jobId = id,
        siteSubmissionId = siteSubmissionId,
        workflowName = workflowName,
        workflowSteps = workflowSteps,
        zone = zone,
        owner = owner,
        requestedOutputs = requestedOutputs.ifEmpty { listOf("qualification", "review_intake") },
        quotedPayoutCents = quotedPayoutCents,
        rightsProfile = rightsProfile,
    )
}
