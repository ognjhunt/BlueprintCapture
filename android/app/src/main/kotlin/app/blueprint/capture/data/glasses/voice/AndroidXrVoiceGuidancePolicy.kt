package app.blueprint.capture.data.glasses.voice

data class AndroidXrVoiceGuidancePolicy(
    val preferGeminiLive: Boolean,
    val geminiLiveConnector: GeminiLiveConnector,
    val statusMessage: String,
) {
    companion object {
        fun default(): AndroidXrVoiceGuidancePolicy =
            AndroidXrVoiceGuidancePolicy(
                preferGeminiLive = false,
                geminiLiveConnector = UnavailableGeminiLiveConnector(
                    "Gemini Live is not wired to a real Android XR live-audio connector in this build.",
                ),
                statusMessage = "Gemini Live is disabled for Android XR; using on-device speech and text-to-speech fallback.",
            )
    }
}
