package app.blueprint.capture

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.core.view.WindowCompat
import app.blueprint.capture.ui.BlueprintCaptureRoot
import app.blueprint.capture.ui.theme.BlueprintTheme
import dagger.hilt.android.AndroidEntryPoint

@AndroidEntryPoint
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        setContent {
            BlueprintTheme {
                BlueprintCaptureRoot()
            }
        }
    }
}
