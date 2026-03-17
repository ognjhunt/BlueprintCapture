package app.blueprint.capture.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import app.blueprint.capture.ui.theme.BlueprintBlack
import app.blueprint.capture.ui.theme.BlueprintSurfaceRaised
import app.blueprint.capture.ui.theme.BlueprintTextMuted

@Composable
fun WalletScreen(
    viewModel: WalletViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsState()
    val stats = state.profile?.stats

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(BlueprintBlack)
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text("Wallet")
        Text("Your earnings and payout history", color = BlueprintTextMuted)
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .background(BlueprintSurfaceRaised, RoundedCornerShape(20.dp))
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text("Balance")
            WalletRow("Available", state.availableBalanceLabel)
            WalletRow("Lifetime earnings", state.totalEarningsLabel)
            WalletRow("Referral pending", state.referralPendingLabel)
        }
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .background(BlueprintSurfaceRaised, RoundedCornerShape(20.dp))
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text("Review metrics")
            WalletRow("Total captures", "${stats?.totalCaptures ?: 0}")
            WalletRow("Approved captures", "${stats?.approvedCaptures ?: 0}")
            WalletRow("Approval rate", "${stats?.approvalRatePercent ?: 0}%")
        }
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .background(BlueprintSurfaceRaised, RoundedCornerShape(20.dp))
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text("Payout setup")
            Text(state.payoutReadinessMessage, color = BlueprintTextMuted)
        }
    }
}

@Composable
private fun WalletRow(
    label: String,
    value: String,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(label, color = BlueprintTextMuted)
        Text(value)
    }
}
