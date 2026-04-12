package app.blueprint.capture.ui.screens

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.CameraAlt
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.GpsFixed
import androidx.compose.material.icons.rounded.Notifications
import androidx.compose.material.icons.rounded.Security
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import app.blueprint.capture.data.permissions.StartupPermissionChecker
import app.blueprint.capture.ui.theme.BlueprintAccent
import app.blueprint.capture.ui.theme.BlueprintBorder
import app.blueprint.capture.ui.theme.BlueprintBlack
import app.blueprint.capture.ui.theme.BlueprintError
import app.blueprint.capture.ui.theme.BlueprintSurfaceCard
import app.blueprint.capture.ui.theme.BlueprintSuccess
import app.blueprint.capture.ui.theme.BlueprintTextMuted
import app.blueprint.capture.ui.theme.BlueprintTextPrimary
import app.blueprint.capture.ui.theme.BlueprintTeal

private data class PermissionItem(
    val label: String,
    val icon: ImageVector,
    val iconBg: Color,
    val iconTint: Color,
    val permission: String,
)

@Composable
fun PermissionsScreen(
    onEnable: () -> Unit,
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val startupPermissionChecker = remember(context.applicationContext) {
        StartupPermissionChecker(context.applicationContext)
    }
    var permissionError by remember { mutableStateOf<String?>(null) }

    val permissionItems = remember {
        buildList {
            add(
                PermissionItem(
                    label = "Location",
                    icon = Icons.Rounded.GpsFixed,
                    iconBg = Color(0xFF1C1C1E),
                    iconTint = BlueprintTextMuted,
                    permission = Manifest.permission.ACCESS_FINE_LOCATION,
                ),
            )
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                add(
                    PermissionItem(
                        label = "Notifications",
                        icon = Icons.Rounded.Notifications,
                        iconBg = Color(0xFF1C1C1E),
                        iconTint = BlueprintTextMuted,
                        permission = Manifest.permission.POST_NOTIFICATIONS,
                    ),
                )
            }
            add(
                PermissionItem(
                    label = "Camera",
                    icon = Icons.Rounded.CameraAlt,
                    iconBg = Color(0xFF1C1C1E),
                    iconTint = BlueprintTextMuted,
                    permission = Manifest.permission.CAMERA,
                ),
            )
        }
    }

    val grantedMap = remember {
        mutableStateMapOf<String, Boolean>()
    }
    val refreshPermissionStatuses = remember(context, permissionItems) {
        {
            permissionItems.forEach { item ->
                grantedMap[item.permission] = ContextCompat.checkSelfPermission(
                    context, item.permission,
                ) == PackageManager.PERMISSION_GRANTED
            }
        }
    }

    DisposableEffect(lifecycleOwner, refreshPermissionStatuses) {
        refreshPermissionStatuses()
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                refreshPermissionStatuses()
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
        }
    }

    val permissionsToRequest = permissionItems.map { it.permission }.toTypedArray()
    val launcher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestMultiplePermissions(),
    ) {
        refreshPermissionStatuses()
        if (startupPermissionChecker.hasRequiredStartupPermission()) {
            permissionError = null
            onEnable()
        } else {
            permissionError = "Location access is required to enter the app."
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(BlueprintBlack)
            .statusBarsPadding()
            .navigationBarsPadding(),
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(modifier = Modifier.weight(1f))

            // Shield + checkmark icon
            Box(
                modifier = Modifier.size(100.dp),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = Icons.Rounded.Security,
                    contentDescription = null,
                    tint = BlueprintTeal,
                    modifier = Modifier.size(100.dp),
                )
                Icon(
                    imageVector = Icons.Rounded.Check,
                    contentDescription = null,
                    tint = BlueprintBlack,
                    modifier = Modifier.size(44.dp),
                )
            }

            Spacer(modifier = Modifier.height(28.dp))

            Text(
                text = "Enable Permissions",
                color = BlueprintTextPrimary,
                fontSize = 36.sp,
                lineHeight = 40.sp,
                fontWeight = FontWeight.ExtraBold,
                textAlign = TextAlign.Center,
                letterSpacing = (-1.0).sp,
            )

            Spacer(modifier = Modifier.height(14.dp))

            Text(
                text = "We use these to find nearby spaces, capture stronger evidence, and keep review states up to date.",
                color = BlueprintTextMuted,
                fontSize = 16.sp,
                lineHeight = 22.sp,
                textAlign = TextAlign.Center,
            )

            Spacer(modifier = Modifier.weight(1f))

            // Permission rows
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                permissionItems.forEach { item ->
                    val granted = grantedMap[item.permission] == true
                    PermissionRow(
                        item = item,
                        granted = granted,
                    )
                }
            }

            permissionError?.let { error ->
                Spacer(modifier = Modifier.height(16.dp))
                Text(
                    text = error,
                    color = BlueprintError,
                    fontSize = 14.sp,
                    lineHeight = 20.sp,
                    textAlign = TextAlign.Center,
                )
            }

            Spacer(modifier = Modifier.height(140.dp))
        }

        // Enable button pinned at bottom
        Box(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .navigationBarsPadding()
                .padding(horizontal = 24.dp, vertical = 32.dp)
                .clip(RoundedCornerShape(18.dp))
                .background(BlueprintAccent)
                .clickable {
                    permissionError = null
                    refreshPermissionStatuses()
                    if (startupPermissionChecker.hasRequiredStartupPermission()) {
                        onEnable()
                    } else {
                        launcher.launch(permissionsToRequest)
                    }
                }
                .padding(vertical = 18.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = "Enable",
                color = BlueprintBlack,
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
            )
        }
    }
}

@Composable
private fun PermissionRow(
    item: PermissionItem,
    granted: Boolean,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(BlueprintSurfaceCard)
            .border(1.dp, BlueprintBorder, RoundedCornerShape(16.dp))
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Box(
            modifier = Modifier
                .size(40.dp)
                .clip(RoundedCornerShape(10.dp))
                .background(item.iconBg),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = item.icon,
                contentDescription = null,
                tint = item.iconTint,
                modifier = Modifier.size(22.dp),
            )
        }
        Text(
            text = item.label,
            color = BlueprintTextPrimary,
            fontSize = 17.sp,
            fontWeight = FontWeight.Medium,
            modifier = Modifier.weight(1f),
        )
        // Radio indicator
        Box(
            modifier = Modifier
                .size(26.dp)
                .clip(CircleShape)
                .background(
                    if (granted) BlueprintSuccess else Color.Transparent,
                )
                .border(
                    2.dp,
                    if (granted) BlueprintSuccess else BlueprintTextMuted.copy(alpha = 0.3f),
                    CircleShape,
                ),
            contentAlignment = Alignment.Center,
        ) {
            if (granted) {
                Icon(
                    imageVector = Icons.Rounded.Check,
                    contentDescription = null,
                    tint = BlueprintBlack,
                    modifier = Modifier.size(14.dp),
                )
            }
        }
    }
}
