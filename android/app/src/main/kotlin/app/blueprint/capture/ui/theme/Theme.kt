package app.blueprint.capture.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable

private val DarkColors = darkColorScheme(
    primary = BlueprintAccent,
    background = BlueprintBlack,
    surface = BlueprintSurface,
    surfaceVariant = BlueprintSurfaceRaised,
)

@Composable
fun BlueprintTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    MaterialTheme(
        colorScheme = DarkColors,
        typography = BlueprintTypography,
        content = content,
    )
}
