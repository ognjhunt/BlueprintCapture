package app.blueprint.capture.ui.screens

import android.content.Context
import android.content.Intent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Email
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material.icons.rounded.Visibility
import androidx.compose.material.icons.rounded.VisibilityOff
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Canvas
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Paint
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import app.blueprint.capture.ui.theme.BlueprintBorder
import app.blueprint.capture.ui.theme.BlueprintBlack
import app.blueprint.capture.ui.theme.BlueprintSurfaceCard
import app.blueprint.capture.ui.theme.BlueprintSurfaceInset
import app.blueprint.capture.ui.theme.BlueprintSurfaceRaised
import app.blueprint.capture.ui.theme.BlueprintTextMuted
import app.blueprint.capture.ui.theme.BlueprintTextPrimary
import com.google.android.gms.auth.api.signin.GoogleSignIn
import com.google.android.gms.auth.api.signin.GoogleSignInOptions
import com.google.android.gms.common.api.ApiException
import androidx.compose.foundation.Canvas as ComposeCanvas

@Composable
fun AuthScreen(
    onSkip: () -> Unit = {},
    viewModel: AuthViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsState()
    val context = LocalContext.current
    var passwordVisible by remember { mutableStateOf(false) }

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
            .statusBarsPadding()
            .navigationBarsPadding(),
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp),
        ) {
            Spacer(modifier = Modifier.height(72.dp))

            Text(
                text = "Create your\naccount",
                color = BlueprintTextPrimary,
                fontSize = 42.sp,
                lineHeight = 46.sp,
                fontWeight = FontWeight.ExtraBold,
                letterSpacing = (-1.2).sp,
            )

            Spacer(modifier = Modifier.height(10.dp))

            Text(
                text = "Sign up to track earnings and get paid.",
                color = BlueprintTextMuted,
                fontSize = 17.sp,
                lineHeight = 24.sp,
            )

            Spacer(modifier = Modifier.height(32.dp))

            // Continue with Google
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(16.dp))
                    .background(BlueprintSurfaceCard)
                    .border(1.dp, BlueprintBorder, RoundedCornerShape(16.dp))
                    .clickable(
                        enabled = !state.isBusy,
                        onClick = {
                            startGoogleSignIn(
                                context = context,
                                onIntent = googleLauncher::launch,
                                onError = viewModel::setGoogleError,
                            )
                        },
                    )
                    .padding(horizontal = 18.dp, vertical = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(14.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                GoogleGIcon(modifier = Modifier.size(22.dp))
                Text(
                    text = "Continue with Google",
                    color = BlueprintTextPrimary,
                    fontSize = 17.sp,
                    fontWeight = FontWeight.Medium,
                )
            }

            Spacer(modifier = Modifier.height(20.dp))

            // "or" divider
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .height(1.dp)
                        .background(BlueprintBorder),
                )
                Text(
                    text = "or",
                    color = BlueprintTextMuted,
                    fontSize = 14.sp,
                )
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .height(1.dp)
                        .background(BlueprintBorder),
                )
            }

            Spacer(modifier = Modifier.height(20.dp))

            // Mode segmented control
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(14.dp))
                    .background(BlueprintSurfaceInset)
                    .padding(4.dp),
            ) {
                AuthModeTab(
                    label = "Create Account",
                    selected = state.mode == AuthMode.SignUp,
                    modifier = Modifier.weight(1f),
                    onClick = { if (state.mode != AuthMode.SignUp) viewModel.toggleMode() },
                )
                AuthModeTab(
                    label = "Sign In",
                    selected = state.mode == AuthMode.SignIn,
                    modifier = Modifier.weight(1f),
                    onClick = { if (state.mode != AuthMode.SignIn) viewModel.toggleMode() },
                )
            }

            Spacer(modifier = Modifier.height(20.dp))

            // Email field
            Text(
                text = "Email Address",
                color = BlueprintTextMuted,
                fontSize = 13.sp,
                fontWeight = FontWeight.Medium,
                modifier = Modifier.padding(start = 2.dp, bottom = 6.dp),
            )
            AuthInputField(
                value = state.email,
                onValueChange = viewModel::updateEmail,
                placeholder = "you@example.com",
                leadingIcon = {
                    Icon(
                        Icons.Rounded.Email,
                        contentDescription = null,
                        tint = BlueprintTextMuted,
                        modifier = Modifier.size(20.dp),
                    )
                },
                keyboardType = KeyboardType.Email,
            )

            Spacer(modifier = Modifier.height(16.dp))

            // Password field
            Text(
                text = "Password",
                color = BlueprintTextMuted,
                fontSize = 13.sp,
                fontWeight = FontWeight.Medium,
                modifier = Modifier.padding(start = 2.dp, bottom = 6.dp),
            )
            AuthInputField(
                value = state.password,
                onValueChange = viewModel::updatePassword,
                placeholder = "At least 8 characters",
                leadingIcon = {
                    Icon(
                        Icons.Rounded.Lock,
                        contentDescription = null,
                        tint = BlueprintTextMuted,
                        modifier = Modifier.size(20.dp),
                    )
                },
                trailingIcon = {
                    Icon(
                        if (passwordVisible) Icons.Rounded.VisibilityOff else Icons.Rounded.Visibility,
                        contentDescription = null,
                        tint = BlueprintTextMuted,
                        modifier = Modifier
                            .size(20.dp)
                            .clickable { passwordVisible = !passwordVisible },
                    )
                },
                visualTransformation = if (passwordVisible) VisualTransformation.None else PasswordVisualTransformation(),
                keyboardType = KeyboardType.Password,
            )

            if (state.errorMessage != null) {
                Spacer(modifier = Modifier.height(12.dp))
                Text(
                    text = state.errorMessage!!,
                    color = Color(0xFFE06666),
                    fontSize = 14.sp,
                )
            }

            Spacer(modifier = Modifier.height(24.dp))

            // Submit button
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(16.dp))
                    .background(
                        if (state.canSubmit) BlueprintSurfaceRaised
                        else Color(0xFF111213),
                    )
                    .border(1.dp, BlueprintBorder, RoundedCornerShape(16.dp))
                    .clickable(enabled = state.canSubmit, onClick = viewModel::submit)
                    .padding(vertical = 18.dp),
                contentAlignment = Alignment.Center,
            ) {
                if (state.isBusy) {
                    CircularProgressIndicator(
                        color = BlueprintTextMuted,
                        modifier = Modifier.size(22.dp),
                        strokeWidth = 2.dp,
                    )
                } else {
                    Text(
                        text = if (state.mode == AuthMode.SignIn) "Sign In" else "Create Account",
                        color = if (state.canSubmit) BlueprintTextPrimary else BlueprintTextMuted.copy(alpha = 0.4f),
                        fontSize = 17.sp,
                        fontWeight = FontWeight.SemiBold,
                    )
                }
            }

            Spacer(modifier = Modifier.height(32.dp))
        }

        // Skip for now — must be after Column so it sits on top and receives touches
        Text(
            text = "Skip for now",
            color = BlueprintTextMuted,
            fontSize = 16.sp,
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(top = 16.dp, end = 24.dp)
                .clickable(onClick = onSkip),
        )
    }
}

@Composable
private fun AuthModeTab(
    label: String,
    selected: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(11.dp))
            .background(if (selected) BlueprintSurfaceCard else Color.Transparent)
            .clickable(onClick = onClick)
            .padding(vertical = 12.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = label,
            color = if (selected) BlueprintTextPrimary else BlueprintTextMuted,
            fontSize = 15.sp,
            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
        )
    }
}

@Composable
private fun AuthInputField(
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    leadingIcon: @Composable (() -> Unit)? = null,
    trailingIcon: @Composable (() -> Unit)? = null,
    visualTransformation: VisualTransformation = VisualTransformation.None,
    keyboardType: KeyboardType = KeyboardType.Text,
) {
    TextField(
        value = value,
        onValueChange = onValueChange,
        placeholder = {
            Text(
                text = placeholder,
                color = BlueprintTextMuted.copy(alpha = 0.5f),
                fontSize = 16.sp,
            )
        },
        leadingIcon = leadingIcon,
        trailingIcon = trailingIcon,
        visualTransformation = visualTransformation,
        keyboardOptions = KeyboardOptions(keyboardType = keyboardType),
        singleLine = true,
        colors = TextFieldDefaults.colors(
            focusedContainerColor = BlueprintSurfaceCard,
            unfocusedContainerColor = BlueprintSurfaceCard,
            focusedTextColor = BlueprintTextPrimary,
            unfocusedTextColor = BlueprintTextPrimary,
            focusedIndicatorColor = Color.Transparent,
            unfocusedIndicatorColor = Color.Transparent,
            cursorColor = BlueprintTextPrimary,
            focusedLeadingIconColor = BlueprintTextMuted,
            unfocusedLeadingIconColor = BlueprintTextMuted,
        ),
        shape = RoundedCornerShape(14.dp),
        modifier = Modifier
            .fillMaxWidth()
            .border(1.dp, BlueprintBorder, RoundedCornerShape(14.dp)),
    )
}

@Composable
private fun GoogleGIcon(modifier: Modifier = Modifier) {
    ComposeCanvas(modifier = modifier) {
        val w = size.width
        val h = size.height
        drawIntoCanvas { canvas ->
            val paint = Paint().asFrameworkPaint()
            paint.isAntiAlias = true

            // Blue arc (top-right)
            paint.color = android.graphics.Color.parseColor("#4285F4")
            canvas.nativeCanvas.drawArc(
                android.graphics.RectF(0f, 0f, w, h),
                -90f, 90f, false, paint,
            )
            // Red arc (top-left)
            paint.color = android.graphics.Color.parseColor("#EA4335")
            canvas.nativeCanvas.drawArc(
                android.graphics.RectF(0f, 0f, w, h),
                -180f, 90f, false, paint,
            )
            // Yellow arc (bottom-left)
            paint.color = android.graphics.Color.parseColor("#FBBC05")
            canvas.nativeCanvas.drawArc(
                android.graphics.RectF(0f, 0f, w, h),
                90f, 90f, false, paint,
            )
            // Green arc (bottom-right)
            paint.color = android.graphics.Color.parseColor("#34A853")
            canvas.nativeCanvas.drawArc(
                android.graphics.RectF(0f, 0f, w, h),
                0f, 90f, false, paint,
            )

            // Center white cutout circle
            paint.color = android.graphics.Color.parseColor("#050607")
            canvas.nativeCanvas.drawCircle(w / 2f, h / 2f, w * 0.35f, paint)

            // White horizontal bar for "G" crossbar (right side)
            paint.color = android.graphics.Color.parseColor("#4285F4")
            canvas.nativeCanvas.drawRect(
                android.graphics.RectF(w * 0.5f, h * 0.35f, w * 0.95f, h * 0.65f),
                paint,
            )
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
