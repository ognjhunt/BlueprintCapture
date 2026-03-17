package app.blueprint.capture.ui

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.Crossfade
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AccountCircle
import androidx.compose.material.icons.rounded.CreditCard
import androidx.compose.material.icons.rounded.MyLocation
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import app.blueprint.capture.data.config.LocalConfigProvider
import app.blueprint.capture.data.model.MainTab
import app.blueprint.capture.data.model.RootStage
import app.blueprint.capture.ui.components.UploadQueueOverlay
import app.blueprint.capture.ui.screens.AuthScreen
import app.blueprint.capture.ui.screens.CaptureSessionScreen
import app.blueprint.capture.ui.screens.OnboardingScreen
import app.blueprint.capture.ui.screens.ProfileScreen
import app.blueprint.capture.ui.screens.ScanScreen
import app.blueprint.capture.ui.screens.WalletScreen
import app.blueprint.capture.ui.theme.BlueprintBlack
import app.blueprint.capture.ui.theme.BlueprintSurface

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
                    configSummary = if (config.hasBackend) {
                        "Firebase auth is live and backend config is present for creator APIs."
                    } else {
                        "Firebase auth is live. Add backend config to unlock creator APIs and payouts."
                    },
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
                                NavigationBar(
                                    containerColor = BlueprintSurface,
                                    tonalElevation = 0.dp,
                                ) {
                                    NavigationBarItem(
                                        selected = rootState.selectedTab == MainTab.Scan,
                                        onClick = { rootViewModel.selectTab(MainTab.Scan) },
                                        icon = {
                                            Icon(
                                                imageVector = Icons.Rounded.MyLocation,
                                                contentDescription = "Scan",
                                                modifier = Modifier.size(24.dp),
                                            )
                                        },
                                        label = { Text("Scan") },
                                    )
                                    NavigationBarItem(
                                        selected = rootState.selectedTab == MainTab.Wallet,
                                        onClick = { rootViewModel.selectTab(MainTab.Wallet) },
                                        icon = {
                                            Icon(
                                                imageVector = Icons.Rounded.CreditCard,
                                                contentDescription = "Wallet",
                                                modifier = Modifier.size(24.dp),
                                            )
                                        },
                                        label = { Text("Wallet") },
                                    )
                                    NavigationBarItem(
                                        selected = rootState.selectedTab == MainTab.Profile,
                                        onClick = { rootViewModel.selectTab(MainTab.Profile) },
                                        icon = {
                                            Icon(
                                                imageVector = Icons.Rounded.AccountCircle,
                                                contentDescription = "Profile",
                                                modifier = Modifier.size(24.dp),
                                            )
                                        },
                                        label = { Text("Profile") },
                                    )
                                }
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
