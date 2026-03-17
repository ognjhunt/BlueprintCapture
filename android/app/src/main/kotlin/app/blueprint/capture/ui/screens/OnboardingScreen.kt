package app.blueprint.capture.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.blueprint.capture.ui.theme.BlueprintAccent
import app.blueprint.capture.ui.theme.BlueprintBlack
import app.blueprint.capture.ui.theme.BlueprintSurfaceRaised
import app.blueprint.capture.ui.theme.BlueprintTextMuted

@Composable
fun OnboardingScreen(
    hasBackend: Boolean,
    hasStripe: Boolean,
    hasPlaces: Boolean,
    onContinue: () -> Unit,
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(BlueprintBlack)
            .padding(horizontal = 24.dp, vertical = 28.dp),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            Spacer(modifier = Modifier.height(12.dp))
            Text("Get paid to\nscan spaces")
            Text(
                "Capture spaces for Blueprint review. We check rights, coverage, and quality before anything moves downstream.",
                color = BlueprintTextMuted,
            )
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(BlueprintSurfaceRaised, RoundedCornerShape(24.dp))
                    .padding(18.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text("What this Android build already matches")
                FeatureLine("Nearby spaces and approved opportunities")
                FeatureLine("Rights and policy checks before reuse")
                FeatureLine("Payouts only after review approval")
            }
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(BlueprintSurfaceRaised, RoundedCornerShape(24.dp))
                    .padding(18.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Text("Current device readiness")
                StatusLine("Firebase auth", true)
                StatusLine("Backend config", hasBackend)
                StatusLine("Stripe config", hasStripe)
                StatusLine("Places config", hasPlaces)
            }
            Spacer(modifier = Modifier.height(8.dp))
            Button(
                onClick = onContinue,
                colors = ButtonDefaults.buttonColors(
                    containerColor = BlueprintAccent,
                    contentColor = BlueprintBlack,
                ),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text("Get Started")
            }
        }
    }
}

@Composable
private fun FeatureLine(text: String) {
    Text(text, color = BlueprintTextMuted)
}

@Composable
private fun StatusLine(
    label: String,
    ready: Boolean,
) {
    Text(
        text = "$label · ${if (ready) "Ready" else "Still local-only"}",
        color = BlueprintTextMuted,
    )
}
