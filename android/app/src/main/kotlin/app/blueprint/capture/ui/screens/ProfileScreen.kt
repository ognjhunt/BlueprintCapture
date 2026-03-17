package app.blueprint.capture.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import app.blueprint.capture.ui.theme.BlueprintAccent
import app.blueprint.capture.ui.theme.BlueprintBlack
import app.blueprint.capture.ui.theme.BlueprintSurfaceRaised
import app.blueprint.capture.ui.theme.BlueprintTextMuted

@Composable
fun ProfileScreen(
    viewModel: ProfileViewModel = hiltViewModel(),
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
        Text("My Account")
        Text(
            state.firebaseUser?.email ?: "Signed-in contributor profile",
            color = BlueprintTextMuted,
        )
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .background(BlueprintSurfaceRaised, RoundedCornerShape(20.dp))
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text("Contributor")
            ProfileStat("Role", state.profile?.role ?: "capturer")
            ProfileStat("Total captures", "${stats?.totalCaptures ?: 0}")
            ProfileStat("Approved", "${stats?.approvedCaptures ?: 0}")
            ProfileStat("Average quality", "${stats?.averageQuality ?: 0}")
        }
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .background(BlueprintSurfaceRaised, RoundedCornerShape(20.dp))
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text("Account")
            OutlinedTextField(
                value = state.nameDraft,
                onValueChange = viewModel::updateName,
                label = { Text("Full name") },
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = state.phoneDraft,
                onValueChange = viewModel::updatePhone,
                label = { Text("Phone number") },
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = state.companyDraft,
                onValueChange = viewModel::updateCompany,
                label = { Text("Company") },
                modifier = Modifier.fillMaxWidth(),
            )
            state.errorMessage?.let { Text(it, color = BlueprintTextMuted) }
            Button(
                onClick = viewModel::saveProfile,
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(
                    containerColor = BlueprintAccent,
                    contentColor = BlueprintBlack,
                ),
                enabled = state.isSignedIn && !state.isSaving,
            ) {
                Text(if (state.isSaving) "Saving..." else "Save profile")
            }
            OutlinedButton(
                onClick = viewModel::signOut,
                modifier = Modifier.fillMaxWidth(),
                enabled = state.isSignedIn,
            ) {
                Text("Sign out")
            }
        }
    }
}

@Composable
private fun ProfileStat(
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
