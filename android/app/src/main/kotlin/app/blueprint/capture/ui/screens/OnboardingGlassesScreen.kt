package app.blueprint.capture.ui.screens

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.hilt.navigation.compose.hiltViewModel
import app.blueprint.capture.ui.theme.BlueprintAccent
import app.blueprint.capture.ui.theme.BlueprintBlack
import app.blueprint.capture.ui.theme.BlueprintBorderStrong
import app.blueprint.capture.ui.theme.BlueprintSurfaceRaised
import app.blueprint.capture.ui.theme.BlueprintTeal
import app.blueprint.capture.ui.theme.BlueprintTextMuted
import app.blueprint.capture.ui.theme.BlueprintTextPrimary

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun OnboardingGlassesScreen(
    onContinue: () -> Unit,
    glassesViewModel: GlassesViewModel = hiltViewModel(),
) {
    val context = LocalContext.current
    val connectionState by glassesViewModel.state.collectAsState()
    var showConnectSheet by rememberSaveable { mutableStateOf(false) }

    val blePermissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestMultiplePermissions(),
    ) {
        glassesViewModel.startScanning()
    }

    fun requestBleAndScan() {
        val required = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }
        val allGranted = required.all {
            ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED
        }
        if (allGranted) {
            glassesViewModel.startScanning()
        } else {
            blePermissionLauncher.launch(required)
        }
    }

    val connectedDeviceName = (connectionState as? GlassesConnectionState.Connected)?.deviceName

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
                .padding(horizontal = 28.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(modifier = Modifier.weight(1f))

            GlassesIcon(
                modifier = Modifier.size(86.dp),
                tint = BlueprintTeal,
            )

            Spacer(modifier = Modifier.height(20.dp))

            Text(
                text = "Connect Smart Glasses",
                color = BlueprintTextPrimary,
                fontSize = 30.sp,
                lineHeight = 34.sp,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center,
            )

            Spacer(modifier = Modifier.height(12.dp))

            Text(
                text = "Optional - pair Meta smart glasses for hands-free capture.",
                color = BlueprintTextMuted,
                fontSize = 17.sp,
                lineHeight = 24.sp,
                textAlign = TextAlign.Center,
            )

            if (connectedDeviceName != null) {
                Spacer(modifier = Modifier.height(16.dp))
                Text(
                    text = "Connected to $connectedDeviceName",
                    color = BlueprintTeal,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.Medium,
                    textAlign = TextAlign.Center,
                )
            }

            Spacer(modifier = Modifier.weight(1f))

            PrimaryOnboardingButton(
                text = if (connectedDeviceName != null) "Continue" else connectionButtonTitle(connectionState),
                onClick = if (connectedDeviceName != null) {
                    onContinue
                } else {
                    { showConnectSheet = true }
                },
            )

            Spacer(modifier = Modifier.height(14.dp))

            Text(
                text = if (connectedDeviceName != null) "Manage Connection" else "Skip - Use Phone Only",
                color = BlueprintTextMuted,
                fontSize = 16.sp,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.clickable {
                    if (connectedDeviceName != null) {
                        showConnectSheet = true
                    } else {
                        onContinue()
                    }
                },
            )

            Spacer(modifier = Modifier.height(32.dp))
        }
    }

    if (showConnectSheet) {
        ModalBottomSheet(
            onDismissRequest = { showConnectSheet = false },
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
            containerColor = BlueprintSurfaceRaised,
            contentColor = BlueprintTextPrimary,
            dragHandle = {
                Box(
                    modifier = Modifier
                        .padding(top = 10.dp)
                        .size(width = 42.dp, height = 4.dp)
                        .clip(RoundedCornerShape(999.dp))
                        .background(BlueprintBorderStrong),
                )
            },
        ) {
            GlassesConnectionSheet(
                viewModel = glassesViewModel,
                onScanRequest = ::requestBleAndScan,
            )
        }
    }
}

@Composable
private fun PrimaryOnboardingButton(
    text: String,
    onClick: () -> Unit,
) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .background(BlueprintAccent, RoundedCornerShape(18.dp))
            .clickable(onClick = onClick)
            .padding(vertical = 18.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = text,
            color = BlueprintBlack,
            fontSize = 18.sp,
            fontWeight = FontWeight.Bold,
        )
    }
}

private fun connectionButtonTitle(state: GlassesConnectionState): String = when (state) {
    is GlassesConnectionState.Connected -> "Continue"
    is GlassesConnectionState.Connecting -> "Connecting..."
    is GlassesConnectionState.Scanning -> "Scanning..."
    is GlassesConnectionState.Error -> "Try Again"
    GlassesConnectionState.Idle -> "Connect Glasses"
}
