package app.blueprint.capture

import android.app.Application
import android.util.Log
import androidx.hilt.work.HiltWorkerFactory
import androidx.work.Configuration
import app.blueprint.capture.BuildConfig
import app.blueprint.capture.data.auth.AuthRepository
import app.blueprint.capture.data.auth.FirebaseAuthErrorFormatter
import app.blueprint.capture.data.notification.PushNotificationManager
import com.meta.wearable.dat.core.Wearables
import dagger.hilt.android.HiltAndroidApp
import javax.inject.Inject
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

@HiltAndroidApp
class BlueprintCaptureApplication : Application(), Configuration.Provider {
    @Inject
    lateinit var workerFactory: HiltWorkerFactory

    @Inject
    lateinit var authRepository: AuthRepository

    @Inject
    lateinit var pushNotificationManager: PushNotificationManager

    private val applicationScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    override fun onCreate() {
        super.onCreate()
        app.blueprint.capture.data.capture.CaptureUploadNotifications.initialize(this)
        if (BuildConfig.MWDAT_PRIVATE_SDK_ENABLED) {
            val mwdatResult = Wearables.initialize(this)
            if (!mwdatResult.isSuccess) {
                Log.w("MWDAT", "Wearables SDK init failed")
            }
        } else {
            Log.i("MWDAT", "Meta DAT SDK disabled for this build; Android XR and phone capture remain available.")
        }
        pushNotificationManager.start()
        applicationScope.launch {
            runCatching { authRepository.ensureAnonymousSession() }
                .onFailure {
                    Log.w(
                        "Auth",
                        "Anonymous sign-in failed: ${FirebaseAuthErrorFormatter.describeAnonymousSignInFailure(it)}",
                        it,
                    )
                }
        }
    }

    override val workManagerConfiguration: Configuration
        get() = Configuration.Builder()
            .setWorkerFactory(workerFactory)
            .build()
}
