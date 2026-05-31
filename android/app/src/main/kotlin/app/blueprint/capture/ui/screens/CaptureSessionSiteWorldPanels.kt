package app.blueprint.capture.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.blueprint.capture.ui.theme.BlueprintAccent
import app.blueprint.capture.ui.theme.BlueprintBorder
import app.blueprint.capture.ui.theme.BlueprintError
import app.blueprint.capture.ui.theme.BlueprintSectionLabel
import app.blueprint.capture.ui.theme.BlueprintSuccess
import app.blueprint.capture.ui.theme.BlueprintTeal
import app.blueprint.capture.ui.theme.BlueprintTextMuted
import app.blueprint.capture.ui.theme.BlueprintTextPrimary
import app.blueprint.capture.ui.theme.BlueprintTextSecondary

@Composable
internal fun SiteWorldPreflightCard(
    siteScale: SiteWorldSiteScale,
    criticalZoneOptions: List<SiteWorldAnchorType>,
    selectedCriticalZones: Set<SiteWorldAnchorType>,
    routePlan: List<String>,
    requiredRules: List<String>,
    optionalRules: List<String>,
    passBrief: SiteWorldPassBrief,
    onUpdateSiteScale: (SiteWorldSiteScale) -> Unit,
    onToggleCriticalZone: (SiteWorldAnchorType) -> Unit,
) {
    CaptureSessionSurfaceCard {
        Text("Site World Candidate")
        Text(passBrief.title, color = BlueprintTeal)
        Text(passBrief.summary, color = BlueprintTextMuted)

        Text("Site size", color = BlueprintSectionLabel, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf(
                SiteWorldSiteScale.SmallSimple,
                SiteWorldSiteScale.Medium,
                SiteWorldSiteScale.MultiZone,
            ).forEach { scale ->
                FilterChip(
                    label = when (scale) {
                        SiteWorldSiteScale.SmallSimple -> "Small"
                        SiteWorldSiteScale.Medium -> "Medium"
                        SiteWorldSiteScale.MultiZone -> "Multi-zone"
                    },
                    selected = siteScale == scale,
                    onClick = { onUpdateSiteScale(scale) },
                )
            }
        }

        Text("Critical zones", color = BlueprintSectionLabel, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            criticalZoneOptions.chunked(3).forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    row.forEach { anchor ->
                        FilterChip(
                            label = anchor.label,
                            selected = selectedCriticalZones.contains(anchor),
                            onClick = { onToggleCriticalZone(anchor) },
                        )
                    }
                }
            }
        }

        SiteWorldListSection("Route plan", routePlan)
        SiteWorldListSection("Required", requiredRules)
        SiteWorldListSection("Optional", optionalRules)
        SiteWorldListSection("Operator prompts", passBrief.exactPrompts.take(2).map { "\"$it\"" })
    }
}
@Composable
internal fun SiteWorldLiveGuidanceCard(
    passBrief: SiteWorldPassBrief,
    checkpointCount: Int,
    entryLocked: Boolean,
    weakSignalEvents: Int,
    criticalZoneCount: Int,
    matchedCriticalZones: Int,
    prompt: String,
    supportPrompts: List<String>,
) {
    CaptureSessionSurfaceCard {
        Text(passBrief.title)
        Text(passBrief.summary, color = BlueprintTextMuted)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterChip(label = if (entryLocked) "Entry locked" else "Entry lock pending", selected = entryLocked, onClick = {})
            FilterChip(
                label = "Checkpoints $checkpointCount/${passBrief.requiredCheckpointTarget}",
                selected = checkpointCount >= passBrief.requiredCheckpointTarget,
                onClick = {},
            )
            if (criticalZoneCount > 0) {
                FilterChip(
                    label = "Critical $matchedCriticalZones/$criticalZoneCount",
                    selected = matchedCriticalZones >= criticalZoneCount,
                    onClick = {},
                )
            }
            if (weakSignalEvents > 0) {
                FilterChip(label = "Weak $weakSignalEvents", selected = true, onClick = {})
            }
        }
        Text(prompt, color = BlueprintTextPrimary, fontWeight = FontWeight.SemiBold)
        supportPrompts.forEach { item ->
            Text(item, color = BlueprintTextMuted, fontSize = 13.sp)
        }
    }
}

@Composable
internal fun SiteWorldAnchorToolCard(
    highlightedAnchorTypes: Set<SiteWorldAnchorType>,
    onMarkAnchor: (SiteWorldAnchorType) -> Unit,
    onMarkEntryLock: () -> Unit,
    onMarkWeakSignal: () -> Unit,
) {
    CaptureSessionSurfaceCard {
        Text("Checkpoints")
        Text("Mark anchors to improve overlap, revisits, and loop closure.", color = BlueprintTextMuted)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterChip(label = "Lock entry", selected = true, onClick = onMarkEntryLock)
            FilterChip(label = "Weak segment", selected = false, onClick = onMarkWeakSignal)
        }
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf(
                SiteWorldAnchorType.Doorway,
                SiteWorldAnchorType.Intersection,
                SiteWorldAnchorType.DockTurn,
                SiteWorldAnchorType.HandoffPoint,
                SiteWorldAnchorType.ControlPanel,
                SiteWorldAnchorType.FloorTransition,
                SiteWorldAnchorType.RestrictedBoundary,
                SiteWorldAnchorType.ExitPoint,
            ).chunked(3).forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    row.forEach { anchor ->
                        FilterChip(
                            label = anchor.label,
                            selected = highlightedAnchorTypes.contains(anchor),
                            onClick = { onMarkAnchor(anchor) },
                        )
                    }
                }
            }
        }
    }
}

@Composable
internal fun SiteWorldReviewCard(review: SiteWorldPassReview) {
    CaptureSessionSurfaceCard {
        Text(review.title)
        Text(review.summary, color = BlueprintTextMuted)
        Text(
            text = "${review.completedRequiredPasses}/${review.totalRequiredPasses} passes complete · ${review.score}",
            color = when (review.tone) {
                SiteWorldReviewTone.Ready -> BlueprintSuccess
                SiteWorldReviewTone.Caution -> BlueprintAccent
                SiteWorldReviewTone.ActionRequired -> BlueprintError
            },
            fontWeight = FontWeight.SemiBold,
        )
        if (review.completedItems.isNotEmpty()) {
            SiteWorldListSection("Completed", review.completedItems)
        }
        if (review.missingItems.isNotEmpty()) {
            SiteWorldListSection("Still needed", review.missingItems)
        }
        review.weakSignalSummary?.let {
            Text(it.replace("weak_signal_events:", "Weak signal events: "), color = BlueprintTextMuted, fontSize = 13.sp)
        }
    }
}

@Composable
internal fun SiteWorldListSection(title: String, items: List<String>) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(title, color = BlueprintSectionLabel, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
        items.forEach { item ->
            Text("• $item", color = BlueprintTextSecondary, fontSize = 13.sp, lineHeight = 18.sp)
        }
    }
}

@Composable
internal fun FilterChip(
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
) {
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(999.dp))
            .background(if (selected) BlueprintTeal.copy(alpha = 0.28f) else Color(0xFF1A1A1A))
            .border(1.dp, if (selected) BlueprintTeal.copy(alpha = 0.5f) else BlueprintBorder, RoundedCornerShape(999.dp))
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 8.dp),
    ) {
        Text(
            text = label,
            color = BlueprintTextPrimary,
            fontSize = 13.sp,
            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Medium,
        )
    }
}
