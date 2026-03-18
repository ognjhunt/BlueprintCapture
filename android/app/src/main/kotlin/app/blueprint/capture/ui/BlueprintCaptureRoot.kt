package app.blueprint.capture.ui

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.Crossfade
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AccountCircle
import androidx.compose.material.icons.rounded.CreditCard
import androidx.compose.material.icons.rounded.CropFree
import androidx.compose.material3.Icon
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import app.blueprint.capture.data.config.LocalConfigProvider
import app.blueprint.capture.data.model.MainTab
import app.blueprint.capture.data.model.RootStage
import app.blueprint.capture.ui.components.UploadQueueOverlay
import app.blueprint.capture.ui.screens.AuthScreen
import app.blueprint.capture.ui.screens.CaptureSessionScreen
import app.blueprint.capture.ui.screens.InviteCodeScreen
import app.blueprint.capture.ui.screens.OnboardingScreen
import app.blueprint.capture.ui.screens.PermissionsScreen
import app.blueprint.capture.ui.screens.ProfileScreen
import app.blueprint.capture.ui.screens.ScanScreen
import app.blueprint.capture.ui.screens.WalletScreen
import app.blueprint.capture.ui.theme.BlueprintBlack
import app.blueprint.capture.ui.theme.BlueprintBorder
import app.blueprint.capture.ui.theme.BlueprintNavDivider
import app.blueprint.capture.ui.theme.BlueprintNavSelected
import app.blueprint.capture.ui.theme.BlueprintSurface
import app.blueprint.capture.ui.theme.BlueprintTextMuted
import app.blueprint.capture.ui.theme.BlueprintTextPrimary

@Composable
fun BlueprintCaptureRoot(
    configProvider: LocalConfigProvider = LocalConfigProvider(),
    rootViewModel: BlueprintCaptureRootViewModel = hiltViewModel(),
) {
    val config = configProvider.current()
    val rootState by rootViewModel.uiState.collectAsState()

    Surface(
        modifier = Modifier.fillMaxSize(),
        color = BlueprintBlack,
    ) {
        Crossfade(targetState = rootState.stage, label = "root-stage") { stage ->
            when (stage) {
                RootStage.Onboarding -> OnboardingScreen(
                    hasBackend = config.hasBackend,
                    hasStripe = config.hasStripe,
                    hasPlaces = config.hasPlaces,
                    onContinue = rootViewModel::completeOnboarding,
                )

                RootStage.Auth -> AuthScreen(
                    onSkip = rootViewModel::skipAuth,
                )

                RootStage.InviteCode -> InviteCodeScreen(
                    onSkip = rootViewModel::completeInviteCode,
                    onApply = rootViewModel::completeInviteCode,
                )

                RootStage.Permissions -> PermissionsScreen(
                    onEnable = rootViewModel::completePermissions,
                )

                RootStage.App -> {
                    val activeCapture = rootState.activeCapture
                    if (activeCapture != null) {
                        CaptureSessionScreen(
                            capture = activeCapture,
                            onClose = rootViewModel::dismissCaptureSession,
                        )
                    } else {
                        Scaffold(
                            modifier = Modifier.fillMaxSize(),
                            containerColor = BlueprintBlack,
                            bottomBar = {
                                BlueprintBottomBar(
                                    selectedTab = rootState.selectedTab,
                                    onSelect = rootViewModel::selectTab,
                                )
                            },
                        ) { padding ->
                            Box(
                                modifier = Modifier
                                    .fillMaxSize()
                                    .padding(padding)
                                    .background(BlueprintBlack),
                            ) {
                                AnimatedContent(targetState = rootState.selectedTab, label = "tab-content") { tab ->
                                    when (tab) {
                                        MainTab.Scan -> ScanScreen(
                                            onStartCapture = rootViewModel::startCaptureSession,
                                        )

                                        MainTab.Wallet -> WalletScreen()
                                        MainTab.Profile -> ProfileScreen()
                                    }
                                }

                                Column(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(horizontal = 20.dp, vertical = 16.dp),
                                    verticalArrangement = Arrangement.Bottom,
                                ) {
                                    UploadQueueOverlay(
                                        items = rootState.uploads,
                                        onStartUpload = rootViewModel::startUpload,
                                        onRetry = rootViewModel::retryUpload,
                                        onDismiss = rootViewModel::dismissUpload,
                                        onCancel = rootViewModel::cancelUpload,
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private data class RootTabSpec(
    val tab: MainTab,
    val icon: ImageVector,
    val contentDescription: String,
)

@Composable
private fun BlueprintBottomBar(
    selectedTab: MainTab,
    onSelect: (MainTab) -> Unit,
) {
    val tabs = listOf(
        RootTabSpec(MainTab.Scan, Icons.Rounded.CropFree, "Scan"),
        RootTabSpec(MainTab.Wallet, Icons.Rounded.CreditCard, "Wallet"),
        RootTabSpec(MainTab.Profile, Icons.Rounded.AccountCircle, "Profile"),
    )

    Surface(
        color = BlueprintSurface,
        tonalElevation = 0.dp,
        shadowElevation = 0.dp,
    ) {
        Column(modifier = Modifier.fillMaxWidth()) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(1.dp)
                    .background(BlueprintNavDivider),
            )
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .navigationBarsPadding()
                    .padding(horizontal = 30.dp, vertical = 16.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                tabs.forEach { spec ->
                    val isSelected = spec.tab == selectedTab
                    Box(
                        modifier = Modifier
                            .size(if (isSelected) 68.dp else 56.dp)
                            .clip(CircleShape)
                            .background(if (isSelected) BlueprintNavSelected else Color.Transparent)
                            .border(
                                width = if (isSelected) 1.dp else 0.dp,
                                color = if (isSelected) BlueprintBorder else Color.Transparent,
                                shape = CircleShape,
                            )
                            .clickable(onClick = { onSelect(spec.tab) }),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(
                            imageVector = spec.icon,
                            contentDescription = spec.contentDescription,
                            tint = if (isSelected) BlueprintTextPrimary else BlueprintTextMuted,
                            modifier = Modifier.size(if (isSelected) 32.dp else 28.dp),
                        )
                    }
                }
            }
        }
    }
}
