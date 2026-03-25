package app.blueprint.capture.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.AccountBalance
import androidx.compose.material.icons.rounded.BugReport
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.CreditCard
import androidx.compose.material.icons.rounded.Description
import androidx.compose.material.icons.rounded.GraphicEq
import androidx.compose.material.icons.automirrored.rounded.Help
import androidx.compose.material.icons.rounded.Language
import androidx.compose.material.icons.rounded.NearMe
import androidx.compose.material.icons.rounded.Payments
import androidx.compose.material.icons.rounded.Person
import androidx.compose.material.icons.rounded.PhotoCamera
import androidx.compose.material.icons.rounded.Timer
import androidx.compose.material.icons.rounded.Verified
import androidx.compose.material.icons.rounded.Videocam
import androidx.compose.material.icons.rounded.Warning
import androidx.compose.material.icons.rounded.Wifi
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.blueprint.capture.data.notification.NotificationPreferenceKey
import app.blueprint.capture.ui.theme.BlueprintAccent
import app.blueprint.capture.ui.theme.BlueprintBorder
import app.blueprint.capture.ui.theme.BlueprintBlack
import app.blueprint.capture.ui.theme.BlueprintBorderStrong
import app.blueprint.capture.ui.theme.BlueprintSurfaceRaised
import app.blueprint.capture.ui.theme.BlueprintError
import app.blueprint.capture.ui.theme.BlueprintSectionLabel
import app.blueprint.capture.ui.theme.BlueprintSurfaceCard
import app.blueprint.capture.ui.theme.BlueprintSurfaceInset
import app.blueprint.capture.ui.theme.BlueprintTeal
import app.blueprint.capture.ui.theme.BlueprintTealSurface
import app.blueprint.capture.ui.theme.BlueprintTextMuted
import app.blueprint.capture.ui.theme.BlueprintTextPrimary
import app.blueprint.capture.ui.theme.BlueprintWarning
import androidx.compose.foundation.layout.statusBarsPadding
import java.util.Locale

// Icon background colors matching iOS
private val IconBgNavyBlue = Color(0xFF1A2340)
private val IconTintNavyBlue = Color(0xFF6B8DD6)
private val IconBgPurple = Color(0xFF2D1A40)
private val IconTintPurple = Color(0xFFB06DD6)
private val IconBgAmber = Color(0xFF2D1E0A)
private val IconBgBugRed = Color(0xFF3D1A1A)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    isSignedIn: Boolean,
    userName: String,
    userEmail: String?,
    onSignIn: () -> Unit,
    onBack: () -> Unit,
    settingsPreferencesViewModel: SettingsPreferencesViewModel = hiltViewModel(),
    glassesViewModel: GlassesViewModel = hiltViewModel(),
) {
    val scrollState = rememberScrollState()
    val context = LocalContext.current
    var showGlassesSheet by rememberSaveable { mutableStateOf(false) }
    var showPayouts by rememberSaveable { mutableStateOf(false) }

    if (showPayouts) {
        PayoutsScreen(onBack = { showPayouts = false })
        return
    }

    var wifiOnlyUploads by remember { mutableStateOf(false) }
    val autoClearCompleted by settingsPreferencesViewModel.uploadAutoClear.collectAsState()
    val notificationPreferences by settingsPreferencesViewModel.notificationPreferences.collectAsState()
    var captureHaptics by remember { mutableStateOf(true) }

    val packageInfo = remember(context) {
        runCatching {
            context.packageManager.getPackageInfo(context.packageName, 0)
        }.getOrNull()
    }
    val versionName = packageInfo?.versionName?.removePrefix("") ?: "1.0"
    val versionCode = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
        packageInfo?.longVersionCode?.toString() ?: "1"
    } else {
        @Suppress("DEPRECATION")
        packageInfo?.versionCode?.toString() ?: "1"
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(BlueprintBlack)
            .statusBarsPadding()
            .verticalScroll(scrollState),
    ) {
        Spacer(modifier = Modifier.height(8.dp))

        // Back button
        Box(
            modifier = Modifier
                .padding(horizontal = 16.dp)
                .size(40.dp)
                .clip(RoundedCornerShape(20.dp))
                .background(BlueprintSurfaceCard)
                .clickable(onClick = onBack),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = Icons.AutoMirrored.Rounded.KeyboardArrowLeft,
                contentDescription = "Back",
                tint = BlueprintTextPrimary,
                modifier = Modifier.size(26.dp),
            )
        }

        Spacer(modifier = Modifier.height(16.dp))

        // Title block
        Column(modifier = Modifier.padding(horizontal = 20.dp)) {
            Text(
                text = "Settings",
                color = BlueprintTextPrimary,
                fontSize = 34.sp,
                lineHeight = 38.sp,
                fontWeight = FontWeight.Bold,
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = "Manage your account and preferences",
                color = BlueprintTextMuted,
                fontSize = 17.sp,
                lineHeight = 22.sp,
            )
        }

        Spacer(modifier = Modifier.height(28.dp))

        // PROFILE
        SettingsSectionLabel("Profile")
        Spacer(modifier = Modifier.height(10.dp))
        ProfileRowCard(
            isSignedIn = isSignedIn,
            userName = userName,
            userEmail = userEmail,
            onSignIn = onSignIn,
            modifier = Modifier.padding(horizontal = 20.dp),
        )

        Spacer(modifier = Modifier.height(28.dp))

        // PAYOUTS
        SettingsSectionLabel("Payouts")
        Spacer(modifier = Modifier.height(10.dp))
        SettingsCard(modifier = Modifier.padding(horizontal = 20.dp)) {
            SettingsNavRow(
                icon = Icons.Rounded.CreditCard,
                iconBg = BlueprintTealSurface,
                iconTint = BlueprintTeal,
                title = "Manage Payouts",
                subtitle = "View Android alpha payout status and backend sync notes",
                onClick = { showPayouts = true },
            )
            SettingsRowDivider()
            SettingsNavRow(
                icon = Icons.Rounded.AccountBalance,
                iconBg = IconBgNavyBlue,
                iconTint = IconTintNavyBlue,
                title = "Payout Onboarding",
                subtitle = "Not yet enabled on Android alpha",
                onClick = { showPayouts = true },
            )
            SettingsRowDivider()
            SettingsNavRow(
                icon = Icons.Rounded.Videocam,
                iconBg = BlueprintTealSurface,
                iconTint = BlueprintTeal,
                title = "Capture Glasses",
                subtitle = "Connect Meta smart glasses",
                onClick = { showGlassesSheet = true },
            )
        }

        Spacer(modifier = Modifier.height(28.dp))

        // CAPTURE
        SettingsSectionLabel("Capture")
        Spacer(modifier = Modifier.height(10.dp))
        SettingsCard(modifier = Modifier.padding(horizontal = 20.dp)) {
            SettingsToggleRow(
                icon = Icons.Rounded.Wifi,
                iconBg = IconBgNavyBlue,
                iconTint = IconTintNavyBlue,
                title = "Wi-Fi Only Uploads",
                subtitle = "Prevent uploads over cellular data",
                checked = wifiOnlyUploads,
                onCheckedChange = { wifiOnlyUploads = it },
            )
            SettingsRowDivider()
            SettingsToggleRow(
                icon = Icons.Rounded.CheckCircle,
                iconBg = BlueprintTealSurface,
                iconTint = BlueprintTeal,
                title = "Auto-Clear Completed",
                subtitle = "Remove completed items from queue",
                checked = autoClearCompleted,
                onCheckedChange = settingsPreferencesViewModel::setUploadAutoClear,
            )
            SettingsRowDivider()
            SettingsToggleRow(
                icon = Icons.Rounded.GraphicEq,
                iconBg = IconBgPurple,
                iconTint = IconTintPurple,
                title = "Capture Haptics",
                subtitle = "Vibration feedback during capture",
                checked = captureHaptics,
                onCheckedChange = { captureHaptics = it },
            )
        }

        Spacer(modifier = Modifier.height(28.dp))

        // NOTIFICATIONS
        SettingsSectionLabel("Notifications")
        Spacer(modifier = Modifier.height(10.dp))
        SettingsCard(modifier = Modifier.padding(horizontal = 20.dp)) {
            SettingsToggleRow(
                icon = Icons.Rounded.NearMe,
                iconBg = BlueprintTealSurface,
                iconTint = BlueprintTeal,
                title = "Nearby job alerts",
                subtitle = "Nearby approved jobs that enter your geofence",
                checked = notificationPreferences.isEnabled(NotificationPreferenceKey.NearbyJobs),
                onCheckedChange = {
                    settingsPreferencesViewModel.setNotificationPreference(
                        NotificationPreferenceKey.NearbyJobs,
                        it,
                    )
                },
            )
            SettingsRowDivider()
            SettingsToggleRow(
                icon = Icons.Rounded.Timer,
                iconBg = IconBgAmber,
                iconTint = BlueprintWarning,
                title = "Reservation alerts",
                subtitle = "Reservation reminders and expiry updates",
                checked = notificationPreferences.isEnabled(NotificationPreferenceKey.Reservations),
                onCheckedChange = {
                    settingsPreferencesViewModel.setNotificationPreference(
                        NotificationPreferenceKey.Reservations,
                        it,
                    )
                },
            )
            SettingsRowDivider()
            SettingsToggleRow(
                icon = Icons.Rounded.Verified,
                iconBg = BlueprintTealSurface,
                iconTint = BlueprintTeal,
                title = "Capture status",
                subtitle = "Approved, needs fix, rejected, and paid captures",
                checked = notificationPreferences.isEnabled(NotificationPreferenceKey.CaptureStatus),
                onCheckedChange = {
                    settingsPreferencesViewModel.setNotificationPreference(
                        NotificationPreferenceKey.CaptureStatus,
                        it,
                    )
                },
            )
            SettingsRowDivider()
            SettingsToggleRow(
                icon = Icons.Rounded.Payments,
                iconBg = IconBgNavyBlue,
                iconTint = IconTintNavyBlue,
                title = "Payout updates",
                subtitle = "Scheduled, sent, and failed payout events",
                checked = notificationPreferences.isEnabled(NotificationPreferenceKey.Payouts),
                onCheckedChange = {
                    settingsPreferencesViewModel.setNotificationPreference(
                        NotificationPreferenceKey.Payouts,
                        it,
                    )
                },
            )
            SettingsRowDivider()
            SettingsToggleRow(
                icon = Icons.Rounded.Warning,
                iconBg = IconBgAmber,
                iconTint = BlueprintWarning,
                title = "Account alerts",
                subtitle = "Payout method and account action required alerts",
                checked = notificationPreferences.isEnabled(NotificationPreferenceKey.Account),
                onCheckedChange = {
                    settingsPreferencesViewModel.setNotificationPreference(
                        NotificationPreferenceKey.Account,
                        it,
                    )
                },
            )
        }

        Spacer(modifier = Modifier.height(28.dp))

        // USEFUL LINKS
        SettingsSectionLabel("Useful Links")
        Spacer(modifier = Modifier.height(10.dp))
        SettingsCard(modifier = Modifier.padding(horizontal = 20.dp)) {
            SettingsNavRow(
                icon = Icons.Rounded.Language,
                iconBg = BlueprintSurfaceInset,
                iconTint = BlueprintTextMuted,
                title = "Main Website",
                onClick = {},
            )
            SettingsRowDivider()
            SettingsNavRow(
                icon = Icons.AutoMirrored.Rounded.Help,
                iconBg = BlueprintSurfaceInset,
                iconTint = BlueprintTextMuted,
                title = "Help Center",
                onClick = {},
            )
            SettingsRowDivider()
            SettingsNavRow(
                icon = Icons.Rounded.BugReport,
                iconBg = IconBgBugRed,
                iconTint = BlueprintError,
                title = "Report a Bug",
                onClick = {},
            )
        }

        Spacer(modifier = Modifier.height(28.dp))

        // LEGAL
        SettingsSectionLabel("Legal")
        Spacer(modifier = Modifier.height(10.dp))
        SettingsCard(modifier = Modifier.padding(horizontal = 20.dp)) {
            SettingsNavRow(
                icon = Icons.Rounded.Description,
                iconBg = BlueprintSurfaceInset,
                iconTint = BlueprintTextMuted,
                title = "Terms of Service",
                onClick = {},
            )
            SettingsRowDivider()
            SettingsNavRow(
                icon = Icons.Rounded.PhotoCamera,
                iconBg = BlueprintSurfaceInset,
                iconTint = BlueprintTextMuted,
                title = "Privacy Policy",
                onClick = {},
            )
            SettingsRowDivider()
            SettingsNavRow(
                icon = Icons.Rounded.PhotoCamera,
                iconBg = BlueprintSurfaceInset,
                iconTint = BlueprintTextMuted,
                title = "Capture Policy",
                onClick = {},
            )
        }

        Spacer(modifier = Modifier.height(28.dp))

        // TECHNICAL DETAILS
        SettingsSectionLabel("Technical Details")
        Spacer(modifier = Modifier.height(10.dp))
        SettingsCard(modifier = Modifier.padding(horizontal = 20.dp)) {
            SettingsInfoRow(label = "Version", value = versionName)
            SettingsRowDivider(indented = false)
            SettingsInfoRow(label = "Build", value = versionCode)
        }

        Spacer(modifier = Modifier.height(40.dp))
    }

    if (showGlassesSheet) {
        ModalBottomSheet(
            onDismissRequest = { showGlassesSheet = false },
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
            GlassesConnectionSheet(
                viewModel = glassesViewModel,
            )
        }
    }
}

// ── Sub-components ────────────────────────────────────────────────────────────

@Composable
private fun SettingsSectionLabel(text: String) {
    Text(
        text = text.uppercase(Locale.US),
        color = BlueprintSectionLabel,
        fontSize = 13.sp,
        fontWeight = FontWeight.Bold,
        letterSpacing = 2.4.sp,
        modifier = Modifier.padding(horizontal = 20.dp),
    )
}

@Composable
private fun SettingsCard(
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(BlueprintSurfaceCard, RoundedCornerShape(18.dp))
            .border(1.dp, BlueprintBorder, RoundedCornerShape(18.dp)),
        content = content,
    )
}

@Composable
private fun ProfileRowCard(
    isSignedIn: Boolean,
    userName: String,
    userEmail: String?,
    onSignIn: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .background(BlueprintSurfaceCard, RoundedCornerShape(18.dp))
            .border(1.dp, BlueprintBorder, RoundedCornerShape(18.dp))
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Box(
            modifier = Modifier
                .size(50.dp)
                .clip(RoundedCornerShape(14.dp))
                .background(BlueprintTealSurface),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = Icons.Rounded.Person,
                contentDescription = null,
                tint = BlueprintTeal,
                modifier = Modifier.size(28.dp),
            )
        }
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                text = userName,
                color = BlueprintTextPrimary,
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
            )
            Text(
                text = userEmail ?: "Not signed in",
                color = BlueprintTextMuted,
                fontSize = 14.sp,
            )
        }
        if (!isSignedIn) {
            Box(
                modifier = Modifier
                    .clip(RoundedCornerShape(10.dp))
                    .background(BlueprintTealSurface)
                    .border(1.dp, BlueprintTeal.copy(alpha = 0.3f), RoundedCornerShape(10.dp))
                    .clickable(onClick = onSignIn)
                    .padding(horizontal = 16.dp, vertical = 8.dp),
            ) {
                Text(
                    text = "Sign In",
                    color = BlueprintTeal,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                )
            }
        }
    }
}

@Composable
private fun SettingsNavRow(
    icon: ImageVector,
    iconBg: Color,
    iconTint: Color,
    title: String,
    subtitle: String? = null,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 13.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Box(
            modifier = Modifier
                .size(44.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(iconBg),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = iconTint,
                modifier = Modifier.size(24.dp),
            )
        }
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                text = title,
                color = BlueprintTextPrimary,
                fontSize = 17.sp,
                fontWeight = FontWeight.Medium,
            )
            if (subtitle != null) {
                Text(
                    text = subtitle,
                    color = BlueprintTextMuted,
                    fontSize = 13.sp,
                    lineHeight = 17.sp,
                )
            }
        }
        Icon(
            imageVector = Icons.AutoMirrored.Rounded.KeyboardArrowRight,
            contentDescription = null,
            tint = BlueprintTextMuted.copy(alpha = 0.4f),
            modifier = Modifier.size(22.dp),
        )
    }
}

@Composable
private fun SettingsToggleRow(
    icon: ImageVector,
    iconBg: Color,
    iconTint: Color,
    title: String,
    subtitle: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onCheckedChange(!checked) }
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Box(
            modifier = Modifier
                .size(44.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(iconBg),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = iconTint,
                modifier = Modifier.size(24.dp),
            )
        }
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                text = title,
                color = BlueprintTextPrimary,
                fontSize = 17.sp,
                fontWeight = FontWeight.Medium,
            )
            Text(
                text = subtitle,
                color = BlueprintTextMuted,
                fontSize = 13.sp,
                lineHeight = 17.sp,
            )
        }
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange,
            colors = SwitchDefaults.colors(
                checkedThumbColor = BlueprintAccent,
                checkedTrackColor = BlueprintTeal,
                uncheckedThumbColor = BlueprintTextMuted,
                uncheckedTrackColor = BlueprintSurfaceInset,
                uncheckedBorderColor = BlueprintBorder,
            ),
        )
    }
}

@Composable
private fun SettingsInfoRow(
    label: String,
    value: String,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 14.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(text = label, color = BlueprintTextMuted, fontSize = 17.sp)
        Text(text = value, color = BlueprintTextMuted, fontSize = 17.sp)
    }
}

@Composable
private fun SettingsRowDivider(indented: Boolean = true) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(start = if (indented) 74.dp else 16.dp, end = 16.dp)
            .height(1.dp)
            .background(BlueprintBorder),
    )
}
