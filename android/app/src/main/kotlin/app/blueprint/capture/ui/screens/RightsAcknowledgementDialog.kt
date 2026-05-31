package app.blueprint.capture.ui.screens

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.blueprint.capture.ui.theme.BlueprintBorder
import app.blueprint.capture.ui.theme.BlueprintTeal
import app.blueprint.capture.ui.theme.BlueprintTextPrimary

internal object RightsAcknowledgementDialogCopy {
    const val title: String = "Review capture rights"
    const val body: String =
        "Only continue if you have permission to capture this space, will avoid restricted or private areas, and understand qualification, privacy, and rights checks may still block downstream use."
    const val confirmButton: String = "I Confirm"
    const val dismissButton: String = "Cancel"
}

@Composable
internal fun RightsAcknowledgementDialog(
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = Color(0xFF111111),
        title = {
            Text(
                text = RightsAcknowledgementDialogCopy.title,
                color = Color.White,
                fontSize = 17.sp,
                fontWeight = FontWeight.SemiBold,
            )
        },
        text = {
            Text(
                text = RightsAcknowledgementDialogCopy.body,
                color = Color(0xFF888888),
                fontSize = 14.sp,
            )
        },
        confirmButton = {
            Button(
                onClick = onConfirm,
                colors = ButtonDefaults.buttonColors(
                    containerColor = BlueprintTeal,
                ),
                shape = RoundedCornerShape(12.dp),
            ) {
                Text(RightsAcknowledgementDialogCopy.confirmButton)
            }
        },
        dismissButton = {
            OutlinedButton(
                onClick = onDismiss,
                shape = RoundedCornerShape(12.dp),
                border = BorderStroke(1.dp, BlueprintBorder),
            ) {
                Text(RightsAcknowledgementDialogCopy.dismissButton, color = BlueprintTextPrimary)
            }
        },
    )
}
