package app.blueprint.capture.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.CardGiftcard
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.blueprint.capture.ui.theme.BlueprintBorder
import app.blueprint.capture.ui.theme.BlueprintBlack
import app.blueprint.capture.ui.theme.BlueprintSectionLabel
import app.blueprint.capture.ui.theme.BlueprintSurfaceCard
import app.blueprint.capture.ui.theme.BlueprintSurfaceInset
import app.blueprint.capture.ui.theme.BlueprintTextMuted
import app.blueprint.capture.ui.theme.BlueprintTextPrimary
import app.blueprint.capture.ui.theme.BlueprintTeal
import java.util.Locale

@Composable
fun InviteCodeScreen(
    onSkip: () -> Unit,
    onApply: () -> Unit,
) {
    var code by rememberSaveable { mutableStateOf("") }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(BlueprintBlack)
            .statusBarsPadding()
            .navigationBarsPadding(),
    ) {
        // Skip for now
        Text(
            text = "Skip for now",
            color = BlueprintTextMuted,
            fontSize = 16.sp,
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(top = 16.dp, end = 24.dp)
                .clickable(onClick = onSkip),
        )

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(modifier = Modifier.weight(1f))

            // Gift icon
            Box(
                modifier = Modifier
                    .size(96.dp),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = Icons.Rounded.CardGiftcard,
                    contentDescription = null,
                    tint = BlueprintTeal,
                    modifier = Modifier.size(80.dp),
                )
            }

            Spacer(modifier = Modifier.height(28.dp))

            Text(
                text = "Got an Invite?",
                color = BlueprintTextPrimary,
                fontSize = 38.sp,
                lineHeight = 42.sp,
                fontWeight = FontWeight.ExtraBold,
                textAlign = TextAlign.Center,
                letterSpacing = (-1.0).sp,
            )

            Spacer(modifier = Modifier.height(14.dp))

            Text(
                text = "Enter your friend's invite code below.\nYou'll both get 10% extra on your first payout.",
                color = BlueprintTextMuted,
                fontSize = 16.sp,
                lineHeight = 22.sp,
                textAlign = TextAlign.Center,
            )

            Spacer(modifier = Modifier.weight(1f))

            // Input section
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    text = "INVITE CODE",
                    color = BlueprintSectionLabel,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold,
                    letterSpacing = 2.sp,
                    modifier = Modifier.padding(start = 2.dp),
                )
                TextField(
                    value = code,
                    onValueChange = { code = it.uppercase(Locale.US).take(10) },
                    placeholder = {
                        Text(
                            text = "e.g. AB12CD",
                            color = BlueprintTextMuted.copy(alpha = 0.5f),
                            fontSize = 18.sp,
                            fontWeight = FontWeight.Medium,
                        )
                    },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters),
                    colors = TextFieldDefaults.colors(
                        focusedContainerColor = BlueprintSurfaceCard,
                        unfocusedContainerColor = BlueprintSurfaceCard,
                        focusedTextColor = BlueprintTextPrimary,
                        unfocusedTextColor = BlueprintTextPrimary,
                        focusedIndicatorColor = Color.Transparent,
                        unfocusedIndicatorColor = Color.Transparent,
                        cursorColor = BlueprintTextPrimary,
                    ),
                    textStyle = androidx.compose.ui.text.TextStyle(
                        fontSize = 18.sp,
                        fontWeight = FontWeight.Medium,
                        color = BlueprintTextPrimary,
                    ),
                    shape = RoundedCornerShape(16.dp),
                    modifier = Modifier
                        .fillMaxWidth()
                        .border(1.dp, BlueprintBorder, RoundedCornerShape(16.dp)),
                )
            }

            Spacer(modifier = Modifier.height(14.dp))

            // Apply Code button
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(16.dp))
                    .background(
                        if (code.isNotBlank()) BlueprintSurfaceCard
                        else Color(0xFF111213),
                    )
                    .border(1.dp, BlueprintBorder, RoundedCornerShape(16.dp))
                    .clickable(
                        enabled = code.isNotBlank(),
                        onClick = onApply,
                    )
                    .padding(vertical = 18.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = "Apply Code",
                    color = if (code.isNotBlank()) BlueprintTextPrimary else BlueprintTextMuted.copy(alpha = 0.4f),
                    fontSize = 17.sp,
                    fontWeight = FontWeight.SemiBold,
                )
            }

            Spacer(modifier = Modifier.weight(0.5f))
        }
    }
}
