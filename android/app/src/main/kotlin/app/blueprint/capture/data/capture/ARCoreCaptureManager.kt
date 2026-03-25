package app.blueprint.capture.data.capture

import android.content.Context
import android.media.Image
import android.os.SystemClock
import androidx.annotation.VisibleForTesting
import com.google.ar.core.Config
import com.google.ar.core.Frame
import com.google.ar.core.LightEstimate
import com.google.ar.core.Plane
import com.google.ar.core.PointCloud
import com.google.ar.core.Pose
import com.google.ar.core.RecordingConfig
import com.google.ar.core.Session
import com.google.ar.core.TrackingState
import com.google.ar.core.exceptions.CameraNotAvailableException
import com.google.ar.core.exceptions.NotYetAvailableException
import com.google.ar.core.exceptions.RecordingFailedException
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONArray
import org.json.JSONObject

data class ARCoreCaptureArtifacts(
    val recordingFile: File,
    val arcoreEvidenceDirectory: File,
    val coordinateFrameSessionId: String,
    val captureStartEpochMs: Long,
    val durationMs: Long,
    val frameCount: Int,
)

class ARCoreCaptureManager(
    private val context: Context,
    private val evidenceRecorder: ARCoreEvidenceRecorder = ARCoreEvidenceRecorder(),
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val stateMutex = Mutex()

    private var session: Session? = null
    private var captureLoopJob: Job? = null
    private var captureArtifacts: ActiveCapture? = null
    private val stopRequested = AtomicBoolean(false)

    suspend fun startCapture(
        outputDirectory: File,
        captureStartEpochMs: Long,
    ): Result<Unit> = stateMutex.withLock {
        runCatching {
            check(captureArtifacts == null) { "ARCore capture is already active." }
            outputDirectory.mkdirs()

            val activeSession = Session(context).also(::configureSession)
            val recordingFile = outputDirectory.resolve("walkthrough.mp4")
            val arcoreRoot = evidenceRecorder.prepareOutput(outputDirectory)
            val depthManifest = DepthManifest()
            val confidenceManifest = ConfidenceManifest()
            val recordingConfig = RecordingConfig(activeSession)
                .setMp4DatasetFilePath(recordingFile.absolutePath)
                .setAutoStopOnPause(true)

            try {
                activeSession.startRecording(recordingConfig)
                activeSession.resume()
            } catch (error: RecordingFailedException) {
                activeSession.close()
                throw error
            } catch (error: CameraNotAvailableException) {
                activeSession.close()
                throw error
            }

            val activeCapture = ActiveCapture(
                recordingFile = recordingFile,
                arcoreRoot = arcoreRoot,
                captureStartEpochMs = captureStartEpochMs,
                monotonicStartNs = SystemClock.elapsedRealtimeNanos(),
                session = activeSession,
                depthManifest = depthManifest,
                confidenceManifest = confidenceManifest,
            )
            stopRequested.set(false)
            session = activeSession
            captureArtifacts = activeCapture
            captureLoopJob = scope.launch {
                runCaptureLoop(activeCapture)
            }
        }
    }

    suspend fun stopCapture(): Result<ARCoreCaptureArtifacts> {
        val activeCapture = stateMutex.withLock {
            captureArtifacts ?: return Result.failure(IllegalStateException("ARCore capture is not active."))
        }
        stopRequested.set(true)
        captureLoopJob?.cancelAndJoin()

        return stateMutex.withLock {
            runCatching {
                finalizeCapture(activeCapture)
            }.also {
                captureLoopJob = null
                captureArtifacts = null
                session = null
                stopRequested.set(false)
            }
        }
    }

    suspend fun close() {
        val activeCapture = stateMutex.withLock { captureArtifacts }
        stopRequested.set(true)
        captureLoopJob?.cancelAndJoin()
        stateMutex.withLock {
            runCatching {
                activeCapture?.session?.pause()
            }
            runCatching {
                activeCapture?.session?.close()
            }
            captureLoopJob = null
            captureArtifacts = null
            session = null
            stopRequested.set(false)
        }
    }

    private fun configureSession(session: Session) {
        val config = Config(session).apply {
            setFocusMode(Config.FocusMode.AUTO)
            setPlaneFindingMode(Config.PlaneFindingMode.HORIZONTAL_AND_VERTICAL)
            setLightEstimationMode(Config.LightEstimationMode.ENVIRONMENTAL_HDR)
            setUpdateMode(Config.UpdateMode.LATEST_CAMERA_IMAGE)
            if (session.isDepthModeSupported(Config.DepthMode.AUTOMATIC)) {
                setDepthMode(Config.DepthMode.AUTOMATIC)
            }
        }
        session.configure(config)
    }

    private suspend fun runCaptureLoop(activeCapture: ActiveCapture) {
        while (scope.isActive && !stopRequested.get()) {
            val frame = try {
                activeCapture.session.update()
            } catch (_: CameraNotAvailableException) {
                break
            } catch (_: Throwable) {
                break
            }
            processFrame(activeCapture, frame)
            delay(12L)
        }
    }

    private fun processFrame(activeCapture: ActiveCapture, frame: Frame) {
        val camera = frame.camera
        val frameTimestampNs = frame.timestamp
        if (frameTimestampNs <= 0L) return

        val captureTimeSec = ((frameTimestampNs - activeCapture.firstFrameTimestampNs(frameTimestampNs)) / 1_000_000_000.0)
            .coerceAtLeast(0.0)
        val frameIndex = activeCapture.nextFrameIndex()
        val frameId = frameIndex.toFrameId()
        val trackingState = camera.trackingState
        val trackingReason = camera.trackingFailureReason.name.lowercase(Locale.US)
        val capturedAt = ISO_8601.format(Instant.ofEpochMilli(activeCapture.captureStartEpochMs + (captureTimeSec * 1000.0).toLong()))

        if (!activeCapture.intrinsicsWritten) {
            val imageIntrinsics = camera.imageIntrinsics
            val focalLength = imageIntrinsics.focalLength
            val principalPoint = imageIntrinsics.principalPoint
            val dimensions = imageIntrinsics.imageDimensions
            val payload = JSONObject(
                mapOf(
                    "schema_version" to "v1",
                    "camera_model" to "pinhole",
                    "source" to "arcore",
                    "coordinate_frame_session_id" to activeCapture.coordinateFrameSessionId,
                    "fx" to focalLength.getOrNull(0),
                    "fy" to focalLength.getOrNull(1),
                    "cx" to principalPoint.getOrNull(0),
                    "cy" to principalPoint.getOrNull(1),
                    "width" to dimensions.getOrNull(0),
                    "height" to dimensions.getOrNull(1),
                ),
            )
            evidenceRecorder.writeSessionIntrinsics(activeCapture.arcoreRoot, payload.toString(2))
            activeCapture.intrinsicsWritten = true
        }

        evidenceRecorder.appendJsonLine(
            activeCapture.arcoreRoot,
            "frames.jsonl",
            JSONObject(
                mapOf(
                    "schema_version" to "v1",
                    "frame_id" to frameId,
                    "frame_index" to frameIndex,
                    "t_capture_sec" to round6(captureTimeSec),
                    "t_monotonic_ns" to activeCapture.monotonicStartNs + frameTimestampNs - activeCapture.firstFrameTimestampNs(frameTimestampNs),
                    "timestamp_ns" to frameTimestampNs,
                    "android_camera_timestamp_ns" to frame.androidCameraTimestamp,
                    "captured_at" to capturedAt,
                    "coordinate_frame_session_id" to activeCapture.coordinateFrameSessionId,
                ),
            ).toString(),
        )

        evidenceRecorder.appendJsonLine(
            activeCapture.arcoreRoot,
            "tracking_state.jsonl",
            JSONObject(
                mapOf(
                    "schema_version" to "v1",
                    "frame_id" to frameId,
                    "t_capture_sec" to round6(captureTimeSec),
                    "tracking_state" to trackingState.name.lowercase(Locale.US),
                    "tracking_reason" to if (trackingState == TrackingState.TRACKING) null else trackingReason,
                    "coordinate_frame_session_id" to activeCapture.coordinateFrameSessionId,
                ),
            ).toString(),
        )

        if (trackingState == TrackingState.TRACKING) {
            evidenceRecorder.appendJsonLine(
                activeCapture.arcoreRoot,
                "poses.jsonl",
                JSONObject(
                    mapOf(
                        "schema_version" to "v1",
                        "frame_id" to frameId,
                        "frame_index" to frameIndex,
                        "t_capture_sec" to round6(captureTimeSec),
                        "t_monotonic_ns" to activeCapture.monotonicStartNs + frameTimestampNs - activeCapture.firstFrameTimestampNs(frameTimestampNs),
                        "timestamp_ns" to frameTimestampNs,
                        "coordinate_frame_session_id" to activeCapture.coordinateFrameSessionId,
                        "T_world_camera" to poseToRowMajor(camera.pose),
                        "tracking_state" to trackingState.name.lowercase(Locale.US),
                        "tracking_reason" to null,
                    ),
                ).toString(),
            )
        }

        runCatching {
            frame.acquirePointCloud().use { pointCloud ->
                if (pointCloud.timestamp <= 0L) return@use
                evidenceRecorder.appendJsonLine(
                    activeCapture.arcoreRoot,
                    "point_cloud.jsonl",
                    JSONObject(
                        mapOf(
                            "schema_version" to "v1",
                            "frame_id" to frameId,
                            "t_capture_sec" to round6(captureTimeSec),
                            "timestamp_ns" to pointCloud.timestamp,
                            "coordinate_frame_session_id" to activeCapture.coordinateFrameSessionId,
                            "points" to floatBufferToNestedPoints(pointCloud),
                            "ids" to intBufferToList(pointCloud),
                        ),
                    ).toString(),
                )
            }
        }

        val updatedPlanes = frame.getUpdatedTrackables(Plane::class.java)
        if (updatedPlanes.isNotEmpty()) {
            updatedPlanes.forEach { plane ->
                evidenceRecorder.appendJsonLine(
                    activeCapture.arcoreRoot,
                    "planes.jsonl",
                    JSONObject(
                        mapOf(
                            "schema_version" to "v1",
                            "frame_id" to frameId,
                            "t_capture_sec" to round6(captureTimeSec),
                            "plane_id" to "plane_${plane.hashCode()}",
                            "plane_type" to plane.type.name.lowercase(Locale.US),
                            "tracking_state" to plane.trackingState.name.lowercase(Locale.US),
                            "center_pose" to poseToRowMajor(plane.centerPose),
                            "extent_x_m" to round6(plane.extentX.toDouble()),
                            "extent_z_m" to round6(plane.extentZ.toDouble()),
                            "polygon_vertices" to floatBufferToList(plane.polygon),
                            "coordinate_frame_session_id" to activeCapture.coordinateFrameSessionId,
                        ),
                    ).toString(),
                )
            }
        }

        val lightEstimate = frame.lightEstimate
        if (lightEstimate.state == LightEstimate.State.VALID) {
            evidenceRecorder.appendJsonLine(
                activeCapture.arcoreRoot,
                "light_estimates.jsonl",
                JSONObject(
                    mapOf(
                        "schema_version" to "v1",
                        "frame_id" to frameId,
                        "t_capture_sec" to round6(captureTimeSec),
                        "timestamp_ns" to lightEstimate.timestamp,
                        "pixel_intensity" to round6(lightEstimate.pixelIntensity.toDouble()),
                        "color_correction" to floatArrayToList(FloatArray(4).also { lightEstimate.getColorCorrection(it, 0) }),
                        "main_light_direction" to floatArrayToList(lightEstimate.environmentalHdrMainLightDirection),
                        "main_light_intensity" to floatArrayToList(lightEstimate.environmentalHdrMainLightIntensity),
                        "ambient_spherical_harmonics" to floatArrayToList(lightEstimate.environmentalHdrAmbientSphericalHarmonics),
                        "coordinate_frame_session_id" to activeCapture.coordinateFrameSessionId,
                    ),
                ).toString(),
            )
        }

        captureDepthArtifacts(activeCapture, frame, frameId, captureTimeSec)
    }

    private fun captureDepthArtifacts(
        activeCapture: ActiveCapture,
        frame: Frame,
        frameId: String,
        captureTimeSec: Double,
    ) {
        runCatching {
            frame.acquireDepthImage16Bits().use { image ->
                val relativePath = "depth/$frameId.raw"
                writeRawImage(activeCapture.arcoreRoot.resolve(relativePath), image)
                activeCapture.depthManifest.frames += mapOf(
                    "frame_id" to frameId,
                    "t_capture_sec" to round6(captureTimeSec),
                    "depth_path" to "arcore/$relativePath",
                    "width" to image.width,
                    "height" to image.height,
                    "image_format" to "depth16",
                    "coordinate_frame_session_id" to activeCapture.coordinateFrameSessionId,
                )
            }
        }
        runCatching {
            frame.acquireRawDepthConfidenceImage().use { image ->
                val relativePath = "confidence/$frameId.raw"
                writeRawImage(activeCapture.arcoreRoot.resolve(relativePath), image)
                activeCapture.confidenceManifest.frames += mapOf(
                    "frame_id" to frameId,
                    "t_capture_sec" to round6(captureTimeSec),
                    "confidence_path" to "arcore/$relativePath",
                    "width" to image.width,
                    "height" to image.height,
                    "image_format" to "raw_depth_confidence",
                    "coordinate_frame_session_id" to activeCapture.coordinateFrameSessionId,
                )
            }
        }
    }

    private fun finalizeCapture(activeCapture: ActiveCapture): ARCoreCaptureArtifacts {
        try {
            activeCapture.session.stopRecording()
        } catch (_: RecordingFailedException) {
        }
        runCatching { activeCapture.session.pause() }
        runCatching { activeCapture.session.close() }

        writeManifest(activeCapture.arcoreRoot.resolve("depth_manifest.json"), activeCapture.depthManifest.toJson())
        writeManifest(activeCapture.arcoreRoot.resolve("confidence_manifest.json"), activeCapture.confidenceManifest.toJson())

        val durationMs = (SystemClock.elapsedRealtimeNanos() - activeCapture.monotonicStartNs) / 1_000_000L
        return ARCoreCaptureArtifacts(
            recordingFile = activeCapture.recordingFile,
            arcoreEvidenceDirectory = activeCapture.arcoreRoot,
            coordinateFrameSessionId = activeCapture.coordinateFrameSessionId,
            captureStartEpochMs = activeCapture.captureStartEpochMs,
            durationMs = durationMs.coerceAtLeast(0L),
            frameCount = activeCapture.frameCount,
        )
    }

    private fun writeManifest(file: File, jsonObject: JSONObject) {
        file.parentFile?.mkdirs()
        file.writeText(jsonObject.toString(2))
    }

    private fun writeRawImage(file: File, image: Image) {
        file.parentFile?.mkdirs()
        FileOutputStream(file).use { output ->
            image.planes.forEachIndexed { planeIndex, plane ->
                val buffer = plane.buffer.duplicate()
                val bytes = ByteArray(buffer.remaining())
                buffer.get(bytes)
                if (planeIndex == 0) {
                    output.write(bytes)
                }
            }
        }
    }

    @VisibleForTesting
    internal fun poseToRowMajor(pose: Pose): List<List<Double>> = poseToRowMajorStatic(pose)

    private data class ActiveCapture(
        val recordingFile: File,
        val arcoreRoot: File,
        val captureStartEpochMs: Long,
        val monotonicStartNs: Long,
        val session: Session,
        val depthManifest: DepthManifest,
        val confidenceManifest: ConfidenceManifest,
        val coordinateFrameSessionId: String = "cfs_${Instant.now().toEpochMilli()}",
        var intrinsicsWritten: Boolean = false,
        var frameCount: Int = 0,
        var firstTimestampNs: Long? = null,
    ) {
        fun nextFrameIndex(): Int {
            frameCount += 1
            return frameCount - 1
        }

        fun firstFrameTimestampNs(current: Long): Long {
            val existing = firstTimestampNs
            if (existing != null) return existing
            firstTimestampNs = current
            return current
        }
    }

    private data class DepthManifest(
        val schemaVersion: String = "v1",
        val representation: String = "per_frame_depth_image",
        val imageEncoding: String = "raw_sensor_bytes",
        val frames: MutableList<Map<String, Any?>> = mutableListOf(),
    ) {
        fun toJson(): JSONObject = JSONObject(
            mapOf(
                "schema_version" to schemaVersion,
                "representation" to representation,
                "image_encoding" to imageEncoding,
                "frame_count" to frames.size,
                "frames" to JSONArray(frames),
            ),
        )
    }

    private data class ConfidenceManifest(
        val schemaVersion: String = "v1",
        val representation: String = "per_frame_confidence_image",
        val imageEncoding: String = "raw_sensor_bytes",
        val frames: MutableList<Map<String, Any?>> = mutableListOf(),
    ) {
        fun toJson(): JSONObject = JSONObject(
            mapOf(
                "schema_version" to schemaVersion,
                "representation" to representation,
                "image_encoding" to imageEncoding,
                "frame_count" to frames.size,
                "frames" to JSONArray(frames),
            ),
        )
    }

    companion object {
        private val ISO_8601: DateTimeFormatter =
            DateTimeFormatter.ISO_OFFSET_DATE_TIME.withZone(ZoneOffset.UTC)

        private fun Int.toFrameId(): String = String.format(Locale.US, "%06d", this + 1)

        private fun round6(value: Double): Double = String.format(Locale.US, "%.6f", value).toDouble()

        private fun poseToRowMajorStatic(pose: Pose): List<List<Double>> {
            val columnMajor = FloatArray(16)
            pose.toMatrix(columnMajor, 0)
            return listOf(
                listOf(columnMajor[0], columnMajor[4], columnMajor[8], columnMajor[12]),
                listOf(columnMajor[1], columnMajor[5], columnMajor[9], columnMajor[13]),
                listOf(columnMajor[2], columnMajor[6], columnMajor[10], columnMajor[14]),
                listOf(columnMajor[3], columnMajor[7], columnMajor[11], columnMajor[15]),
            ).map { row -> row.map { round6(it.toDouble()) } }
        }

        private fun floatArrayToList(values: FloatArray?): List<Double> =
            values?.map { round6(it.toDouble()) } ?: emptyList()

        private fun floatBufferToList(buffer: java.nio.FloatBuffer?): List<Double> {
            if (buffer == null) return emptyList()
            val duplicate = buffer.duplicate()
            val values = ArrayList<Double>(duplicate.remaining())
            while (duplicate.hasRemaining()) {
                values += round6(duplicate.get().toDouble())
            }
            return values
        }

        private fun floatBufferToNestedPoints(pointCloud: PointCloud): List<List<Double>> {
            val duplicate = pointCloud.points.duplicate()
            val rows = mutableListOf<List<Double>>()
            while (duplicate.remaining() >= 4) {
                rows += listOf(
                    round6(duplicate.get().toDouble()),
                    round6(duplicate.get().toDouble()),
                    round6(duplicate.get().toDouble()),
                    round6(duplicate.get().toDouble()),
                )
            }
            return rows
        }

        private fun intBufferToList(pointCloud: PointCloud): List<Int> {
            val duplicate = pointCloud.ids.duplicate()
            val ids = ArrayList<Int>(duplicate.remaining())
            while (duplicate.hasRemaining()) {
                ids += duplicate.get()
            }
            return ids
        }
    }
}
