package app.blueprint.capture.data.glasses

enum class AndroidXrUxMode {
    WaitingForDevice,
    AudioOnlyGlasses,
    DisplayGlasses,
}

data class AndroidXrUxState(
    val mode: AndroidXrUxMode,
    val title: String,
    val body: String,
    val capabilitySummary: List<String>,
    val primaryAction: String,
) {
    companion object {
        fun from(
            isProjectedDeviceConnected: Boolean,
            capabilities: GlassesCapabilities,
            hasCaptureTarget: Boolean,
        ): AndroidXrUxState {
            if (!isProjectedDeviceConnected) {
                return AndroidXrUxState(
                    mode = AndroidXrUxMode.WaitingForDevice,
                    title = "Waiting for Android XR glasses",
                    body = "Pair audio glasses or display glasses with this phone before launching a projected Blueprint session. This does not prove public launch, payout, or provider readiness.",
                    capabilitySummary = listOf(
                        "Display state unknown",
                        "Projected camera unverified",
                        "Projected mic unverified",
                        "World tracking unverified",
                    ),
                    primaryAction = "Open Android XR readiness mode",
                )
            }

            val worldTracking = "World tracking unverified"
            val camera = if (capabilities.supportsProjectedCamera) "Projected camera" else "Projected camera unavailable"
            val mic = if (capabilities.supportsProjectedMic) "Projected mic" else "Projected mic unavailable"

            return if (capabilities.hasDisplay) {
                AndroidXrUxState(
                    mode = AndroidXrUxMode.DisplayGlasses,
                    title = "Display-glasses Android XR",
                    body = "Visual projected UI is available. Keep controls high-contrast and readable on additive or transparent displays; projected capability bits do not prove world tracking, geospatial authority, or payout readiness.",
                    capabilitySummary = listOf("Display UI available", camera, mic, worldTracking),
                    primaryAction = if (hasCaptureTarget) "Launch display XR capture" else "Open display XR readiness mode",
                )
            } else {
                AndroidXrUxState(
                    mode = AndroidXrUxMode.AudioOnlyGlasses,
                    title = "Audio-only Android XR glasses",
                    body = "Use a voice-led flow with no projected visual UI. Projected camera and mic artifacts can support a raw bundle, but they do not prove world tracking, geospatial authority, or payout readiness.",
                    capabilitySummary = listOf("No visual display", camera, mic, worldTracking),
                    primaryAction = if (hasCaptureTarget) "Launch audio-guided XR capture" else "Open audio-guided XR readiness mode",
                )
            }
        }
    }
}
