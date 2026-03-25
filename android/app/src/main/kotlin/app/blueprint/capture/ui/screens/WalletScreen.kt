package app.blueprint.capture.ui.screens

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AccountBalanceWallet
import androidx.compose.material.icons.rounded.AttachMoney
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.Schedule
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import app.blueprint.capture.data.capture.CaptureHistoryEntry
import app.blueprint.capture.data.capture.CaptureSubmissionStage
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import app.blueprint.capture.ui.theme.BlueprintBlack
import app.blueprint.capture.ui.theme.BlueprintBorder
import app.blueprint.capture.ui.theme.BlueprintSuccess
import app.blueprint.capture.ui.theme.BlueprintSurface
import app.blueprint.capture.ui.theme.BlueprintSurfaceRaised
import app.blueprint.capture.ui.theme.BlueprintTeal
import app.blueprint.capture.ui.theme.BlueprintTextMuted
import app.blueprint.capture.ui.theme.BlueprintTextPrimary
import kotlin.math.max

private enum class WalletLedgerTab(val label: String) {
    Payouts("Payouts"),
    Cashouts("Cashouts"),
    History("History"),
}

@Composable
fun WalletScreen(
    viewModel: WalletViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsState()
    var selectedTabIndex by rememberSaveable { mutableIntStateOf(0) }
    var showPayouts by rememberSaveable { mutableStateOf(false) }

    if (showPayouts) {
        PayoutsScreen(onBack = { showPayouts = false })
        return
    }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(BlueprintBlack)
            .statusBarsPadding(),
        contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 14.dp, bottom = 32.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        item {
            WalletHeader(
                isRefreshing = state.isRefreshing,
                onRefresh = viewModel::refresh,
            )
        }

        if (state.showPayoutBanner) {
            item {
                WalletStatusBanner(
                    title = state.payoutBannerTitle,
                    subtitle = state.payoutBannerBody,
                    actionLabel = state.payoutBannerActionLabel,
                    onAction = if (state.payoutBannerActionLabel != null) {
                        { showPayouts = true }
                    } else null,
                )
            }
        }

        item {
            WalletBalanceCard(state = state)
        }

        item {
            WalletPendingRow(
                totalCaptures = state.totalCaptures,
                pendingReviewCount = state.pendingReviewCount,
                cashoutEnabled = state.cashoutEnabled,
                onCashout = { showPayouts = true },
            )
        }

        item {
            WalletLedgerPicker(
                selectedIndex = selectedTabIndex,
                onSelect = { selectedTabIndex = it },
            )
        }

        item {
            WalletLedgerContent(
                selectedTab = WalletLedgerTab.entries[selectedTabIndex],
                payoutEntries = state.payoutEntries,
                historyEntries = state.historyEntries,
                isLoading = state.isLedgerLoading,
            )
        }
    }
}

@Composable
private fun WalletHeader(
    isRefreshing: Boolean,
    onRefresh: () -> Unit,
) {
    val rotation by animateFloatAsState(
        targetValue = if (isRefreshing) 180f else 0f,
        animationSpec = tween(durationMillis = 900),
        label = "wallet-refresh-rotation",
    )

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
                text = "Wallet",
                style = TextStyle(
                    color = BlueprintTextPrimary,
                    fontSize = 52.sp,
                    lineHeight = 54.sp,
                    fontWeight = FontWeight.ExtraBold,
                    letterSpacing = (-1.3).sp,
                ),
            )
            Text(
                text = "Your earnings and payout history",
                style = TextStyle(
                    color = BlueprintTextMuted,
                    fontSize = 16.sp,
                    lineHeight = 21.sp,
                    fontWeight = FontWeight.Medium,
                ),
            )
        }

        Box(
            modifier = Modifier
                .padding(top = 16.dp)
                .size(56.dp)
                .clip(CircleShape)
                .background(BlueprintSurfaceRaised)
                .border(1.dp, BlueprintBorder, CircleShape)
                .clickable(onClick = onRefresh),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = Icons.Rounded.Refresh,
                contentDescription = "Refresh wallet",
                tint = if (isRefreshing) BlueprintTeal else Color(0xFF8E939A),
                modifier = Modifier
                    .size(28.dp)
                    .graphicsLayer { rotationZ = rotation },
            )
        }
    }
}

@Composable
private fun WalletStatusBanner(
    title: String,
    subtitle: String,
    actionLabel: String? = null,
    onAction: (() -> Unit)? = null,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(IntrinsicSize.Min)
            .clip(RoundedCornerShape(22.dp))
            .background(Color(0xFF151718))
            .border(1.dp, BlueprintTeal.copy(alpha = 0.24f), RoundedCornerShape(22.dp)),
    ) {
        Box(
            modifier = Modifier
                .fillMaxHeight()
                .width(4.dp)
                .background(BlueprintTeal),
        )

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 18.dp, vertical = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                imageVector = Icons.Rounded.Lock,
                contentDescription = null,
                tint = BlueprintTeal,
                modifier = Modifier.size(24.dp),
            )

            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(3.dp),
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

            if (actionLabel != null && onAction != null) {
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(12.dp))
                        .background(BlueprintTeal.copy(alpha = 0.18f))
                        .border(1.dp, BlueprintTeal.copy(alpha = 0.35f), RoundedCornerShape(12.dp))
                        .clickable(onClick = onAction)
                        .padding(horizontal = 14.dp, vertical = 9.dp),
                ) {
                    Text(
                        text = actionLabel,
                        color = BlueprintTeal,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.SemiBold,
                    )
                }
            }
        }
    }
}

@Composable
private fun WalletBalanceCard(
    state: WalletUiState,
) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(188.dp)
            .clip(RoundedCornerShape(22.dp))
            .background(
                Brush.linearGradient(
                    colors = listOf(Color(0xFF1A1A1C), Color(0xFF101112)),
                ),
            )
            .border(1.dp, Color.White.copy(alpha = 0.08f), RoundedCornerShape(22.dp)),
    ) {
        Box(
            modifier = Modifier
                .size(262.dp)
                .align(Alignment.TopEnd)
                .graphicsLayer {
                    translationX = 90f
                    translationY = -70f
                }
                .clip(CircleShape)
                .background(BlueprintTeal.copy(alpha = 0.09f)),
        )

        Box(
            modifier = Modifier
                .size(184.dp)
                .align(Alignment.BottomEnd)
                .graphicsLayer {
                    translationX = 70f
                    translationY = 70f
                }
                .clip(CircleShape)
                .background(BlueprintSuccess.copy(alpha = 0.05f)),
        )

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 22.dp, vertical = 20.dp),
        ) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(
                    modifier = Modifier
                        .size(width = 24.dp, height = 20.dp)
                        .clip(RoundedCornerShape(5.dp))
                        .background(BlueprintTeal),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = "B",
                        style = TextStyle(
                            color = Color(0xFF0D1112),
                            fontSize = 13.sp,
                            fontWeight = FontWeight.ExtraBold,
                        ),
                    )
                }
                Text(
                    text = "Blueprint Cash",
                    style = TextStyle(
                        color = Color(0xFFB3B3B7),
                        fontSize = 17.sp,
                        lineHeight = 20.sp,
                        fontWeight = FontWeight.SemiBold,
                    ),
                )
            }

            Box(modifier = Modifier.weight(1f))

            Text(
                text = state.totalEarningsLabel,
                style = TextStyle(
                    color = BlueprintTextPrimary,
                    fontSize = 64.sp,
                    lineHeight = 64.sp,
                    fontWeight = FontWeight.ExtraBold,
                    letterSpacing = (-2.4).sp,
                ),
            )

            Row(
                modifier = Modifier.padding(top = 14.dp),
                horizontalArrangement = Arrangement.spacedBy(28.dp),
            ) {
                WalletBalanceStat(
                    value = state.availableBalanceLabel,
                    label = "Pending",
                    valueColor = BlueprintTeal,
                )
                WalletBalanceStat(
                    value = "${max(state.totalCaptures, 0)}",
                    label = "Scans",
                    valueColor = Color(0xFF90939A),
                )
            }
        }
    }
}

@Composable
private fun WalletBalanceStat(
    value: String,
    label: String,
    valueColor: Color,
) {
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(
            text = value,
            style = TextStyle(
                color = valueColor,
                fontSize = 19.sp,
                lineHeight = 22.sp,
                fontWeight = FontWeight.SemiBold,
            ),
        )
        Text(
            text = label,
            style = TextStyle(
                color = Color(0xFF64676D),
                fontSize = 13.sp,
                lineHeight = 16.sp,
                fontWeight = FontWeight.Medium,
            ),
        )
    }
}

@Composable
private fun WalletPendingRow(
    totalCaptures: Int,
    pendingReviewCount: Int,
    cashoutEnabled: Boolean,
    onCashout: () -> Unit = {},
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(
            modifier = Modifier.weight(1f),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                imageVector = Icons.Rounded.Schedule,
                contentDescription = null,
                tint = Color(0xFF5A5D63),
                modifier = Modifier.size(18.dp),
            )
            Text(
                text = "$totalCaptures captures • $pendingReviewCount pending review",
                style = TextStyle(
                    color = Color(0xFF6C7077),
                    fontSize = 14.sp,
                    lineHeight = 18.sp,
                    fontWeight = FontWeight.Medium,
                ),
            )
        }

        Row(
            modifier = Modifier
                .clip(RoundedCornerShape(22.dp))
                .background(Color(0xFF232325))
                .border(1.dp, Color.White.copy(alpha = 0.10f), RoundedCornerShape(22.dp))
                .clickable(enabled = cashoutEnabled, onClick = onCashout)
                .padding(horizontal = 14.dp, vertical = 10.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                modifier = Modifier
                    .size(22.dp)
                    .clip(CircleShape)
                    .background(Color(0xFFD4D4D6)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = Icons.Rounded.AttachMoney,
                    contentDescription = null,
                    tint = BlueprintSurface,
                    modifier = Modifier.size(14.dp),
                )
            }
            Text(
                text = "Cashout",
                style = TextStyle(
                    color = if (cashoutEnabled) Color(0xFFDDDDDE) else Color(0xFFA8A8AA),
                    fontSize = 15.sp,
                    lineHeight = 18.sp,
                    fontWeight = FontWeight.Bold,
                ),
            )
        }
    }
}

@Composable
private fun WalletLedgerPicker(
    selectedIndex: Int,
    onSelect: (Int) -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(Color(0xFF1A1A1A))
            .padding(4.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        WalletLedgerTab.entries.forEachIndexed { index, tab ->
            val isSelected = selectedIndex == index
            Box(
                modifier = Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(16.dp))
                    .background(if (isSelected) Color(0xFF343436) else Color.Transparent)
                    .clickable(onClick = { onSelect(index) })
                    .padding(vertical = 14.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = tab.label,
                    style = TextStyle(
                        color = if (isSelected) BlueprintTextPrimary else Color(0xFF6F7175),
                        fontSize = 18.sp,
                        lineHeight = 22.sp,
                        fontWeight = FontWeight.Bold,
                    ),
                )
            }
        }
    }
}

@Composable
private fun WalletLedgerContent(
    selectedTab: WalletLedgerTab,
    payoutEntries: List<CaptureHistoryEntry>,
    historyEntries: List<CaptureHistoryEntry>,
    isLoading: Boolean,
) {
    val entries = when (selectedTab) {
        WalletLedgerTab.Payouts -> payoutEntries
        WalletLedgerTab.Cashouts -> emptyList()
        WalletLedgerTab.History -> historyEntries
    }
    val (emptyTitle, emptySubtitle) = when (selectedTab) {
        WalletLedgerTab.Payouts -> "No payouts yet" to "Approved captures will appear here."
        WalletLedgerTab.Cashouts -> "No cashouts yet" to "Cashouts will appear here once processed."
        WalletLedgerTab.History -> "No history yet" to "Wallet activity will appear here."
    }

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 240.dp),
        contentAlignment = if (isLoading || entries.isEmpty()) Alignment.Center else Alignment.TopStart,
    ) {
        when {
            isLoading -> CircularProgressIndicator(
                color = BlueprintTeal,
                modifier = Modifier.size(36.dp),
            )
            entries.isEmpty() -> Column(
                modifier = Modifier.padding(horizontal = 24.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Icon(
                    imageVector = Icons.Rounded.AccountBalanceWallet,
                    contentDescription = null,
                    tint = Color(0xFF2F3135),
                    modifier = Modifier.size(74.dp),
                )
                Text(
                    text = emptyTitle,
                    style = TextStyle(
                        color = Color(0xFF6D7177),
                        fontSize = 20.sp,
                        lineHeight = 24.sp,
                        fontWeight = FontWeight.SemiBold,
                    ),
                )
                Text(
                    text = emptySubtitle,
                    style = TextStyle(
                        color = Color(0xFF4C5056),
                        fontSize = 16.sp,
                        lineHeight = 21.sp,
                        fontWeight = FontWeight.Medium,
                        textAlign = TextAlign.Center,
                    ),
                )
            }
            else -> Column(modifier = Modifier.fillMaxWidth()) {
                entries.forEach { entry -> LedgerRow(entry) }
            }
        }
    }
}

@Composable
private fun LedgerRow(entry: CaptureHistoryEntry) {
    val dateLabel = entry.submittedAtMs?.let { ms ->
        SimpleDateFormat("MMM d", Locale.US).format(Date(ms))
    } ?: "—"
    val amountLabel = "$" + String.format("%.2f", entry.payoutCents / 100.0)
    val title = entry.jobId ?: "Capture ${entry.captureId.take(8)}"
    val (chipText, chipColor) = when (entry.stage) {
        CaptureSubmissionStage.Paid -> "Paid" to BlueprintTeal
        CaptureSubmissionStage.NeedsRecapture -> "Needs Recapture" to Color(0xFFF5A623)
        CaptureSubmissionStage.InReview -> "In Review" to Color(0xFF6C7077)
    }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 4.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(
                text = title,
                style = TextStyle(
                    color = BlueprintTextPrimary,
                    fontSize = 15.sp,
                    lineHeight = 20.sp,
                    fontWeight = FontWeight.SemiBold,
                ),
                maxLines = 1,
            )
            Text(
                text = dateLabel,
                style = TextStyle(
                    color = BlueprintTextMuted,
                    fontSize = 13.sp,
                    lineHeight = 16.sp,
                    fontWeight = FontWeight.Medium,
                ),
            )
        }

        Box(
            modifier = Modifier
                .clip(RoundedCornerShape(8.dp))
                .background(chipColor.copy(alpha = 0.15f))
                .padding(horizontal = 8.dp, vertical = 4.dp),
        ) {
            Text(
                text = chipText,
                style = TextStyle(
                    color = chipColor,
                    fontSize = 12.sp,
                    lineHeight = 16.sp,
                    fontWeight = FontWeight.SemiBold,
                ),
            )
        }

        Text(
            text = amountLabel,
            style = TextStyle(
                color = if (entry.stage == CaptureSubmissionStage.Paid) BlueprintSuccess else BlueprintTextMuted,
                fontSize = 15.sp,
                lineHeight = 20.sp,
                fontWeight = FontWeight.Bold,
            ),
        )
    }
}
