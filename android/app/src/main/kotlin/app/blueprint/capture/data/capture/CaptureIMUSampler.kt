package app.blueprint.capture.data.capture

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

@Serializable
data class IMUSample(
    @SerialName("t_ms") val timestampMs: Long,
    @SerialName("ax") val ax: Float,
    @SerialName("ay") val ay: Float,
    @SerialName("az") val az: Float,
    @SerialName("gx") val gx: Float? = null,
    @SerialName("gy") val gy: Float? = null,
    @SerialName("gz") val gz: Float? = null,
)

/**
 * Collects accelerometer + gyroscope samples during a capture session.
 * Mirrors the CoreMotion IMU collection done on iOS throughout a capture.
 *
 * Usage:
 *   val sampler = CaptureIMUSampler(context)
 *   sampler.startCapture(captureStartMs)
 *   // ... recording runs ...
 *   val count = sampler.sampleCount()
 *   val file = sampler.writeToFile(rawDirectory)   // stops sampling and writes imu_samples.jsonl
 *   sampler.release()
 */
class CaptureIMUSampler(context: Context) {
    private val sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val accelerometer: Sensor? = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
    private val gyroscope: Sensor? = sensorManager.getDefaultSensor(Sensor.TYPE_GYROSCOPE)

    private val samples = mutableListOf<IMUSample>()
    private val lock = Any()
    private val isRecording = AtomicBoolean(false)
    private val captureStartMs = AtomicLong(0L)
    private var latestGyro: FloatArray? = null

    private val sensorListener = object : SensorEventListener {
        override fun onSensorChanged(event: SensorEvent) {
            if (!isRecording.get()) return
            val tMs = System.currentTimeMillis() - captureStartMs.get()
            synchronized(lock) {
                when (event.sensor.type) {
                    Sensor.TYPE_GYROSCOPE -> {
                        latestGyro = event.values.copyOf()
                    }
                    Sensor.TYPE_ACCELEROMETER -> {
                        val gyro = latestGyro
                        samples += IMUSample(
                            timestampMs = tMs,
                            ax = event.values[0],
                            ay = event.values[1],
                            az = event.values[2],
                            gx = gyro?.getOrNull(0),
                            gy = gyro?.getOrNull(1),
                            gz = gyro?.getOrNull(2),
                        )
                    }
                }
            }
        }

        override fun onAccuracyChanged(sensor: Sensor, accuracy: Int) {}
    }

    fun startCapture(startMs: Long = System.currentTimeMillis()) {
        if (isRecording.compareAndSet(false, true)) {
            captureStartMs.set(startMs)
            synchronized(lock) {
                samples.clear()
                latestGyro = null
            }
            gyroscope?.let {
                sensorManager.registerListener(sensorListener, it, SensorManager.SENSOR_DELAY_GAME)
            }
            accelerometer?.let {
                sensorManager.registerListener(sensorListener, it, SensorManager.SENSOR_DELAY_GAME)
            }
        }
    }

    fun stopCapture(): List<IMUSample> {
        if (isRecording.compareAndSet(true, false)) {
            sensorManager.unregisterListener(sensorListener)
        }
        return synchronized(lock) { samples.toList() }
    }

    fun sampleCount(): Int = synchronized(lock) { samples.size }

    /**
     * Stops recording, serializes all samples as JSONL to [outputDir]/imu_samples.jsonl,
     * and returns the written file.
     */
    fun writeToFile(outputDir: File): File {
        val imuSamples = stopCapture()
        val json = Json { encodeDefaults = true; explicitNulls = false }
        val file = outputDir.resolve("imu_samples.jsonl")
        file.bufferedWriter().use { writer ->
            imuSamples.forEach { sample ->
                writer.write(json.encodeToString(sample))
                writer.newLine()
            }
        }
        return file
    }

    fun release() {
        sensorManager.unregisterListener(sensorListener)
        isRecording.set(false)
    }
}
