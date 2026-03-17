package app.blueprint.capture.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.blueprint.capture.data.model.ScanTarget
import app.blueprint.capture.ui.theme.BlueprintAccent
import app.blueprint.capture.ui.theme.BlueprintBlack
import app.blueprint.capture.ui.theme.BlueprintSurface
import app.blueprint.capture.ui.theme.BlueprintSurfaceRaised
import app.blueprint.capture.ui.theme.BlueprintTextMuted

@Composable
fun ScanScreen(
    targets: List<ScanTarget>,
    configSummary: String,
    onStartCapture: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(BlueprintBlack)
            .padding(horizontal = 20.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text("Captures")
            Text("Android phone capture ships valid video-first while backend tiering stays video-only.", color = BlueprintTextMuted)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            BannerCard(
                modifier = Modifier.weight(1f),
                title = "Backend",
                body = configSummary,
            )
            BannerCard(
                modifier = Modifier.weight(1f),
                title = "Capture source",
                body = "android_phone",
            )
        }
        Button(
            onClick = onStartCapture,
            modifier = Modifier.fillMaxWidth(),
            colors = ButtonDefaults.buttonColors(
                containerColor = BlueprintAccent,
                contentColor = BlueprintBlack,
            ),
        ) {
            Text("Start Android phone capture")
        }
        LazyColumn(
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            items(targets) { target ->
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(BlueprintSurfaceRaised, RoundedCornerShape(22.dp))
                        .padding(16.dp),
                ) {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text(target.title)
                            Text(target.payoutText)
                        }
                        Text(target.subtitle, color = BlueprintTextMuted)
                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text(target.distanceText, color = BlueprintTextMuted)
                            Text(if (target.readyNow) "Ready now" else "Needs review", color = BlueprintTextMuted)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun BannerCard(
    modifier: Modifier = Modifier,
    title: String,
    body: String,
) {
    Column(
        modifier = modifier
            .background(BlueprintSurface, RoundedCornerShape(18.dp))
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(title)
        Text(body, color = BlueprintTextMuted)
    }
}
