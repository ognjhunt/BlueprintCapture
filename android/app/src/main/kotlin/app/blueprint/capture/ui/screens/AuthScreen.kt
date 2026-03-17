package app.blueprint.capture.ui.screens

import android.content.Context
import android.content.Intent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import app.blueprint.capture.ui.theme.BlueprintAccent
import app.blueprint.capture.ui.theme.BlueprintBlack
import app.blueprint.capture.ui.theme.BlueprintSurfaceRaised
import app.blueprint.capture.ui.theme.BlueprintTextMuted
import com.google.android.gms.auth.api.signin.GoogleSignIn
import com.google.android.gms.auth.api.signin.GoogleSignInOptions
import com.google.android.gms.common.api.ApiException

@Composable
fun AuthScreen(
    configSummary: String,
    viewModel: AuthViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsState()
    val context = LocalContext.current

    val googleLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.StartActivityForResult(),
    ) { result ->
        handleGoogleSignInResult(
            data = result.data,
            onToken = viewModel::submitGoogleIdToken,
            onError = viewModel::setGoogleError,
        )
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(BlueprintBlack)
            .padding(20.dp),
    ) {
        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Text("Sign in to Blueprint")
            Text(
                "Auth comes before invite codes, wallet setup, and curated capture state so the Android flow stays aligned with iOS. $configSummary",
                color = BlueprintTextMuted,
            )
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(BlueprintSurfaceRaised, RoundedCornerShape(20.dp))
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text(if (state.mode == AuthMode.SignIn) "Welcome back" else "Create your account")
                    Text(
                        if (state.mode == AuthMode.SignIn) "Email sign-in" else "Email sign-up",
                        color = BlueprintTextMuted,
                    )
                }
                if (state.mode == AuthMode.SignUp) {
                    OutlinedTextField(
                        value = state.name,
                        onValueChange = viewModel::updateName,
                        label = { Text("Full name") },
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
                OutlinedTextField(
                    value = state.email,
                    onValueChange = viewModel::updateEmail,
                    label = { Text("Email") },
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = state.password,
                    onValueChange = viewModel::updatePassword,
                    label = { Text("Password") },
                    visualTransformation = PasswordVisualTransformation(),
                    modifier = Modifier.fillMaxWidth(),
                )
                if (state.mode == AuthMode.SignUp) {
                    OutlinedTextField(
                        value = state.confirmPassword,
                        onValueChange = viewModel::updateConfirmPassword,
                        label = { Text("Confirm password") },
                        visualTransformation = PasswordVisualTransformation(),
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
                state.errorMessage?.let { message ->
                    Text(message, color = BlueprintTextMuted)
                }
                Button(
                    onClick = viewModel::submit,
                    enabled = state.canSubmit,
                    modifier = Modifier.fillMaxWidth(),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = BlueprintAccent,
                        contentColor = BlueprintBlack,
                    ),
                ) {
                    if (state.isBusy) {
                        CircularProgressIndicator(modifier = Modifier.padding(vertical = 2.dp))
                    } else {
                        Text(if (state.mode == AuthMode.SignIn) "Sign In" else "Create Account")
                    }
                }
                OutlinedButton(
                    onClick = {
                        startGoogleSignIn(
                            context = context,
                            onIntent = googleLauncher::launch,
                            onError = viewModel::setGoogleError,
                        )
                    },
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !state.isBusy,
                ) {
                    Text("Continue with Google")
                }
                OutlinedButton(
                    onClick = viewModel::toggleMode,
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !state.isBusy,
                ) {
                    Text(if (state.mode == AuthMode.SignIn) "Need an account?" else "Already have an account?")
                }
            }
        }
    }
}

private fun startGoogleSignIn(
    context: Context,
    onIntent: (Intent) -> Unit,
    onError: (String) -> Unit,
) {
    val webClientId = context.googleWebClientId()
    if (webClientId.isNullOrBlank()) {
        onError("Google sign-in is unavailable because the web client ID was not generated.")
        return
    }

    val options = GoogleSignInOptions.Builder(GoogleSignInOptions.DEFAULT_SIGN_IN)
        .requestEmail()
        .requestIdToken(webClientId)
        .build()

    onIntent(GoogleSignIn.getClient(context, options).signInIntent)
}

private fun handleGoogleSignInResult(
    data: Intent?,
    onToken: (String) -> Unit,
    onError: (String) -> Unit,
) {
    val task = GoogleSignIn.getSignedInAccountFromIntent(data)
    try {
        val account = task.getResult(ApiException::class.java)
        val token = account.idToken
        if (token.isNullOrBlank()) {
            onError("Google sign-in returned without an ID token.")
        } else {
            onToken(token)
        }
    } catch (error: ApiException) {
        onError(error.localizedMessage ?: "Google sign-in failed.")
    }
}

private fun Context.googleWebClientId(): String? {
    val resourceId = resources.getIdentifier("default_web_client_id", "string", packageName)
    if (resourceId == 0) {
        return null
    }
    return getString(resourceId)
}
