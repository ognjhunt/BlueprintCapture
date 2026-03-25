package app.blueprint.capture.data.glasses.androidxr

import androidx.activity.ComponentActivity
import androidx.camera.core.CameraSelector
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.video.FileOutputOptions
import androidx.camera.video.FallbackStrategy
import androidx.camera.video.Quality
import androidx.camera.video.QualitySelector
import androidx.camera.video.Recorder
import androidx.camera.video.Recording
import androidx.camera.video.VideoCapture
import androidx.camera.video.VideoRecordEvent
import androidx.core.content.ContextCompat
import java.io.File
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine

class AndroidXrProjectedCaptureManager(
    private val activity: ComponentActivity,
) {
    private var cameraProvider: ProcessCameraProvider? = null
    private var videoCapture: VideoCapture<Recorder>? = null

    suspend fun prepare(): Result<Unit> = suspendCoroutine { continuation ->
        val future = ProcessCameraProvider.getInstance(activity)
        future.addListener(
            {
                val result = runCatching {
                    val provider = future.get()
                    val recorder = Recorder.Builder()
                        .setQualitySelector(
                            QualitySelector.from(
                                Quality.HD,
                                FallbackStrategy.lowerQualityOrHigherThan(Quality.SD),
                            ),
                        )
                        .build()
                    val captureUseCase = VideoCapture.withOutput(recorder)
                    provider.unbindAll()
                    provider.bindToLifecycle(
                        activity,
                        CameraSelector.DEFAULT_BACK_CAMERA,
                        captureUseCase,
                    )
                    cameraProvider = provider
                    videoCapture = captureUseCase
                }
                continuation.resume(result)
            },
            ContextCompat.getMainExecutor(activity),
        )
    }

    fun startRecording(
        outputFile: File,
        withAudio: Boolean,
        onEvent: (VideoRecordEvent) -> Unit,
    ): Result<Recording> = runCatching {
        val captureUseCase = videoCapture ?: error("Projected camera is not ready.")
        var pendingRecording = captureUseCase.output.prepareRecording(
            activity,
            FileOutputOptions.Builder(outputFile).build(),
        )
        if (withAudio) {
            pendingRecording = pendingRecording.withAudioEnabled()
        }
        pendingRecording.start(ContextCompat.getMainExecutor(activity), onEvent)
    }

    fun close() {
        runCatching { cameraProvider?.unbindAll() }
        cameraProvider = null
        videoCapture = null
    }
}
