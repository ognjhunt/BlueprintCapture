package app.blueprint.capture.ui.screens

import androidx.compose.foundation.background
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.CameraAlt
import androidx.compose.material.icons.rounded.CropFree
import androidx.compose.material.icons.rounded.Face
import androidx.compose.material.icons.rounded.MonetizationOn
import androidx.compose.material.icons.rounded.PanTool
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.blueprint.capture.ui.theme.BlueprintAccent
import app.blueprint.capture.ui.theme.BlueprintBlack
import app.blueprint.capture.ui.theme.BlueprintTeal
import app.blueprint.capture.ui.theme.BlueprintTextMuted
import app.blueprint.capture.ui.theme.BlueprintTextPrimary

@Composable
fun OnboardingScreen(
    hasBackend: Boolean,
    hasStripe: Boolean,
    hasNearbyDiscovery: Boolean,
    onContinue: () -> Unit,
) {
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

            // Hero icon: camera inside viewfinder frame
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier.size(96.dp),
            ) {
                Icon(
                    imageVector = Icons.Rounded.CropFree,
                    contentDescription = null,
                    tint = BlueprintTeal,
                    modifier = Modifier.size(96.dp),
                )
                Icon(
                    imageVector = Icons.Rounded.CameraAlt,
                    contentDescription = null,
                    tint = BlueprintTeal,
                    modifier = Modifier.size(48.dp),
                )
            }

            Spacer(modifier = Modifier.height(36.dp))

            Text(
                text = "Get paid to\nscan spaces",
                color = BlueprintTextPrimary,
                fontSize = 42.sp,
                lineHeight = 46.sp,
                fontWeight = FontWeight.ExtraBold,
                textAlign = TextAlign.Center,
                letterSpacing = (-1.2).sp,
            )

            Spacer(modifier = Modifier.height(18.dp))

            Text(
                text = "Capture spaces for Blueprint review. We check rights, coverage, and quality before anything moves downstream.",
                color = BlueprintTextMuted,
                fontSize = 17.sp,
                lineHeight = 24.sp,
                textAlign = TextAlign.Center,
            )

            Spacer(modifier = Modifier.weight(1.2f))

            // Feature rows
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(22.dp),
            ) {
                OnboardingFeatureRow(
                    icon = Icons.Rounded.Face,
                    text = "Nearby spaces and approved opportunities",
                )
                OnboardingFeatureRow(
                    icon = Icons.Rounded.PanTool,
                    text = "Rights and policy checks before reuse",
                )
                OnboardingFeatureRow(
                    icon = Icons.Rounded.MonetizationOn,
                    text = "Payout only after review approval",
                )
            }

            Spacer(modifier = Modifier.height(140.dp))
        }

        // "Get Started" pinned at bottom
        Box(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .navigationBarsPadding()
                .padding(horizontal = 28.dp, vertical = 32.dp)
                .background(BlueprintAccent, RoundedCornerShape(18.dp))
                .clickable(onClick = onContinue)
                .padding(vertical = 18.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = "Get Started",
                color = BlueprintBlack,
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
            )
        }
    }
}

@Composable
private fun OnboardingFeatureRow(
    icon: ImageVector,
    text: String,
) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = BlueprintTeal,
            modifier = Modifier.size(24.dp),
        )
        Text(
            text = text,
            color = BlueprintTextMuted,
            fontSize = 17.sp,
            lineHeight = 22.sp,
        )
    }
}
