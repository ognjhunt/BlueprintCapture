package app.blueprint.capture.ui.screens

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.core.content.ContextCompat
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ArrowOutward
import androidx.compose.material.icons.rounded.ArrowUpward
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material.icons.rounded.LocationOn
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
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.hilt.navigation.compose.hiltViewModel
import app.blueprint.capture.data.model.CaptureLaunch
import app.blueprint.capture.data.model.CapturePermissionTone
import app.blueprint.capture.data.model.ScanTarget
import app.blueprint.capture.ui.theme.BlueprintBlack
import app.blueprint.capture.ui.theme.BlueprintBorder
import app.blueprint.capture.ui.theme.BlueprintBorderStrong
import app.blueprint.capture.ui.theme.BlueprintError
import app.blueprint.capture.ui.theme.BlueprintSectionLabel
import app.blueprint.capture.ui.theme.BlueprintSuccess
import app.blueprint.capture.ui.theme.BlueprintBorderStrong
import app.blueprint.capture.ui.theme.BlueprintSurface
import app.blueprint.capture.ui.theme.BlueprintSurfaceRaised
import app.blueprint.capture.ui.theme.BlueprintTeal
import app.blueprint.capture.ui.theme.BlueprintTealDeep
import app.blueprint.capture.ui.theme.BlueprintTextMuted
import app.blueprint.capture.ui.theme.BlueprintTextPrimary
import app.blueprint.capture.ui.theme.BlueprintTextSecondary
import app.blueprint.capture.ui.theme.BlueprintWarning
import coil.compose.SubcomposeAsyncImage
import coil.compose.SubcomposeAsyncImageContent

private enum class SearchParityScreen {
    Search,
    Submit,
}

private data class SearchLocationSuggestion(
    val id: String,
    val title: String,
    val resultAddress: String,
    val recentSubtitle: String,
    val reviewAddress: String,
    val isRecent: Boolean = false,
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ScanScreen(
    onStartCapture: (CaptureLaunch) -> Unit,
    viewModel: ScanViewModel = hiltViewModel(),
    glassesViewModel: GlassesViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsState()
    val locationSuggestions = remember { searchLocationSuggestions() }

    var showGlassesSheet by rememberSaveable { mutableStateOf(false) }

    val context = androidx.compose.ui.platform.LocalContext.current
    val blePermissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestMultiplePermissions(),
    ) {
        // Permissions resolved (granted or denied) — ViewModel handles BLE/mock fallback
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
    var parityScreen by rememberSaveable { mutableStateOf<SearchParityScreen?>(null) }
    var searchQuery by rememberSaveable { mutableStateOf("") }
    var selectedLocationId by rememberSaveable { mutableStateOf<String?>(null) }
    var submissionContext by rememberSaveable { mutableStateOf("") }
    var captureRulesAccepted by rememberSaveable { mutableStateOf(false) }

    val selectedLocation = remember(selectedLocationId) {
        locationSuggestions.firstOrNull { it.id == selectedLocationId }
    }
    val recentLocations = remember(locationSuggestions) {
        locationSuggestions.filter(SearchLocationSuggestion::isRecent)
    }
    val suggestedLocations = remember(searchQuery, locationSuggestions) {
        searchSuggestionsFor(query = searchQuery, suggestions = locationSuggestions)
    }

    fun openSearchFlow() {
        parityScreen = SearchParityScreen.Search
    }

    fun closeSearchFlow() {
        parityScreen = null
    }

    fun startSubmissionFor(location: SearchLocationSuggestion) {
        selectedLocationId = location.id
        parityScreen = SearchParityScreen.Submit
    }

    fun launchCaptureFromSubmission() {
        val location = selectedLocation ?: return
        onStartCapture(
            CaptureLaunch(
                label = location.title,
                categoryLabel = "SPACE REVIEW",
                addressText = location.reviewAddress,
                permissionTone = CapturePermissionTone.Review,
                workflowName = "Space review",
                workflowSteps = listOf(
                    submissionContext.trim().ifBlank {
                        "Capture the public-facing approach, main circulation path, and any repeated high-value zones."
                    },
                ),
                detailChecklist = defaultSubmissionChecklist,
                requestedOutputs = listOf("qualification", "review_intake"),
            ),
        )
        parityScreen = null
        selectedLocationId = null
        searchQuery = ""
        submissionContext = ""
        captureRulesAccepted = false
    }

    BackHandler(enabled = parityScreen != null) {
        when (parityScreen) {
            SearchParityScreen.Submit -> parityScreen = SearchParityScreen.Search
            SearchParityScreen.Search -> closeSearchFlow()
            null -> Unit
        }
    }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(BlueprintBlack)
            .statusBarsPadding(),
        contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 14.dp, bottom = 28.dp),
        verticalArrangement = Arrangement.spacedBy(22.dp),
    ) {
        item {
            ScanHeader(onSearchClick = ::openSearchFlow)
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
                            onClick = { showGlassesSheet = true },
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
            SubmitSpaceCard(onClick = ::openSearchFlow)
        }
    }

    if (parityScreen != null) {
        Dialog(
            onDismissRequest = ::closeSearchFlow,
            properties = DialogProperties(
                usePlatformDefaultWidth = false,
                decorFitsSystemWindows = false,
                dismissOnBackPress = true,
                dismissOnClickOutside = false,
            ),
        ) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(BlueprintBlack),
            ) {
                when (parityScreen) {
                    SearchParityScreen.Search -> SearchParityScreenScreen(
                        query = searchQuery,
                        selectedLocation = selectedLocation,
                        recentLocations = recentLocations,
                        suggestedLocations = suggestedLocations,
                        onQueryChange = { updated ->
                            searchQuery = updated
                            selectedLocationId = null
                        },
                        onCancel = ::closeSearchFlow,
                        onClearQuery = {
                            searchQuery = ""
                            selectedLocationId = null
                        },
                        onSelectLocation = { location ->
                            selectedLocationId = location.id
                        },
                        onSubmitSpace = {
                            selectedLocation?.let(::startSubmissionFor)
                        },
                    )

                    SearchParityScreen.Submit -> {
                        selectedLocation?.let { location ->
                            SubmitSpaceParityScreen(
                                location = location,
                                contextValue = submissionContext,
                                captureRulesAccepted = captureRulesAccepted,
                                onClose = ::closeSearchFlow,
                                onChangeLocation = {
                                    selectedLocationId = null
                                    parityScreen = SearchParityScreen.Search
                                },
                                onContextChange = { submissionContext = it },
                                onAutoFill = {
                                    submissionContext = autoFillContextFor(location)
                                },
                                onCaptureRulesAccepted = { captureRulesAccepted = it },
                                onContinue = ::launchCaptureFromSubmission,
                            )
                        }
                    }

                    null -> Unit
                }
            }
        }
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
                        .clip(androidx.compose.foundation.shape.RoundedCornerShape(999.dp))
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
private fun ScanHeader(
    onSearchClick: () -> Unit,
) {
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
            HeaderActionButton(
                icon = Icons.Rounded.Search,
                contentDescription = "Search",
                onClick = onSearchClick,
            )
            HeaderActionButton(
                icon = Icons.Rounded.Refresh,
                contentDescription = "Refresh",
                onClick = {},
            )
        }
    }
}

@Composable
private fun HeaderActionButton(
    icon: ImageVector,
    contentDescription: String,
    onClick: () -> Unit,
) {
    Box(
        modifier = Modifier
            .size(56.dp)
            .clip(CircleShape)
            .background(BlueprintSurfaceRaised)
            .clickable(onClick = onClick)
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

@Composable
private fun SearchParityScreenScreen(
    query: String,
    selectedLocation: SearchLocationSuggestion?,
    recentLocations: List<SearchLocationSuggestion>,
    suggestedLocations: List<SearchLocationSuggestion>,
    onQueryChange: (String) -> Unit,
    onCancel: () -> Unit,
    onClearQuery: () -> Unit,
    onSelectLocation: (SearchLocationSuggestion) -> Unit,
    onSubmitSpace: () -> Unit,
) {
    val showIdleState = query.isBlank() && selectedLocation == null
    val showSelectedLocationState = selectedLocation != null

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(BlueprintBlack)
            .statusBarsPadding()
            .navigationBarsPadding()
            .padding(horizontal = 22.dp, vertical = 18.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            BlueprintGlyph()
            Text(
                text = "Cancel",
                modifier = Modifier.clickable(onClick = onCancel),
                style = TextStyle(
                    color = BlueprintTextPrimary,
                    fontSize = 25.sp,
                    lineHeight = 30.sp,
                    fontWeight = FontWeight.SemiBold,
                    letterSpacing = (-0.4).sp,
                ),
            )
        }

        Spacer(modifier = Modifier.height(24.dp))

        SearchParityField(
            value = query,
            placeholder = "Mall, store, or address...",
            onValueChange = onQueryChange,
            onClear = onClearQuery,
        )

        when {
            showIdleState -> SearchIdleState(recentLocations = recentLocations, modifier = Modifier.weight(1f))
            showSelectedLocationState -> SearchNoCapturesState(
                location = selectedLocation,
                modifier = Modifier.weight(1f),
                onSubmitSpace = onSubmitSpace,
            )
            else -> SearchResultsState(
                results = suggestedLocations,
                modifier = Modifier.weight(1f),
                onSelectLocation = onSelectLocation,
            )
        }
    }
}

@Composable
private fun SearchIdleState(
    recentLocations: List<SearchLocationSuggestion>,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(top = 28.dp),
        verticalArrangement = Arrangement.SpaceBetween,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 72.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            Box(
                modifier = Modifier
                    .size(116.dp)
                    .clip(CircleShape)
                    .background(Color(0xFF101113)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = Icons.Rounded.LocationOn,
                    contentDescription = null,
                    tint = BlueprintTextMuted.copy(alpha = 0.30f),
                    modifier = Modifier.size(60.dp),
                )
            }
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Text(
                    text = "Find Nearby Opportunities",
                    style = TextStyle(
                        color = BlueprintTextPrimary.copy(alpha = 0.56f),
                        fontSize = 24.sp,
                        lineHeight = 30.sp,
                        fontWeight = FontWeight.SemiBold,
                        letterSpacing = (-0.3).sp,
                    ),
                )
                Text(
                    text = "Search a mall, store, or address to see if there's an active capture job nearby.",
                    modifier = Modifier.widthIn(max = 320.dp),
                    style = TextStyle(
                        color = BlueprintTextMuted.copy(alpha = 0.60f),
                        fontSize = 16.sp,
                        lineHeight = 23.sp,
                        fontWeight = FontWeight.Medium,
                        letterSpacing = (-0.1).sp,
                    ),
                )
            }
        }

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 18.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            recentLocations.forEach { location ->
                RecentLocationRow(location = location)
            }
        }
    }
}

@Composable
private fun SearchResultsState(
    results: List<SearchLocationSuggestion>,
    modifier: Modifier = Modifier,
    onSelectLocation: (SearchLocationSuggestion) -> Unit,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(top = 26.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        Text(
            text = "SUGGESTED LOCATIONS",
            style = TextStyle(
                color = BlueprintSectionLabel,
                fontSize = 12.sp,
                lineHeight = 15.sp,
                fontWeight = FontWeight.ExtraBold,
                letterSpacing = 2.8.sp,
            ),
        )

        if (results.isEmpty()) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(24.dp))
                    .background(Color(0xFF171717))
                    .border(1.dp, BlueprintBorder, RoundedCornerShape(24.dp))
                    .padding(horizontal = 22.dp, vertical = 28.dp),
            ) {
                Text(
                    text = "No matching locations yet. Try a mall, store, or full address.",
                    style = TextStyle(
                        color = BlueprintTextMuted.copy(alpha = 0.72f),
                        fontSize = 16.sp,
                        lineHeight = 22.sp,
                        fontWeight = FontWeight.Medium,
                    ),
                )
            }
        } else {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(24.dp))
                    .background(Color(0xFF171717))
                    .border(1.dp, BlueprintBorder, RoundedCornerShape(24.dp)),
            ) {
                results.forEachIndexed { index, location ->
                    SearchLocationResultRow(
                        location = location,
                        onClick = { onSelectLocation(location) },
                    )
                    if (index < results.lastIndex) {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(start = 154.dp, end = 22.dp)
                                .height(1.dp)
                                .background(BlueprintBorder.copy(alpha = 0.78f)),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun SearchNoCapturesState(
    location: SearchLocationSuggestion?,
    modifier: Modifier = Modifier,
    onSubmitSpace: () -> Unit,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(top = 80.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            modifier = Modifier
                .size(154.dp)
                .clip(CircleShape)
                .background(Color(0xFF131313)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = Icons.Rounded.LocationOn,
                contentDescription = null,
                tint = BlueprintTextMuted.copy(alpha = 0.34f),
                modifier = Modifier.size(78.dp),
            )
        }

        Spacer(modifier = Modifier.height(34.dp))

        Text(
            text = "No captures here yet",
            style = TextStyle(
                color = BlueprintTextPrimary.copy(alpha = 0.56f),
                fontSize = 25.sp,
                lineHeight = 30.sp,
                fontWeight = FontWeight.SemiBold,
                letterSpacing = (-0.4).sp,
            ),
        )

        Spacer(modifier = Modifier.height(12.dp))

        Text(
            text = "There's no active capture job registered near ${location?.title.orEmpty()}.",
            modifier = Modifier.widthIn(max = 340.dp),
            style = TextStyle(
                color = BlueprintTextMuted.copy(alpha = 0.62f),
                fontSize = 17.sp,
                lineHeight = 24.sp,
                fontWeight = FontWeight.Medium,
                letterSpacing = (-0.1).sp,
            ),
        )

        Spacer(modifier = Modifier.height(56.dp))

        SubmitSpaceReviewCard(
            title = "Submit This Space for Review",
            subtitle = "Nominate it to become an approved capture job",
            onClick = onSubmitSpace,
        )
    }
}

@Composable
private fun SearchParityField(
    value: String,
    placeholder: String,
    onValueChange: (String) -> Unit,
    onClear: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(82.dp)
            .clip(RoundedCornerShape(28.dp))
            .background(Color(0xFF1B1B1C))
            .border(
                width = 1.5.dp,
                color = if (value.isBlank()) BlueprintTeal.copy(alpha = 0.50f) else BlueprintBorderStrong,
                shape = RoundedCornerShape(28.dp),
            )
            .padding(horizontal = 22.dp),
        horizontalArrangement = Arrangement.spacedBy(16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            imageVector = Icons.Rounded.Search,
            contentDescription = null,
            tint = BlueprintTeal,
            modifier = Modifier.size(32.dp),
        )

        Box(
            modifier = Modifier.weight(1f),
            contentAlignment = Alignment.CenterStart,
        ) {
            if (value.isBlank()) {
                Text(
                    text = placeholder,
                    style = TextStyle(
                        color = BlueprintTextMuted.copy(alpha = 0.50f),
                        fontSize = 27.sp,
                        lineHeight = 31.sp,
                        fontWeight = FontWeight.Medium,
                        letterSpacing = (-0.5).sp,
                    ),
                )
            }

            BasicTextField(
                value = value,
                onValueChange = onValueChange,
                singleLine = true,
                cursorBrush = SolidColor(BlueprintTextPrimary),
                textStyle = TextStyle(
                    color = BlueprintTextPrimary,
                    fontSize = 28.sp,
                    lineHeight = 32.sp,
                    fontWeight = FontWeight.Medium,
                    letterSpacing = (-0.7).sp,
                ),
                modifier = Modifier.fillMaxWidth(),
            )
        }

        if (value.isNotBlank()) {
            Box(
                modifier = Modifier
                    .size(40.dp)
                    .clip(CircleShape)
                    .background(Color(0xFF3E3E42))
                    .clickable(onClick = onClear),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = Icons.Rounded.Close,
                    contentDescription = "Clear search",
                    tint = BlueprintBlack,
                    modifier = Modifier.size(24.dp),
                )
            }
        }
    }
}

@Composable
private fun RecentLocationRow(
    location: SearchLocationSuggestion,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(24.dp))
            .background(Color(0xFF171717))
            .border(1.dp, BlueprintBorder.copy(alpha = 0.70f), RoundedCornerShape(24.dp))
            .padding(horizontal = 22.dp, vertical = 18.dp),
        horizontalArrangement = Arrangement.spacedBy(16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            imageVector = Icons.Rounded.Search,
            contentDescription = null,
            tint = BlueprintTextMuted.copy(alpha = 0.78f),
            modifier = Modifier.size(32.dp),
        )

        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(
                text = location.title,
                style = TextStyle(
                    color = BlueprintTextPrimary.copy(alpha = 0.72f),
                    fontSize = 25.sp,
                    lineHeight = 28.sp,
                    fontWeight = FontWeight.Medium,
                    letterSpacing = (-0.4).sp,
                ),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = location.recentSubtitle,
                style = TextStyle(
                    color = BlueprintTextMuted.copy(alpha = 0.70f),
                    fontSize = 19.sp,
                    lineHeight = 22.sp,
                    fontWeight = FontWeight.Medium,
                    letterSpacing = (-0.2).sp,
                ),
            )
        }

        Icon(
            imageVector = Icons.Rounded.ArrowOutward,
            contentDescription = null,
            tint = BlueprintTextMuted.copy(alpha = 0.42f),
            modifier = Modifier.size(22.dp),
        )
    }
}

@Composable
private fun SearchLocationResultRow(
    location: SearchLocationSuggestion,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 18.dp, vertical = 18.dp),
        horizontalArrangement = Arrangement.spacedBy(18.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(54.dp)
                .clip(RoundedCornerShape(16.dp))
                .background(BlueprintTealDeep.copy(alpha = 0.92f)),
            contentAlignment = Alignment.Center,
        ) {
            Box(
                modifier = Modifier
                    .size(28.dp)
                    .clip(CircleShape)
                    .background(BlueprintTextPrimary),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = Icons.Rounded.LocationOn,
                    contentDescription = null,
                    tint = BlueprintTealDeep,
                    modifier = Modifier.size(18.dp),
                )
            }
        }

        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(
                text = location.title,
                style = TextStyle(
                    color = BlueprintTextPrimary,
                    fontSize = 22.sp,
                    lineHeight = 27.sp,
                    fontWeight = FontWeight.Bold,
                    letterSpacing = (-0.4).sp,
                ),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = location.resultAddress,
                style = TextStyle(
                    color = BlueprintTextMuted.copy(alpha = 0.82f),
                    fontSize = 17.sp,
                    lineHeight = 22.sp,
                    fontWeight = FontWeight.Medium,
                    letterSpacing = (-0.1).sp,
                ),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }

        Icon(
            imageVector = Icons.Rounded.ChevronRight,
            contentDescription = null,
            tint = BlueprintTextMuted.copy(alpha = 0.36f),
            modifier = Modifier.size(36.dp),
        )
    }
}

@Composable
private fun SubmitSpaceReviewCard(
    title: String,
    subtitle: String,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(26.dp))
            .background(Color(0xFF171717))
            .border(1.dp, BlueprintTeal.copy(alpha = 0.36f), RoundedCornerShape(26.dp))
            .clickable(onClick = onClick),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .padding(vertical = 18.dp)
                .width(4.dp)
                .height(156.dp)
                .clip(RoundedCornerShape(3.dp))
                .background(BlueprintTeal),
        )

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 18.dp, vertical = 26.dp),
            horizontalArrangement = Arrangement.spacedBy(18.dp),
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
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Text(
                    text = title,
                    style = TextStyle(
                        color = BlueprintTextPrimary,
                        fontSize = 20.sp,
                        lineHeight = 26.sp,
                        fontWeight = FontWeight.ExtraBold,
                        letterSpacing = (-0.4).sp,
                    ),
                )
                Text(
                    text = subtitle,
                    style = TextStyle(
                        color = BlueprintTextMuted.copy(alpha = 0.80f),
                        fontSize = 17.sp,
                        lineHeight = 22.sp,
                        fontWeight = FontWeight.Medium,
                        letterSpacing = (-0.1).sp,
                    ),
                )
            }

            Icon(
                imageVector = Icons.Rounded.ChevronRight,
                contentDescription = null,
                tint = BlueprintTextMuted.copy(alpha = 0.38f),
                modifier = Modifier.size(34.dp),
            )
        }
    }
}

@Composable
private fun SubmitSpaceParityScreen(
    location: SearchLocationSuggestion,
    contextValue: String,
    captureRulesAccepted: Boolean,
    onClose: () -> Unit,
    onChangeLocation: () -> Unit,
    onContextChange: (String) -> Unit,
    onAutoFill: () -> Unit,
    onCaptureRulesAccepted: (Boolean) -> Unit,
    onContinue: () -> Unit,
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(BlueprintBlack),
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .statusBarsPadding()
                .padding(horizontal = 22.dp, vertical = 18.dp)
                .padding(bottom = 148.dp),
            verticalArrangement = Arrangement.spacedBy(34.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End,
            ) {
                RoundIconButton(
                    icon = Icons.Rounded.Close,
                    contentDescription = "Close",
                    size = 58.dp,
                    onClick = onClose,
                )
            }

            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(
                    text = "Submit a Space",
                    style = TextStyle(
                        color = BlueprintTextPrimary,
                        fontSize = 46.sp,
                        lineHeight = 48.sp,
                        fontWeight = FontWeight.ExtraBold,
                        letterSpacing = (-1.2).sp,
                    ),
                )
                Text(
                    text = "Tell us where the space is, why it matters, and confirm capture guardrails.",
                    style = TextStyle(
                        color = BlueprintTextMuted.copy(alpha = 0.84f),
                        fontSize = 18.sp,
                        lineHeight = 25.sp,
                        fontWeight = FontWeight.Medium,
                        letterSpacing = (-0.15).sp,
                    ),
                )
            }

            Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                SectionLabel("LOCATION")
                SelectedLocationCard(location = location)
                Row(
                    modifier = Modifier.clickable(onClick = onChangeLocation),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        imageVector = Icons.Rounded.Refresh,
                        contentDescription = null,
                        tint = BlueprintTeal,
                        modifier = Modifier.size(22.dp),
                    )
                    Text(
                        text = "Change location",
                        style = TextStyle(
                            color = BlueprintTeal,
                            fontSize = 18.sp,
                            lineHeight = 23.sp,
                            fontWeight = FontWeight.SemiBold,
                            letterSpacing = (-0.2).sp,
                        ),
                    )
                }
            }

            Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                SectionLabel("CONTEXT")
                ContextCard(
                    value = contextValue,
                    onValueChange = onContextChange,
                    onAutoFill = onAutoFill,
                )
            }

            Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                SectionLabel("BEFORE YOU RECORD")
                RulesCard(
                    captureRulesAccepted = captureRulesAccepted,
                    onCaptureRulesAccepted = onCaptureRulesAccepted,
                )
            }
        }

        Box(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .background(
                    brush = Brush.verticalGradient(
                        colors = listOf(
                            Color.Transparent,
                            BlueprintBlack.copy(alpha = 0.88f),
                            BlueprintBlack,
                        ),
                    ),
                )
                .navigationBarsPadding()
                .padding(horizontal = 22.dp, vertical = 18.dp),
        ) {
            val continueEnabled = captureRulesAccepted && contextValue.isNotBlank()
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(82.dp)
                    .clip(RoundedCornerShape(24.dp))
                    .background(if (continueEnabled) BlueprintTextPrimary else Color(0xFF171717))
                    .border(
                        width = if (continueEnabled) 0.dp else 1.dp,
                        color = BlueprintBorder,
                        shape = RoundedCornerShape(24.dp),
                    )
                    .clickable(enabled = continueEnabled, onClick = onContinue),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = "Continue to Capture",
                    style = TextStyle(
                        color = if (continueEnabled) BlueprintBlack else BlueprintTextMuted.copy(alpha = 0.42f),
                        fontSize = 23.sp,
                        lineHeight = 27.sp,
                        fontWeight = FontWeight.ExtraBold,
                        letterSpacing = (-0.4).sp,
                    ),
                )
            }
        }
    }
}

@Composable
private fun BlueprintGlyph() {
    Box(
        modifier = Modifier
            .size(42.dp)
            .clip(RoundedCornerShape(8.dp))
            .background(BlueprintTeal),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = "B",
            style = TextStyle(
                color = BlueprintBlack,
                fontSize = 24.sp,
                lineHeight = 24.sp,
                fontWeight = FontWeight.ExtraBold,
            ),
        )
    }
}

@Composable
private fun RoundIconButton(
    icon: ImageVector,
    contentDescription: String,
    size: androidx.compose.ui.unit.Dp,
    onClick: () -> Unit,
) {
    Box(
        modifier = Modifier
            .size(size)
            .clip(CircleShape)
            .background(Color(0xFF151517))
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = contentDescription,
            tint = BlueprintTextPrimary.copy(alpha = 0.86f),
            modifier = Modifier.size(size / 2.2f),
        )
    }
}

@Composable
private fun SectionLabel(text: String) {
    Text(
        text = text,
        style = TextStyle(
            color = BlueprintSectionLabel,
            fontSize = 14.sp,
            lineHeight = 17.sp,
            fontWeight = FontWeight.ExtraBold,
            letterSpacing = 3.0.sp,
        ),
    )
}

@Composable
private fun SelectedLocationCard(
    location: SearchLocationSuggestion,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(26.dp))
            .background(Color(0xFF171717))
            .border(1.dp, BlueprintTeal.copy(alpha = 0.36f), RoundedCornerShape(26.dp))
            .padding(horizontal = 18.dp, vertical = 18.dp),
        horizontalArrangement = Arrangement.spacedBy(18.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(54.dp)
                .clip(RoundedCornerShape(16.dp))
                .background(BlueprintTealDeep),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = Icons.Rounded.LocationOn,
                contentDescription = null,
                tint = BlueprintTeal,
                modifier = Modifier.size(28.dp),
            )
        }

        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Text(
                text = location.reviewAddress,
                style = TextStyle(
                    color = BlueprintTextPrimary,
                    fontSize = 22.sp,
                    lineHeight = 30.sp,
                    fontWeight = FontWeight.Bold,
                    letterSpacing = (-0.5).sp,
                ),
            )
            Text(
                text = "From your search",
                style = TextStyle(
                    color = BlueprintTeal,
                    fontSize = 16.sp,
                    lineHeight = 21.sp,
                    fontWeight = FontWeight.Medium,
                ),
            )
        }
    }
}

@Composable
private fun ContextCard(
    value: String,
    onValueChange: (String) -> Unit,
    onAutoFill: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(28.dp))
            .background(Color(0xFF171717))
            .border(1.dp, BlueprintBorder, RoundedCornerShape(28.dp))
            .padding(horizontal = 20.dp, vertical = 20.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.Top,
        ) {
            Text(
                text = "Why is this space\nworth reviewing?",
                style = TextStyle(
                    color = BlueprintTextPrimary,
                    fontSize = 24.sp,
                    lineHeight = 31.sp,
                    fontWeight = FontWeight.Bold,
                    letterSpacing = (-0.5).sp,
                ),
            )

            Row(
                modifier = Modifier
                    .clip(RoundedCornerShape(22.dp))
                    .background(BlueprintTealDeep)
                    .clickable(onClick = onAutoFill)
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    imageVector = Icons.Rounded.AutoAwesome,
                    contentDescription = null,
                    tint = BlueprintTeal,
                    modifier = Modifier.size(18.dp),
                )
                Text(
                    text = "Auto-fill",
                    style = TextStyle(
                        color = BlueprintTeal,
                        fontSize = 16.sp,
                        lineHeight = 20.sp,
                        fontWeight = FontWeight.Bold,
                    ),
                )
            }
        }

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 168.dp),
        ) {
            if (value.isBlank()) {
                Text(
                    text = "Tell us what makes this space valuable to capture...",
                    style = TextStyle(
                        color = BlueprintTextMuted.copy(alpha = 0.54f),
                        fontSize = 20.sp,
                        lineHeight = 29.sp,
                        fontWeight = FontWeight.Medium,
                        letterSpacing = (-0.2).sp,
                    ),
                )
            }

            BasicTextField(
                value = value,
                onValueChange = onValueChange,
                cursorBrush = SolidColor(BlueprintTextPrimary),
                textStyle = TextStyle(
                    color = BlueprintTextPrimary,
                    fontSize = 20.sp,
                    lineHeight = 29.sp,
                    fontWeight = FontWeight.Medium,
                    letterSpacing = (-0.2).sp,
                ),
                modifier = Modifier.fillMaxWidth(),
            )
        }

        Text(
            text = "Example: active loading area, repeated congestion, strong coverage potential, or buyer-requested zone.",
            style = TextStyle(
                color = BlueprintTextMuted.copy(alpha = 0.58f),
                fontSize = 14.sp,
                lineHeight = 21.sp,
                fontWeight = FontWeight.Medium,
                letterSpacing = (-0.1).sp,
            ),
        )
    }
}

@Composable
private fun RulesCard(
    captureRulesAccepted: Boolean,
    onCaptureRulesAccepted: (Boolean) -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(28.dp))
            .background(Color(0xFF171717))
            .border(1.dp, BlueprintBorder, RoundedCornerShape(28.dp)),
    ) {
        val rules = listOf(
            "Capture only common areas you can visibly access.",
            "Avoid faces, screens, paperwork, and posted private information.",
            "Respect restricted zones and any on-site staff direction.",
        )

        rules.forEachIndexed { index, rule ->
            RuleRow(text = rule)
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(start = 72.dp, end = 22.dp)
                    .height(if (index == rules.lastIndex) 1.dp else 1.dp)
                    .background(BlueprintBorder),
            )
        }

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 18.dp, vertical = 18.dp),
            horizontalArrangement = Arrangement.spacedBy(16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = "I can follow these capture rules",
                modifier = Modifier.weight(1f),
                style = TextStyle(
                    color = BlueprintTextPrimary,
                    fontSize = 22.sp,
                    lineHeight = 28.sp,
                    fontWeight = FontWeight.Bold,
                    letterSpacing = (-0.4).sp,
                ),
            )
            ParityToggle(
                checked = captureRulesAccepted,
                onCheckedChange = onCaptureRulesAccepted,
            )
        }
    }
}

@Composable
private fun RuleRow(
    text: String,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 18.dp, vertical = 18.dp),
        horizontalArrangement = Arrangement.spacedBy(16.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Box(
            modifier = Modifier
                .padding(top = 3.dp)
                .size(34.dp)
                .clip(CircleShape)
                .background(BlueprintSuccess),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = Icons.Rounded.Check,
                contentDescription = null,
                tint = BlueprintBlack,
                modifier = Modifier.size(22.dp),
            )
        }

        Text(
            text = text,
            modifier = Modifier.weight(1f),
            style = TextStyle(
                color = BlueprintTextMuted.copy(alpha = 0.90f),
                fontSize = 20.sp,
                lineHeight = 31.sp,
                fontWeight = FontWeight.Medium,
                letterSpacing = (-0.2).sp,
            ),
        )
    }
}

@Composable
private fun ParityToggle(
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
) {
    val trackColor = if (checked) BlueprintSuccess else Color(0xFF64646A)
    val knobAlignment = if (checked) Alignment.CenterEnd else Alignment.CenterStart
    Box(
        modifier = Modifier
            .size(width = 94.dp, height = 52.dp)
            .clip(RoundedCornerShape(26.dp))
            .background(trackColor)
            .padding(4.dp)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                onClick = { onCheckedChange(!checked) },
            ),
        contentAlignment = knobAlignment,
    ) {
        Box(
            modifier = Modifier
                .size(44.dp)
                .clip(CircleShape)
                .background(BlueprintTextPrimary),
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
        categoryLabel = categoryLabel,
        addressText = addressText,
        payoutText = payoutText,
        distanceText = distanceText,
        estimatedMinutes = estimatedMinutes,
        permissionTone = permissionTone,
        imageUrl = imageUrl,
        detailChecklist = detailChecklist,
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

private val defaultSubmissionChecklist = listOf(
    "Capture only common areas you can visibly access.",
    "Avoid faces, screens, paperwork, and posted private information.",
    "Respect restricted zones and any on-site staff direction.",
)

private fun autoFillContextFor(location: SearchLocationSuggestion): String {
    return "${location.title} looks like a strong review candidate because it appears to be a public-facing, repeatable location with meaningful circulation paths and likely coverage value around the main entry and service areas."
}

private fun searchSuggestionsFor(
    query: String,
    suggestions: List<SearchLocationSuggestion>,
): List<SearchLocationSuggestion> {
    val trimmedQuery = query.trim()
    if (trimmedQuery.isBlank()) return emptyList()

    return suggestions
        .filter { suggestion ->
            suggestion.title.contains(trimmedQuery, ignoreCase = true) ||
                suggestion.resultAddress.contains(trimmedQuery, ignoreCase = true) ||
                suggestion.reviewAddress.contains(trimmedQuery, ignoreCase = true)
        }
        .sortedBy { suggestion ->
            val titleIndex = suggestion.title.indexOf(trimmedQuery, ignoreCase = true)
            if (titleIndex >= 0) titleIndex else Int.MAX_VALUE
        }
}

private fun searchLocationSuggestions(): List<SearchLocationSuggestion> = listOf(
    SearchLocationSuggestion(
        id = "whole-foods",
        title = "Whole Foods Market",
        resultAddress = "621 Broad St, Durham, NC 27705, Unit...",
        recentSubtitle = "Durham, NC",
        reviewAddress = "Whole Foods Market, Broad St, Durham, NC",
    ),
    SearchLocationSuggestion(
        id = "wheels-durham",
        title = "Wheels Durham",
        resultAddress = "715 N Hoover Rd, Durham, NC 27703,...",
        recentSubtitle = "Durham, NC",
        reviewAddress = "Wheels Durham, Hoover Rd, Durham, NC",
    ),
    SearchLocationSuggestion(
        id = "whetstone",
        title = "Whetstone Apartments",
        resultAddress = "501 Willard St, Durham, NC 27701, Unit...",
        recentSubtitle = "Durham, NC",
        reviewAddress = "Whetstone Apartments, Willard St, Durham, NC",
    ),
    SearchLocationSuggestion(
        id = "wheat",
        title = "Wheat 麦茶 _ Durham",
        resultAddress = "810 Ninth St, Ste 130, Durham, NC 277...",
        recentSubtitle = "Durham, NC",
        reviewAddress = "Wheat 麦茶 _ Durham, Ninth St, Durham, NC",
    ),
    SearchLocationSuggestion(
        id = "jerk",
        title = "Where’s the Jerk",
        resultAddress = "5400 S Miami Blvd, Ste 136, Durham, N...",
        recentSubtitle = "Durham, NC",
        reviewAddress = "Where’s the Jerk, Miami Blvd, Durham, NC",
    ),
    SearchLocationSuggestion(
        id = "whippoorwill",
        title = "Whippoorwill Park",
        resultAddress = "1632 Rowemont Dr, Durham, NC 27705...",
        recentSubtitle = "Durham, NC",
        reviewAddress = "Whippoorwill Park, Rowemont Dr, Durham, NC",
    ),
    SearchLocationSuggestion(
        id = "whitted",
        title = "Whitted School",
        resultAddress = "1210 Sawyer St, Durham, NC 27707, Un...",
        recentSubtitle = "Durham, NC",
        reviewAddress = "Whitted School, Sawyer St, Durham, NC",
    ),
    SearchLocationSuggestion(
        id = "mad-kicks",
        title = "Mad Kicks",
        resultAddress = "Durham, NC",
        recentSubtitle = "Durham, NC",
        reviewAddress = "Mad Kicks, Durham, NC",
        isRecent = true,
    ),
    SearchLocationSuggestion(
        id = "harris-teeter",
        title = "Harris Teeter",
        resultAddress = "Durham, NC",
        recentSubtitle = "Durham, NC",
        reviewAddress = "Harris Teeter, Durham, NC",
        isRecent = true,
    ),
    SearchLocationSuggestion(
        id = "gym-tacos",
        title = "Gym Tacos",
        resultAddress = "Durham, NC",
        recentSubtitle = "Durham, NC",
        reviewAddress = "Gym Tacos, Durham, NC",
        isRecent = true,
    ),
)
