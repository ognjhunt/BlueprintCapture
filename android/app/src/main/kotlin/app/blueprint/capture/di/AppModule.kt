package app.blueprint.capture.di

import android.content.Context
import android.content.SharedPreferences
import android.hardware.SensorManager
import android.location.LocationManager
import androidx.work.WorkManager
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.storage.FirebaseStorage
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object AppModule {
    @Provides
    @Singleton
    fun provideSharedPreferences(
        @ApplicationContext context: Context,
    ): SharedPreferences = context.getSharedPreferences("blueprint_capture_prefs", Context.MODE_PRIVATE)

    @Provides
    @Singleton
    fun provideFirebaseAuth(): FirebaseAuth = FirebaseAuth.getInstance()

    @Provides
    @Singleton
    fun provideFirestore(): FirebaseFirestore = FirebaseFirestore.getInstance()

    @Provides
    @Singleton
    fun provideFirebaseStorage(): FirebaseStorage = FirebaseStorage.getInstance()

    @Provides
    @Singleton
    fun provideWorkManager(
        @ApplicationContext context: Context,
    ): WorkManager = WorkManager.getInstance(context)

    /** Used by ScanViewModel for last-known location to compute feed ranking distances. */
    @Provides
    @Singleton
    fun provideLocationManager(
        @ApplicationContext context: Context,
    ): LocationManager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager

    /** Used by CaptureIMUSampler for accelerometer + gyroscope data during capture. */
    @Provides
    @Singleton
    fun provideSensorManager(
        @ApplicationContext context: Context,
    ): SensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
}
