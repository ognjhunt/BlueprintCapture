package app.blueprint.capture.data.capture

import android.content.Context
import com.google.ar.core.ArCoreApk

enum class ARCoreSupportLevel {
    SupportedInstalled,
    SupportedNeedsInstall,
    Unsupported,
    Unknown,
}

object ARCoreSupport {
    fun supportLevel(context: Context): ARCoreSupportLevel {
        return when (ArCoreApk.getInstance().checkAvailability(context)) {
            ArCoreApk.Availability.SUPPORTED_INSTALLED -> ARCoreSupportLevel.SupportedInstalled
            ArCoreApk.Availability.SUPPORTED_APK_TOO_OLD,
            ArCoreApk.Availability.SUPPORTED_NOT_INSTALLED -> ARCoreSupportLevel.SupportedNeedsInstall
            ArCoreApk.Availability.UNSUPPORTED_DEVICE_NOT_CAPABLE -> ARCoreSupportLevel.Unsupported
            else -> ARCoreSupportLevel.Unknown
        }
    }

    fun isUsable(context: Context): Boolean = supportLevel(context) == ARCoreSupportLevel.SupportedInstalled
}
