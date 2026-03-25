package com.meta.wearable.dat.camera

import android.content.Context
import com.meta.wearable.dat.camera.types.StreamConfiguration
import com.meta.wearable.dat.camera.types.StreamSessionState
import com.meta.wearable.dat.core.Wearables
import com.meta.wearable.dat.core.selectors.DeviceSelector
import java.nio.ByteBuffer
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.emptyFlow

data class VideoFrame(
    val buffer: ByteBuffer = ByteBuffer.allocate(0),
    val presentationTimeUs: Long = 0L,
)

class StreamSession {
    val state = MutableStateFlow(StreamSessionState.CLOSED)
    val videoStream: Flow<VideoFrame> = emptyFlow()

    fun close() {
        state.value = StreamSessionState.CLOSED
    }
}

fun Wearables.startStreamSession(
    context: Context,
    selector: DeviceSelector,
    config: StreamConfiguration,
): StreamSession = StreamSession()
