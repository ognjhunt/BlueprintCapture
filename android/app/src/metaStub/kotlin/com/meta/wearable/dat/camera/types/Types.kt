package com.meta.wearable.dat.camera.types

enum class StreamSessionState {
    STREAMING,
    CLOSED,
}

enum class VideoQuality {
    HIGH,
}

data class StreamConfiguration(
    val videoQuality: VideoQuality,
    val frameRate: Int,
)
