package app.blueprint.capture

import android.app.Application
import android.util.Log
import androidx.hilt.work.HiltWorkerFactory
import androidx.work.Configuration
import com.meta.wearable.dat.core.Wearables
import dagger.hilt.android.HiltAndroidApp
import javax.inject.Inject

@HiltAndroidApp
class BlueprintCaptureApplication : Application(), Configuration.Provider {
    @Inject
    lateinit var workerFactory: HiltWorkerFactory

    override fun onCreate() {
        super.onCreate()
        app.blueprint.capture.data.capture.CaptureUploadNotifications.initialize(this)
        val mwdatResult = Wearables.initialize(this)
        if (!mwdatResult.isSuccess) {
            Log.w("MWDAT", "Wearables SDK init failed")
        }
    }

    override val workManagerConfiguration: Configuration
        get() = Configuration.Builder()
            .setWorkerFactory(workerFactory)
            .build()
}
