package app.blueprint.capture.data.permissions

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject

const val REQUIRED_STARTUP_PERMISSION: String = Manifest.permission.ACCESS_FINE_LOCATION

class StartupPermissionChecker(
    private val isPermissionGranted: (String) -> Boolean,
) {
    @Inject
    constructor(
        @ApplicationContext context: Context,
    ) : this(
        isPermissionGranted = { permission ->
            ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED
        },
    )

    fun hasRequiredStartupPermission(): Boolean = isPermissionGranted(REQUIRED_STARTUP_PERMISSION)
}
