package app.blueprint.capture.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
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
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.Bolt
import androidx.compose.material.icons.rounded.CreditCard
import androidx.compose.material.icons.rounded.DateRange
import androidx.compose.material.icons.rounded.Description
import androidx.compose.material.icons.rounded.Face
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material.icons.rounded.VerifiedUser
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.blueprint.capture.ui.theme.BlueprintBorder
import app.blueprint.capture.ui.theme.BlueprintBlack
import app.blueprint.capture.ui.theme.BlueprintSectionLabel
import app.blueprint.capture.ui.theme.BlueprintSurfaceCard
import app.blueprint.capture.ui.theme.BlueprintSurfaceInset
import app.blueprint.capture.ui.theme.BlueprintSurfaceRaised
import app.blueprint.capture.ui.theme.BlueprintTeal
import app.blueprint.capture.ui.theme.BlueprintTealSurface
import app.blueprint.capture.ui.theme.BlueprintTextMuted
import app.blueprint.capture.ui.theme.BlueprintTextPrimary
import app.blueprint.capture.ui.theme.BlueprintWarning
import java.util.Locale

// Icon bg colors (matching SettingsScreen constants)
private val PayoutNavyBg = Color(0xFF1A2340)
private val PayoutNavyTint = Color(0xFF6B8DD6)
private val PayoutAmberBg = Color(0xFF2D1E0A)
private val PayoutIconDark = Color(0xFF232325)

@Composable
fun PayoutsScreen(onBack: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(BlueprintBlack)
            .statusBarsPadding()
            .verticalScroll(rememberScrollState()),
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

        Column(modifier = Modifier.padding(horizontal = 20.dp)) {
            Text(
                text = "Payouts",
                color = BlueprintTextPrimary,
                fontSize = 34.sp,
                lineHeight = 38.sp,
                fontWeight = FontWeight.Bold,
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = "Android alpha keeps payout onboarding honest and off-device until the live payout path is wired.",
                color = BlueprintTextMuted,
                fontSize = 17.sp,
                lineHeight = 22.sp,
            )
        }

        Spacer(modifier = Modifier.height(20.dp))
        PayoutsAlphaBanner(modifier = Modifier.padding(horizontal = 20.dp))
        Spacer(modifier = Modifier.height(32.dp))
        HonestPayoutCard(
            modifier = Modifier.padding(horizontal = 20.dp),
            title = "What is live in alpha",
            body = "Wallet balances, payout history, and capture review state can sync from the backend when your account is configured.",
        )
        Spacer(modifier = Modifier.height(14.dp))
        HonestPayoutCard(
            modifier = Modifier.padding(horizontal = 20.dp),
            title = "What is intentionally not live on Android",
            body = "Identity verification, bank linking, instant pay, Venmo, PayPal, crypto, and Stripe onboarding are not completed in this Android alpha build.",
        )
        Spacer(modifier = Modifier.height(14.dp))
        HonestPayoutCard(
            modifier = Modifier.padding(horizontal = 20.dp),
            title = "Why this screen is limited",
            body = "BlueprintCapture is capture-first. Until payout onboarding is backed by truthful contracts and a real provider flow, Android keeps this surface informational instead of pretending setup is live.",
        )
        Spacer(modifier = Modifier.height(32.dp))
    }
}

@Composable
private fun HonestPayoutCard(
    modifier: Modifier = Modifier,
    title: String,
    body: String,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(BlueprintSurfaceCard, RoundedCornerShape(18.dp))
            .border(1.dp, BlueprintBorder, RoundedCornerShape(18.dp))
            .padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(
            text = title,
            color = BlueprintTextPrimary,
            fontSize = 18.sp,
            lineHeight = 22.sp,
            fontWeight = FontWeight.SemiBold,
        )
        Text(
            text = body,
            color = BlueprintTextMuted,
            fontSize = 15.sp,
            lineHeight = 21.sp,
        )
    }
}

// ── Sub-components ─────────────────────────────────────────────────────────────

@Composable
private fun PayoutsSectionLabel(text: String) {
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
private fun PayoutsCard(
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
private fun PayoutsRowDivider() {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(start = 74.dp, end = 16.dp)
            .height(1.dp)
            .background(BlueprintBorder),
    )
}

@Composable
private fun PayoutsAlphaBanner(modifier: Modifier = Modifier) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .height(IntrinsicSize.Min)
            .clip(RoundedCornerShape(18.dp))
            .background(Color(0xFF151718))
            .border(1.dp, BlueprintTeal.copy(alpha = 0.24f), RoundedCornerShape(18.dp)),
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
                .padding(horizontal = 16.dp, vertical = 14.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                imageVector = Icons.Rounded.Lock,
                contentDescription = null,
                tint = BlueprintTeal,
                modifier = Modifier.size(22.dp),
            )
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                Text(
                    text = "Payout setup unavailable",
                    color = BlueprintTextPrimary,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    text = "Payout setup is not enabled for this alpha build.",
                    color = BlueprintTextMuted,
                    fontSize = 13.sp,
                    lineHeight = 18.sp,
                )
            }
        }
    }
}

@Composable
private fun IdentityStepCard(
    icon: ImageVector,
    iconTint: Color,
    title: String,
    bullets: List<String>,
    actionLabel: String?,
    onAction: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(BlueprintSurfaceCard, RoundedCornerShape(18.dp))
            .border(1.dp, BlueprintBorder, RoundedCornerShape(18.dp)),
    ) {
        // Header row
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 14.dp),
            verticalAlignment = Alignment.Top,
            horizontalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Box(
                modifier = Modifier
                    .size(44.dp)
                    .clip(RoundedCornerShape(12.dp))
                    .background(PayoutIconDark),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = icon,
                    contentDescription = null,
                    tint = iconTint,
                    modifier = Modifier.size(24.dp),
                )
            }
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text(
                        text = title,
                        color = BlueprintTextPrimary,
                        fontSize = 17.sp,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier.weight(1f),
                    )
                    // UNVERIFIED badge
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(8.dp))
                            .background(BlueprintWarning.copy(alpha = 0.18f))
                            .border(1.dp, BlueprintWarning.copy(alpha = 0.35f), RoundedCornerShape(8.dp))
                            .padding(horizontal = 8.dp, vertical = 3.dp),
                    ) {
                        Text(
                            text = "UNVERIFIED",
                            color = BlueprintWarning,
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold,
                            letterSpacing = 0.6.sp,
                        )
                    }
                }
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    bullets.forEach { bullet ->
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalAlignment = Alignment.Top,
                        ) {
                            Box(
                                modifier = Modifier
                                    .padding(top = 7.dp)
                                    .size(4.dp)
                                    .clip(RoundedCornerShape(2.dp))
                                    .background(BlueprintTextMuted.copy(alpha = 0.5f)),
                            )
                            Text(
                                text = bullet,
                                color = BlueprintTextMuted,
                                fontSize = 14.sp,
                                lineHeight = 19.sp,
                            )
                        }
                    }
                }
            }
        }

        // Action row
        if (actionLabel != null) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(1.dp)
                    .background(BlueprintBorder),
            )
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(
                        BlueprintSurfaceInset,
                        RoundedCornerShape(bottomStart = 17.dp, bottomEnd = 17.dp),
                    )
                    .clickable(onClick = onAction)
                    .padding(horizontal = 16.dp, vertical = 14.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(
                    text = actionLabel,
                    color = BlueprintTextPrimary,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.SemiBold,
                )
                Icon(
                    imageVector = Icons.AutoMirrored.Rounded.KeyboardArrowRight,
                    contentDescription = null,
                    tint = BlueprintTextMuted.copy(alpha = 0.5f),
                    modifier = Modifier.size(22.dp),
                )
            }
        }
    }
}

@Composable
private fun PayoutsInfoRow(
    icon: ImageVector,
    iconBg: Color,
    iconTint: Color,
    title: String,
    subtitle: String,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
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
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
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
    }
}

@Composable
private fun InstantPayCard(modifier: Modifier = Modifier) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(BlueprintSurfaceCard, RoundedCornerShape(18.dp))
            .border(1.dp, BlueprintBorder, RoundedCornerShape(18.dp)),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Box(
                modifier = Modifier
                    .size(44.dp)
                    .clip(RoundedCornerShape(12.dp))
                    .background(PayoutAmberBg),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = Icons.Rounded.Bolt,
                    contentDescription = null,
                    tint = BlueprintWarning,
                    modifier = Modifier.size(24.dp),
                )
            }
            Text(
                text = "Amount in USD",
                color = BlueprintTextMuted.copy(alpha = 0.5f),
                fontSize = 17.sp,
                modifier = Modifier.weight(1f),
            )
            Box(
                modifier = Modifier
                    .clip(RoundedCornerShape(12.dp))
                    .background(BlueprintSurfaceInset)
                    .border(1.dp, BlueprintBorder, RoundedCornerShape(12.dp))
                    .padding(horizontal = 16.dp, vertical = 9.dp),
            ) {
                Text(
                    text = "Cash Out",
                    color = BlueprintTextMuted.copy(alpha = 0.45f),
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                )
            }
        }

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(1.dp)
                .background(BlueprintBorder),
        )
        Text(
            text = "Unlocks after your account is verified.",
            color = BlueprintTextMuted,
            fontSize = 13.sp,
            lineHeight = 18.sp,
            modifier = Modifier
                .fillMaxWidth()
                .background(
                    BlueprintSurfaceInset,
                    RoundedCornerShape(bottomStart = 17.dp, bottomEnd = 17.dp),
                )
                .padding(horizontal = 16.dp, vertical = 12.dp),
        )
    }
}
