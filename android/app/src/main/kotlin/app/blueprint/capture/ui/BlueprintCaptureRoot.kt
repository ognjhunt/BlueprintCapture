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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.blueprint.capture.data.config.LocalConfigProvider
import app.blueprint.capture.data.model.DemoData
import app.blueprint.capture.ui.components.UploadQueueOverlay
import app.blueprint.capture.ui.screens.AuthScreen
import app.blueprint.capture.ui.screens.OnboardingScreen
import app.blueprint.capture.ui.screens.ProfileScreen
import app.blueprint.capture.ui.screens.ScanScreen
import app.blueprint.capture.ui.screens.WalletScreen
import app.blueprint.capture.ui.theme.BlueprintBlack
import app.blueprint.capture.ui.theme.BlueprintSurface

private enum class RootStage {
    Onboarding,
    Auth,
    App,
}

private enum class MainTab {
    Scan,
    Wallet,
    Profile,
}

@Composable
fun BlueprintCaptureRoot(
    configProvider: LocalConfigProvider = LocalConfigProvider(),
) {
    val config = remember { configProvider.current() }
    var rootStage by rememberSaveable { mutableStateOf(RootStage.Onboarding) }
    var selectedTab by rememberSaveable { mutableStateOf(MainTab.Scan) }
    val uploads = remember { mutableStateListOf(*DemoData.uploadQueue.toTypedArray()) }

    Surface(
        modifier = Modifier.fillMaxSize(),
        color = BlueprintBlack,
    ) {
        Crossfade(targetState = rootStage, label = "root-stage") { stage ->
            when (stage) {
                RootStage.Onboarding -> OnboardingScreen(
                    onContinue = { rootStage = RootStage.Auth },
                )
                RootStage.Auth -> AuthScreen(
                    configSummary = "Firebase ${if (config.hasBackend) "and backend ready" else "ready; backend URL still empty"}",
                    onAuthenticated = { rootStage = RootStage.App },
                )
                RootStage.App -> {
                    Scaffold(
                        modifier = Modifier.fillMaxSize(),
                        containerColor = BlueprintBlack,
                        bottomBar = {
                            NavigationBar(
                                containerColor = BlueprintSurface,
                                tonalElevation = 0.dp,
                            ) {
                                NavigationBarItem(
                                    selected = selectedTab == MainTab.Scan,
                                    onClick = { selectedTab = MainTab.Scan },
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
                                    selected = selectedTab == MainTab.Wallet,
                                    onClick = { selectedTab = MainTab.Wallet },
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
                                    selected = selectedTab == MainTab.Profile,
                                    onClick = { selectedTab = MainTab.Profile },
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
                            AnimatedContent(targetState = selectedTab, label = "tab-content") { tab ->
                                when (tab) {
                                    MainTab.Scan -> ScanScreen(
                                        targets = DemoData.scanTargets,
                                        configSummary = config.backendBaseUrl.ifBlank { "Backend URL not set yet" },
                                        onStartCapture = {
                                            if (uploads.none { item -> item.id == "upload-new" }) {
                                                uploads.add(
                                                    0,
                                                    DemoData.uploadQueue.first().copy(
                                                        id = "upload-new",
                                                        label = "Android phone capture",
                                                        progress = 0.12f,
                                                    ),
                                                )
                                            }
                                        },
                                    )
                                    MainTab.Wallet -> WalletScreen(hasBackend = config.hasBackend)
                                    MainTab.Profile -> ProfileScreen(
                                        packageName = "Public.BlueprintCapture.Android",
                                        firebaseProject = "blueprint-8c1ca",
                                    )
                                }
                            }

                            Column(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 20.dp, vertical = 16.dp),
                                verticalArrangement = Arrangement.Bottom,
                            ) {
                                UploadQueueOverlay(items = uploads)
                                Box(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(top = 12.dp)
                                        .background(BlueprintSurface),
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}
