package app.blueprint.capture.ui.screens

import android.content.pm.PackageManager
import android.os.Build
import androidx.compose.animation.AnimatedContent
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.CropFree
import androidx.compose.material.icons.rounded.Groups
import androidx.compose.material.icons.rounded.PhoneAndroid
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material.icons.rounded.Star
import androidx.compose.material.icons.rounded.VerifiedUser
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import app.blueprint.capture.ui.theme.BlueprintAccent
import app.blueprint.capture.ui.theme.BlueprintBlack
import app.blueprint.capture.ui.theme.BlueprintBorder
import app.blueprint.capture.ui.theme.BlueprintBorderStrong
import app.blueprint.capture.ui.theme.BlueprintSectionLabel
import app.blueprint.capture.ui.theme.BlueprintSuccess
import app.blueprint.capture.ui.theme.BlueprintSurfaceCard
import app.blueprint.capture.ui.theme.BlueprintSurfaceInset
import app.blueprint.capture.ui.theme.BlueprintSurfaceRaised
import app.blueprint.capture.ui.theme.BlueprintTeal
import app.blueprint.capture.ui.theme.BlueprintTealSurface
import app.blueprint.capture.ui.theme.BlueprintTextMuted
import app.blueprint.capture.ui.theme.BlueprintTextPrimary
import app.blueprint.capture.ui.theme.BlueprintWarning
import app.blueprint.capture.ui.theme.BlueprintWarningSurface
import java.text.NumberFormat
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProfileScreen(
    viewModel: ProfileViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsState()
    val stats = state.profile?.stats
    val tier = remember(stats?.totalCaptures) { tierPresentation(stats?.totalCaptures ?: 0) }
    val contributorName = remember(state.firebaseUser) {
        state.firebaseUser?.displayName
            ?.takeIf { it.isNotBlank() }
            ?: state.firebaseUser?.email?.substringBefore("@")?.takeIf { it.isNotBlank() }
            ?: "Capturer"
    }
    val subtitle = state.firebaseUser?.email ?: "Not signed in"
    var showSettings by rememberSaveable { mutableStateOf(false) }
    var activeSheet by rememberSaveable { mutableStateOf<ProfileSheetMode?>(null) }

    AnimatedContent(targetState = showSettings, label = "profile-settings-nav") { onSettings ->
        if (onSettings) {
            SettingsScreen(
                isSignedIn = state.isSignedIn,
                userName = contributorName,
                userEmail = state.firebaseUser?.email,
                onSignIn = {},
                onBack = { showSettings = false },
            )
        } else {
            activeSheet?.let { sheetMode ->
                ModalBottomSheet(
                    onDismissRequest = { activeSheet = null },
                    sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
                    containerColor = BlueprintSurfaceRaised,
                    contentColor = BlueprintTextPrimary,
                    dragHandle = {
                        Box(
                            modifier = Modifier
                                .padding(top = 10.dp)
                                .width(42.dp)
                                .height(4.dp)
                                .clip(RoundedCornerShape(999.dp))
                                .background(BlueprintBorderStrong),
                        )
                    },
                ) {
                    ProfileSheet(
                        mode = sheetMode,
                        state = state,
                        tier = tier,
                    )
                }
            }

            val scrollState = rememberScrollState()
            val deviceSummary = rememberDeviceSummary()
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .background(BlueprintBlack)
                    .statusBarsPadding()
                    .verticalScroll(scrollState)
                    .padding(horizontal = 20.dp),
            ) {
                Spacer(modifier = Modifier.height(12.dp))
                HeaderSection(
                    subtitle = subtitle,
                    onOpenSettings = { showSettings = true },
                )
                Spacer(modifier = Modifier.height(24.dp))
                ContributorCard(
                    contributorName = contributorName,
                    tier = tier,
                )
                Spacer(modifier = Modifier.height(26.dp))
                SectionLabel("Statistics")
                Spacer(modifier = Modifier.height(12.dp))
                StatisticsGrid(
                    totalCaptures = stats?.totalCaptures ?: 0,
                    earnings = formatCurrency((stats?.totalEarningsCents ?: 0) / 100.0),
                    referrals = 0,
                    approved = stats?.approvedCaptures ?: 0,
                )
                Spacer(modifier = Modifier.height(28.dp))
                SectionLabel("Account")
                Spacer(modifier = Modifier.height(12.dp))
                AccountLinksCard(
                    onOpenAchievements = { activeSheet = ProfileSheetMode.Achievements },
                    onOpenReferrals = { activeSheet = ProfileSheetMode.Referrals },
                    onOpenSettings = { showSettings = true },
                )
                Spacer(modifier = Modifier.height(28.dp))
                SectionLabel("Device")
                Spacer(modifier = Modifier.height(12.dp))
                DeviceCard(deviceSummary = deviceSummary)
                Spacer(modifier = Modifier.height(32.dp))
            }
        }
    }
}

@Composable
private fun HeaderSection(
    subtitle: String,
    onOpenSettings: () -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Text(
                text = "My Account",
                color = BlueprintTextPrimary,
                fontSize = 34.sp,
                lineHeight = 38.sp,
                fontWeight = FontWeight.Bold,
            )
            Text(
                text = subtitle,
                color = BlueprintTextMuted,
                fontSize = 17.sp,
                lineHeight = 22.sp,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }
        Spacer(modifier = Modifier.width(16.dp))
        Box(
            modifier = Modifier
                .size(58.dp)
                .clip(RoundedCornerShape(29.dp))
                .background(BlueprintSurfaceCard),
        ) {
            IconButton(
                onClick = onOpenSettings,
                modifier = Modifier.fillMaxSize(),
            ) {
                Icon(
                    imageVector = Icons.Rounded.Settings,
                    contentDescription = "Settings",
                    tint = BlueprintTextMuted,
                    modifier = Modifier.size(28.dp),
                )
            }
        }
    }
}

@Composable
private fun ContributorCard(
    contributorName: String,
    tier: TierPresentation,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(BlueprintSurfaceCard, RoundedCornerShape(28.dp))
            .border(1.dp, BlueprintBorder, RoundedCornerShape(28.dp))
            .padding(16.dp),
        horizontalArrangement = Arrangement.spacedBy(16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        TierBadgeIcon()
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(
                text = "CONTRIBUTOR",
                color = BlueprintSectionLabel,
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold,
                letterSpacing = 3.sp,
            )
            Text(
                text = contributorName,
                color = BlueprintTextPrimary,
                fontSize = 23.sp,
                lineHeight = 28.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Box(
                modifier = Modifier
                    .clip(RoundedCornerShape(999.dp))
                    .background(tier.backgroundColor)
                    .padding(horizontal = 12.dp, vertical = 5.dp),
            ) {
                Text(
                    text = tier.label,
                    color = tier.textColor,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold,
                    letterSpacing = 1.2.sp,
                )
            }
        }
    }
}

@Composable
private fun TierBadgeIcon() {
    Box(
        modifier = Modifier
            .size(98.dp)
            .clip(RoundedCornerShape(24.dp))
            .background(BlueprintSurfaceRaised),
    ) {
        Canvas(
            modifier = Modifier
                .fillMaxSize()
                .padding(18.dp),
        ) {
            val width = size.width
            val height = size.height
            val path = Path().apply {
                moveTo(width / 2f, 0f)
                lineTo(width, height * 0.25f)
                lineTo(width, height * 0.75f)
                lineTo(width / 2f, height)
                lineTo(0f, height * 0.75f)
                lineTo(0f, height * 0.25f)
                close()
            }
            drawPath(path = path, color = Color(0xFF3A3B3E))
            drawPath(
                path = path,
                color = Color(0xFF444549),
                style = Stroke(width = 1.5.dp.toPx(), cap = StrokeCap.Round),
            )
        }
        Box(
            modifier = Modifier
                .size(48.dp)
                .clip(RoundedCornerShape(10.dp))
                .background(BlueprintTeal)
                .align(Alignment.Center),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = "B",
                color = Color(0xFF183432),
                fontSize = 20.sp,
                fontWeight = FontWeight.Black,
            )
        }
    }
}

@Composable
private fun StatisticsGrid(
    totalCaptures: Int,
    earnings: String,
    referrals: Int,
    approved: Int,
) {
    Column(
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            StatCard(
                modifier = Modifier.weight(1f),
                title = "Total Captures",
                value = "$totalCaptures",
                icon = {
                    Icon(
                        imageVector = Icons.Rounded.CropFree,
                        contentDescription = null,
                        tint = BlueprintTeal,
                        modifier = Modifier.size(22.dp),
                    )
                },
            )
            StatCard(
                modifier = Modifier.weight(1f),
                title = "Earnings",
                value = earnings,
                icon = {
                    Box(
                        modifier = Modifier
                            .size(28.dp)
                            .clip(RoundedCornerShape(14.dp))
                            .background(BlueprintSuccess),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            text = "$",
                            color = BlueprintBlack,
                            fontSize = 18.sp,
                            fontWeight = FontWeight.Bold,
                        )
                    }
                },
            )
        }
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            StatCard(
                modifier = Modifier.weight(1f),
                title = "Referrals",
                value = "$referrals",
                icon = {
                    Icon(
                        imageVector = Icons.Rounded.Groups,
                        contentDescription = null,
                        tint = BlueprintWarning,
                        modifier = Modifier.size(22.dp),
                    )
                },
            )
            StatCard(
                modifier = Modifier.weight(1f),
                title = "Approved",
                value = "$approved",
                icon = {
                    Icon(
                        imageVector = Icons.Rounded.VerifiedUser,
                        contentDescription = null,
                        tint = BlueprintTextMuted,
                        modifier = Modifier.size(22.dp),
                    )
                },
            )
        }
    }
}

@Composable
private fun StatCard(
    modifier: Modifier = Modifier,
    title: String,
    value: String,
    icon: @Composable () -> Unit,
) {
    Column(
        modifier = modifier
            .aspectRatio(1.02f)
            .background(BlueprintSurfaceCard, RoundedCornerShape(26.dp))
            .border(1.dp, BlueprintBorder, RoundedCornerShape(26.dp))
            .padding(18.dp),
        verticalArrangement = Arrangement.SpaceBetween,
    ) {
        icon()
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(
                text = value,
                color = BlueprintTextPrimary,
                fontSize = 28.sp,
                lineHeight = 30.sp,
                fontWeight = FontWeight.Bold,
            )
            Text(
                text = title,
                color = BlueprintTextMuted,
                fontSize = 15.sp,
                lineHeight = 20.sp,
            )
        }
    }
}

@Composable
private fun SectionLabel(text: String) {
    Text(
        text = text.uppercase(Locale.US),
        color = BlueprintSectionLabel,
        fontSize = 13.sp,
        fontWeight = FontWeight.Bold,
        letterSpacing = 2.4.sp,
    )
}

@Composable
private fun AccountLinksCard(
    onOpenAchievements: () -> Unit,
    onOpenReferrals: () -> Unit,
    onOpenSettings: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(BlueprintSurfaceCard, RoundedCornerShape(28.dp))
            .border(1.dp, BlueprintBorder, RoundedCornerShape(28.dp)),
    ) {
        AccountRow(
            icon = Icons.Rounded.Star,
            iconBackground = BlueprintWarningSurface,
            title = "Level & Achievements",
            subtitle = "Track progress and badges",
            onClick = onOpenAchievements,
        )
        RowDivider()
        AccountRow(
            icon = Icons.Rounded.Groups,
            iconBackground = BlueprintTealSurface,
            title = "Referrals",
            subtitle = "Earn 10% of friends' captures",
            onClick = onOpenReferrals,
        )
        RowDivider()
        AccountRow(
            icon = Icons.Rounded.Settings,
            iconBackground = BlueprintSurfaceInset,
            title = "Settings",
            subtitle = "Account, payouts, preferences",
            onClick = onOpenSettings,
        )
    }
}

@Composable
private fun AccountRow(
    icon: ImageVector,
    iconBackground: Color,
    title: String,
    subtitle: String,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 18.dp, vertical = 18.dp),
        horizontalArrangement = Arrangement.spacedBy(16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(54.dp)
                .clip(RoundedCornerShape(16.dp))
                .background(iconBackground),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = BlueprintAccent,
                modifier = Modifier.size(28.dp),
            )
        }
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(
                text = title,
                color = BlueprintTextPrimary,
                fontSize = 20.sp,
                lineHeight = 24.sp,
                fontWeight = FontWeight.Bold,
            )
            Text(
                text = subtitle,
                color = BlueprintTextMuted,
                fontSize = 14.sp,
                lineHeight = 19.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        Icon(
            imageVector = Icons.AutoMirrored.Rounded.KeyboardArrowRight,
            contentDescription = null,
            tint = BlueprintTextMuted.copy(alpha = 0.45f),
            modifier = Modifier.size(30.dp),
        )
    }
}

@Composable
private fun RowDivider() {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(start = 88.dp, end = 18.dp)
            .height(1.dp)
            .background(BlueprintBorder),
    )
}

@Composable
private fun DeviceCard(
    deviceSummary: DeviceSummary,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(BlueprintSurfaceCard, RoundedCornerShape(28.dp))
            .border(1.dp, BlueprintBorder, RoundedCornerShape(28.dp))
            .padding(horizontal = 18.dp, vertical = 20.dp),
        horizontalArrangement = Arrangement.spacedBy(16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(54.dp)
                .clip(RoundedCornerShape(16.dp))
                .background(BlueprintSurfaceInset),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = Icons.Rounded.PhoneAndroid,
                contentDescription = null,
                tint = BlueprintAccent,
                modifier = Modifier.size(28.dp),
            )
        }
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(
                text = deviceSummary.name,
                color = BlueprintTextPrimary,
                fontSize = 20.sp,
                lineHeight = 24.sp,
                fontWeight = FontWeight.Bold,
            )
            Text(
                text = deviceSummary.capabilityLine,
                color = BlueprintTextMuted,
                fontSize = 14.sp,
                lineHeight = 19.sp,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }
        Text(
            text = deviceSummary.multiplier,
            color = BlueprintSuccess,
            fontSize = 22.sp,
            fontWeight = FontWeight.Bold,
        )
    }
}

@Composable
private fun ProfileSheet(
    mode: ProfileSheetMode,
    state: ProfileUiState,
    tier: TierPresentation,
) {
    val stats = state.profile?.stats
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(start = 20.dp, end = 20.dp, top = 12.dp, bottom = 32.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text(
            text = mode.title,
            color = BlueprintTextPrimary,
            fontSize = 26.sp,
            lineHeight = 30.sp,
            fontWeight = FontWeight.Bold,
        )

        when (mode) {
            ProfileSheetMode.Achievements -> {
                SheetInfoCard(
                    title = tier.label,
                    subtitle = "Current contributor tier",
                )
                SheetMetricRow("Total captures", "${stats?.totalCaptures ?: 0}")
                SheetMetricRow("Approved captures", "${stats?.approvedCaptures ?: 0}")
                SheetMetricRow("Approval rate", "${stats?.approvalRatePercent ?: 0}%")
            }

            ProfileSheetMode.Referrals -> {
                SheetInfoCard(
                    title = "$0",
                    subtitle = "Referrals connected",
                )
                SheetMetricRow("Referral earnings", formatCurrency((stats?.referralEarningsCents ?: 0) / 100.0))
                SheetMetricRow("Referral bonuses", formatCurrency((stats?.referralBonusCents ?: 0) / 100.0))
                Text(
                    text = "Referral totals are available here while the full referrals destination is still being brought over from iOS.",
                    color = BlueprintTextMuted,
                    fontSize = 14.sp,
                    lineHeight = 19.sp,
                )
            }
        }
    }
}

@Composable
private fun SheetInfoCard(
    title: String,
    subtitle: String,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(BlueprintSurfaceCard, RoundedCornerShape(22.dp))
            .border(1.dp, BlueprintBorder, RoundedCornerShape(22.dp))
            .padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(
            text = title,
            color = BlueprintTextPrimary,
            fontSize = 22.sp,
            fontWeight = FontWeight.Bold,
        )
        Text(
            text = subtitle,
            color = BlueprintTextMuted,
            fontSize = 14.sp,
        )
    }
}

@Composable
private fun SheetMetricRow(
    label: String,
    value: String,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(BlueprintSurfaceCard, RoundedCornerShape(18.dp))
            .border(1.dp, BlueprintBorder, RoundedCornerShape(18.dp))
            .padding(horizontal = 18.dp, vertical = 16.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(
            text = label,
            color = BlueprintTextMuted,
            fontSize = 15.sp,
        )
        Text(
            text = value,
            color = BlueprintTextPrimary,
            fontSize = 16.sp,
            fontWeight = FontWeight.SemiBold,
        )
    }
}

@Composable
private fun ProfileTextField(
    label: String,
    value: String,
    onValueChange: (String) -> Unit,
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        modifier = Modifier.fillMaxWidth(),
        label = { Text(label) },
        shape = RoundedCornerShape(18.dp),
        colors = OutlinedTextFieldDefaults.colors(
            focusedTextColor = BlueprintTextPrimary,
            unfocusedTextColor = BlueprintTextPrimary,
            focusedContainerColor = BlueprintSurfaceCard,
            unfocusedContainerColor = BlueprintSurfaceCard,
            focusedBorderColor = BlueprintBorderStrong,
            unfocusedBorderColor = BlueprintBorder,
            focusedLabelColor = BlueprintTextMuted,
            unfocusedLabelColor = BlueprintTextMuted,
            cursorColor = BlueprintTeal,
        ),
        singleLine = true,
    )
}

@Composable
private fun rememberDeviceSummary(): DeviceSummary {
    val context = LocalContext.current
    return remember(context) {
        val packageManager = context.packageManager
        val isEmulator = Build.FINGERPRINT.contains("generic", ignoreCase = true) ||
            Build.MODEL.contains("Emulator", ignoreCase = true) ||
            Build.HARDWARE.contains("ranchu", ignoreCase = true)
        val displayName = when {
            isEmulator -> "Android Emulator"
            Build.MANUFACTURER.isBlank() -> Build.MODEL
            else -> "${Build.MANUFACTURER} ${Build.MODEL}".trim()
        }.ifBlank { "Android Device" }
        val capabilities = buildList {
            if (packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY)) add("Camera2")
            if (packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_AR)) add("ARCore")
        }.ifEmpty { listOf("Standard camera") }

        DeviceSummary(
            name = displayName,
            capabilityLine = "${capabilities.joinToString(" x ")} x 1x multiplier",
            multiplier = "1x",
        )
    }
}

private data class DeviceSummary(
    val name: String,
    val capabilityLine: String,
    val multiplier: String,
)

private enum class ProfileSheetMode(val title: String) {
    Achievements("Level & Achievements"),
    Referrals("Referrals"),
}

private data class TierPresentation(
    val label: String,
    val textColor: Color,
    val backgroundColor: Color,
)

private fun tierPresentation(totalCaptures: Int): TierPresentation =
    when (totalCaptures) {
        in 0..4 -> TierPresentation("IRON", BlueprintTextMuted, BlueprintSurfaceInset)
        in 5..19 -> TierPresentation("BRONZE", BlueprintWarning, BlueprintWarningSurface.copy(alpha = 0.35f))
        in 20..49 -> TierPresentation("SILVER", Color(0xFFC1C4CB), Color(0x332C3138))
        else -> TierPresentation("GOLD", Color(0xFFE3C45F), Color(0x335D4A15))
    }

private fun formatCurrency(value: Double): String =
    NumberFormat.getCurrencyInstance(Locale.US).format(value)
