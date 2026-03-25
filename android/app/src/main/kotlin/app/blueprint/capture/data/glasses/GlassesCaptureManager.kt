package app.blueprint.capture.data.glasses

import android.content.Context
import android.graphics.BitmapFactory
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import androidx.annotation.VisibleForTesting
import com.meta.wearable.dat.camera.StreamSession
import com.meta.wearable.dat.camera.startStreamSession
import com.meta.wearable.dat.camera.types.StreamConfiguration
import com.meta.wearable.dat.camera.types.StreamSessionState
import com.meta.wearable.dat.camera.types.VideoQuality
import com.meta.wearable.dat.core.Wearables
import com.meta.wearable.dat.core.selectors.AutoDeviceSelector
import com.meta.wearable.dat.core.selectors.SpecificDeviceSelector
import com.meta.wearable.dat.core.types.DeviceIdentifier
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.File
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Locale
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

sealed class GlassesCaptureState {
    object Idle : GlassesCaptureState()
    object Preparing : GlassesCaptureState()
    data class Streaming(
        val fps: Double,
        val framesReceived: Int,
        val durationSec: Double,
    ) : GlassesCaptureState()
    object Paused : GlassesCaptureState()
    data class Finished(val artifacts: GlassesCaptureArtifacts) : GlassesCaptureState()
    data class Error(val message: String) : GlassesCaptureState()
}

data class GlassesCaptureArtifacts(
    val videoFile: File,
    val framesDirectory: File,
    val metadataFile: File,
    val glassesEvidenceDirectory: File,
    val companionPhoneDirectory: File?,
    val durationMs: Long,
    val frameCount: Int,
)

@Singleton
class GlassesCaptureManager @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    private val _captureState = MutableStateFlow<GlassesCaptureState>(GlassesCaptureState.Idle)
    val captureState: StateFlow<GlassesCaptureState> = _captureState.asStateFlow()

    private val managerScope = CoroutineScope(Dispatchers.IO)
    private var streamSession: StreamSession? = null
    private var captureJob: Job? = null
    private var currentOutputDir: File? = null

    // Lightweight frame tracking — frames are written to disk, not held in memory.
    private val frameTimestamps = mutableListOf<Long>()
    private var captureStartMs = 0L
    private var framesReceivedCount = 0
    private var lastFpsWindowMs = 0L
    private var framesInWindow = 0

    val sessionState: StateFlow<StreamSessionState>?
        get() = streamSession?.state

    suspend fun connect(deviceIdentifier: DeviceIdentifier? = null): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching {
            _captureState.value = GlassesCaptureState.Preparing
            val selector = if (deviceIdentifier != null) {
                SpecificDeviceSelector(deviceIdentifier)
            } else {
                AutoDeviceSelector()
            }
            val config = StreamConfiguration(
                videoQuality = VideoQuality.HIGH,
                frameRate = 30,
            )
            val session = Wearables.startStreamSession(context, selector, config)
            streamSession = session

            // Wait for streaming state or session close.
            session.state.first { s ->
                s == StreamSessionState.STREAMING || s == StreamSessionState.CLOSED
            }
            if (session.state.value == StreamSessionState.CLOSED) {
                _captureState.value = GlassesCaptureState.Error("Connection closed before streaming began")
                error("Session closed before streaming")
            }
            _captureState.value = GlassesCaptureState.Idle
        }
    }

    suspend fun startCapture(outputDir: File) {
        val session = streamSession ?: return
        currentOutputDir = outputDir

        frameTimestamps.clear()
        framesReceivedCount = 0
        captureStartMs = System.currentTimeMillis()
        lastFpsWindowMs = captureStartMs
        framesInWindow = 0

        val framesDir = File(outputDir, "frames").also { it.mkdirs() }
        _captureState.value = GlassesCaptureState.Streaming(fps = 0.0, framesReceived = 0, durationSec = 0.0)

        captureJob = managerScope.launch {
            collectFrames(session, framesDir)
        }
    }

    private suspend fun collectFrames(session: StreamSession, framesDir: File) {
        session.videoStream.collect { frame ->
            val idx = ++framesReceivedCount
            frameTimestamps.add(frame.presentationTimeUs)

            // Write raw frame bytes to disk.
            val frameBuffer = frame.buffer.duplicate()
            val bytes = ByteArray(frameBuffer.remaining())
            frameBuffer.get(bytes)
            File(framesDir, "frame_%06d.bin".format(idx)).writeBytes(bytes)

            // Update streaming state approximately once per second.
            framesInWindow++
            val nowMs = System.currentTimeMillis()
            val windowMs = nowMs - lastFpsWindowMs
            if (windowMs >= 1000L) {
                val fps = framesInWindow * 1000.0 / windowMs
                framesInWindow = 0
                lastFpsWindowMs = nowMs
                _captureState.value = GlassesCaptureState.Streaming(
                    fps = fps,
                    framesReceived = framesReceivedCount,
                    durationSec = (nowMs - captureStartMs) / 1000.0,
                )
            }
        }
    }

    fun pauseCapture() {
        captureJob?.cancel()
        captureJob = null
        _captureState.value = GlassesCaptureState.Paused
    }

    fun resumeCapture() {
        val session = streamSession ?: return
        val dir = currentOutputDir ?: return
        val framesDir = File(dir, "frames")
        _captureState.value = GlassesCaptureState.Streaming(
            fps = 0.0,
            framesReceived = framesReceivedCount,
            durationSec = (System.currentTimeMillis() - captureStartMs) / 1000.0,
        )
        captureJob = managerScope.launch { collectFrames(session, framesDir) }
    }

    suspend fun stopCapture(): GlassesCaptureArtifacts = withContext(Dispatchers.IO) {
        captureJob?.cancel()
        captureJob = null

        val outputDir = currentOutputDir
            ?: throw IllegalStateException("stopCapture called without a prior startCapture")
        val durationMs = System.currentTimeMillis() - captureStartMs
        val framesDir = File(outputDir, "frames")
        val videoFile = File(outputDir, "walkthrough.mp4")

        // Encode frames to MP4 (best-effort; frames remain on disk as fallback).
        val frameFiles = framesDir.listFiles()
            ?.filter { it.extension == "bin" }
            ?.sortedBy { it.name }
            ?: emptyList()
        if (frameFiles.isNotEmpty()) {
            runCatching { encodeFramesToMp4(frameFiles, videoFile) }
        }

        val metadataFile = File(outputDir, "capture_metadata.json").apply {
            writeText(
                """{"source":"meta_glasses","frames":$framesReceivedCount,"duration_ms":$durationMs}""",
            )
        }
        val streamMetrics = inferStreamMetrics(
            frameFiles = frameFiles,
            durationMs = durationMs,
            frameCount = framesReceivedCount,
            framePresentationTimesUs = frameTimestamps.toList(),
        )
        val evidenceDirectories = writeCanonicalEvidence(
            outputDir = outputDir,
            captureStartMs = captureStartMs,
            framePresentationTimesUs = frameTimestamps.toList(),
            streamWidth = streamMetrics.width,
            streamHeight = streamMetrics.height,
            streamFps = streamMetrics.fps,
        )

        val artifacts = GlassesCaptureArtifacts(
            videoFile = videoFile,
            framesDirectory = framesDir,
            metadataFile = metadataFile,
            glassesEvidenceDirectory = evidenceDirectories.glassesDirectory,
            companionPhoneDirectory = evidenceDirectories.companionPhoneDirectory,
            durationMs = durationMs,
            frameCount = framesReceivedCount,
        )
        frameTimestamps.clear()
        _captureState.value = GlassesCaptureState.Finished(artifacts)
        artifacts
    }

    fun disconnect() {
        captureJob?.cancel()
        captureJob = null
        streamSession?.close()
        streamSession = null
        currentOutputDir = null
        frameTimestamps.clear()
        _captureState.value = GlassesCaptureState.Idle
    }

    private fun writeCanonicalEvidence(
        outputDir: File,
        captureStartMs: Long,
        framePresentationTimesUs: List<Long>,
        streamWidth: Int?,
        streamHeight: Int?,
        streamFps: Double?,
    ): CanonicalEvidenceDirectories = Companion.writeCanonicalEvidence(
        outputDir = outputDir,
        captureStartMs = captureStartMs,
        framePresentationTimesUs = framePresentationTimesUs,
        streamWidth = streamWidth,
        streamHeight = streamHeight,
        streamFps = streamFps,
    )

    // ── Frame encoding ────────────────────────────────────────────────────────

    /**
     * Encodes a directory of raw frame files to walkthrough.mp4.
     *
     * Frame files are expected to contain JPEG-encoded data (the MWDAT SDK streams
     * compressed camera frames). If the first frame can't be decoded as JPEG the
     * function returns without creating the video file.
     */
    private fun encodeFramesToMp4(frameFiles: List<File>, outputFile: File) {
        val firstData = frameFiles.first().readBytes()
        val firstBitmap = BitmapFactory.decodeByteArray(firstData, 0, firstData.size) ?: return
        val videoWidth = firstBitmap.width
        val videoHeight = firstBitmap.height
        firstBitmap.recycle()

        val mimeType = MediaFormat.MIMETYPE_VIDEO_AVC
        val format = MediaFormat.createVideoFormat(mimeType, videoWidth, videoHeight).apply {
            setInteger(MediaFormat.KEY_BIT_RATE, 4_000_000)
            setInteger(MediaFormat.KEY_FRAME_RATE, 30)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
        }

        val encoder = MediaCodec.createEncoderByType(mimeType)
        encoder.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        val inputSurface = encoder.createInputSurface()
        val muxer = MediaMuxer(outputFile.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        encoder.start()

        val bufferInfo = MediaCodec.BufferInfo()
        var trackIndex = -1
        var muxerStarted = false

        fun drainEncoder(eos: Boolean) {
            if (eos) encoder.signalEndOfInputStream()
            loop@ while (true) {
                val idx = encoder.dequeueOutputBuffer(bufferInfo, 10_000L)
                when {
                    idx == MediaCodec.INFO_TRY_AGAIN_LATER -> if (!eos) break@loop
                    idx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        trackIndex = muxer.addTrack(encoder.outputFormat)
                        muxer.start()
                        muxerStarted = true
                    }
                    idx >= 0 -> {
                        val buf = encoder.getOutputBuffer(idx)!!
                        val isConfig = bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
                        if (!isConfig && muxerStarted && bufferInfo.size > 0) {
                            buf.position(bufferInfo.offset)
                            buf.limit(bufferInfo.offset + bufferInfo.size)
                            muxer.writeSampleData(trackIndex, buf, bufferInfo)
                        }
                        encoder.releaseOutputBuffer(idx, false)
                        if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break@loop
                    }
                }
            }
        }

        try {
            frameFiles.forEach { file ->
                val data = file.readBytes()
                val bitmap = BitmapFactory.decodeByteArray(data, 0, data.size) ?: return@forEach
                val canvas = inputSurface.lockCanvas(null)
                canvas.drawBitmap(bitmap, 0f, 0f, null)
                inputSurface.unlockCanvasAndPost(canvas)
                bitmap.recycle()
                drainEncoder(false)
            }
            drainEncoder(true)
        } finally {
            encoder.stop()
            encoder.release()
            if (muxerStarted) {
                muxer.stop()
                muxer.release()
            }
            inputSurface.release()
        }
    }

    private fun inferStreamMetrics(
        frameFiles: List<File>,
        durationMs: Long,
        frameCount: Int,
        framePresentationTimesUs: List<Long>,
    ): StreamMetrics {
        val firstBitmap = frameFiles.firstOrNull()?.let { file ->
            val bytes = runCatching { file.readBytes() }.getOrNull() ?: return@let null
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
        }
        val width = firstBitmap?.width
        val height = firstBitmap?.height
        firstBitmap?.recycle()
        val fps = when {
            framePresentationTimesUs.size >= 2 -> {
                val deltas = framePresentationTimesUs.zipWithNext { a, b -> b - a }.filter { it > 0 }
                val averageDeltaUs = deltas.average()
                if (averageDeltaUs.isFinite() && averageDeltaUs > 0.0) {
                    1_000_000.0 / averageDeltaUs
                } else {
                    null
                }
            }
            durationMs > 0L && frameCount > 0 -> frameCount * 1000.0 / durationMs.toDouble()
            else -> null
        }
        return StreamMetrics(width = width, height = height, fps = fps)
    }

    internal data class CanonicalEvidenceDirectories(
        val glassesDirectory: File,
        val companionPhoneDirectory: File?,
    )

    private data class StreamMetrics(
        val width: Int?,
        val height: Int?,
        val fps: Double?,
    )

    companion object {
        @VisibleForTesting
        internal fun writeCanonicalEvidence(
            outputDir: File,
            captureStartMs: Long,
            framePresentationTimesUs: List<Long>,
            streamWidth: Int?,
            streamHeight: Int?,
            streamFps: Double?,
        ): CanonicalEvidenceDirectories {
            val glassesDirectory = File(outputDir, "glasses").also { it.mkdirs() }
            val streamMetadataFile = File(glassesDirectory, "stream_metadata.json")
            val frameTimestampsFile = File(glassesDirectory, "frame_timestamps.jsonl")
            val deviceStateFile = File(glassesDirectory, "device_state.jsonl")
            val healthEventsFile = File(glassesDirectory, "health_events.jsonl")

            val firstTimestampUs = framePresentationTimesUs.firstOrNull()
            val frameTimestampLines = framePresentationTimesUs.mapIndexed { index, presentationTimeUs ->
                lineJson.encodeToString(
                    JsonObject.serializer(),
                    buildJsonObject {
                        put("schema_version", "v1")
                        put("frame_id", String.format(Locale.US, "%06d", index + 1))
                        put("frame_index", index)
                        put("presentation_time_us", presentationTimeUs)
                        put(
                            "t_capture_sec",
                            round6(
                                if (firstTimestampUs != null) {
                                    (presentationTimeUs - firstTimestampUs) / 1_000_000.0
                                } else {
                                    0.0
                                },
                            ),
                        )
                        put("t_monotonic_ns", presentationTimeUs * 1_000L)
                        put(
                            "captured_at",
                            ISO_8601.format(
                                Instant.ofEpochMilli(
                                    captureStartMs + (((presentationTimeUs - (firstTimestampUs ?: presentationTimeUs)) / 1_000.0).toLong()),
                                ),
                            ),
                        )
                    },
                )
            }
            frameTimestampsFile.writeText(
                frameTimestampLines.joinToString(separator = "\n").let { if (it.isEmpty()) it else "$it\n" },
            )

            val unavailableEvent = lineJson.encodeToString(
                JsonObject.serializer(),
                buildJsonObject {
                    put("schema_version", "v1")
                    put("event", "unavailable_in_public_sdk")
                    put("reason", "public_sdk_not_exposed")
                },
            )
            deviceStateFile.writeText("$unavailableEvent\n")
            healthEventsFile.writeText("$unavailableEvent\n")

            val streamMetadata = buildJsonObject {
                put("schema_version", "v1")
                put("capture_source", "glasses")
                put("device_model", "Meta smart glasses")
                put("frame_count", framePresentationTimesUs.size)
                put("first_party_geometry_available", false)
                put("first_party_motion_available", false)
                put("public_device_state_available", false)
                put("public_health_events_available", false)
                put("companion_phone_pose_available", false)
                put("companion_phone_intrinsics_available", false)
                put("companion_phone_calibration_available", false)
                put(
                    "notes",
                    buildJsonArray {
                        add(JsonPrimitive("Public Android glasses capture does not expose glasses-native pose, IMU, depth, or calibrated extrinsics."))
                    },
                )
                if (streamWidth != null && streamHeight != null) {
                    put(
                        "stream_resolution",
                        buildJsonObject {
                            put("width", streamWidth)
                            put("height", streamHeight)
                        },
                    )
                }
                if (streamFps != null) {
                    put("stream_frame_rate", round3(streamFps))
                }
            }
            streamMetadataFile.writeText(prettyJson.encodeToString(JsonObject.serializer(), streamMetadata))

            return CanonicalEvidenceDirectories(
                glassesDirectory = glassesDirectory,
                companionPhoneDirectory = null,
            )
        }

        private val ISO_8601: DateTimeFormatter =
            DateTimeFormatter.ISO_OFFSET_DATE_TIME.withZone(ZoneOffset.UTC)
        private val prettyJson = Json {
            prettyPrint = true
            encodeDefaults = true
            explicitNulls = false
        }
        private val lineJson = Json {
            prettyPrint = false
            encodeDefaults = true
            explicitNulls = false
        }

        private fun round3(value: Double): Double = String.format(Locale.US, "%.3f", value).toDouble()

        private fun round6(value: Double): Double = String.format(Locale.US, "%.6f", value).toDouble()
    }
}
