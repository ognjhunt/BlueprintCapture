package app.blueprint.capture.data.glasses.voice

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

sealed class VoiceSessionState {
    data object Idle : VoiceSessionState()
    data class Starting(val prefersGeminiLive: Boolean) : VoiceSessionState()
    data class Listening(val source: String) : VoiceSessionState()
    data class Thinking(val transcript: String) : VoiceSessionState()
    data class Speaking(val utterance: String, val fallback: Boolean) : VoiceSessionState()
    data class Errored(val message: String) : VoiceSessionState()
    data object Ended : VoiceSessionState()
}

interface GeminiLiveConnector {
    suspend fun startSession(): Result<Unit>
    suspend fun stopSession()
}

interface OnDeviceSpeechInput {
    fun startListening()
    fun stopListening()
    fun release()
}

interface PartialResultsListener {
    fun onPartialTranscript(partial: String)
}

interface VoiceOutput {
    fun speak(text: String, utteranceId: String = DEFAULT_UTTERANCE_ID)
    fun stop()
    fun release()

    companion object {
        const val DEFAULT_UTTERANCE_ID = "voice_output"
        const val WELCOME_UTTERANCE_ID = "welcome"
        const val ERROR_UTTERANCE_ID = "error"
    }
}

class UnavailableGeminiLiveConnector(
    private val message: String = "Gemini Live is not configured in this build.",
) : GeminiLiveConnector {
    override suspend fun startSession(): Result<Unit> = Result.failure(IllegalStateException(message))

    override suspend fun stopSession() = Unit
}

class VoiceSessionOrchestrator(
    private val scope: CoroutineScope,
    private val geminiLiveConnector: GeminiLiveConnector,
    private val speechInput: OnDeviceSpeechInput,
    private val voiceOutput: VoiceOutput,
    private val onStateChanged: (VoiceSessionState) -> Unit,
    private val onTranscript: (String) -> Unit,
    private val onPartialTranscript: (String) -> Unit = {},
    private val continuousListening: Boolean = true,
) {
    private var state: VoiceSessionState = VoiceSessionState.Idle
    private var sessionActive = false

    fun currentState(): VoiceSessionState = state

    fun startSession(
        welcomeText: String,
        preferGeminiLive: Boolean = true,
    ) {
        sessionActive = true
        transitionTo(VoiceSessionState.Starting(prefersGeminiLive = preferGeminiLive))
        scope.launch {
            if (preferGeminiLive) {
                val geminiResult = geminiLiveConnector.startSession()
                if (geminiResult.isSuccess) {
                    transitionTo(VoiceSessionState.Listening(source = "gemini_live"))
                    return@launch
                }
            }

            voiceOutput.speak(
                text = welcomeText,
                utteranceId = VoiceOutput.WELCOME_UTTERANCE_ID,
            )
            transitionTo(VoiceSessionState.Speaking(welcomeText, fallback = true))
        }
    }

    fun notifyUtteranceCompleted(utteranceId: String) {
        if (utteranceId == VoiceOutput.WELCOME_UTTERANCE_ID || utteranceId == VoiceOutput.ERROR_UTTERANCE_ID) {
            beginListening()
        }
    }

    fun notifyPartialResults(partial: String) {
        if (partial.isNotBlank()) {
            onPartialTranscript(partial)
        }
    }

    fun notifySpeechResults(matches: List<String>, confidences: FloatArray? = null) {
        if (matches.isEmpty()) {
            if (continuousListening && sessionActive) beginListening()
            return
        }
        val chosenIndex = confidences
            ?.indices
            ?.maxByOrNull { confidences[it] }
            ?: 0
        val transcript = matches.getOrNull(chosenIndex) ?: matches.first()
        onTranscript(transcript)
        transitionTo(VoiceSessionState.Thinking(transcript = transcript))

        if (continuousListening && sessionActive) {
            beginListening()
        }
    }

    fun notifyRecognitionError(message: String) {
        val isSilenceTimeout = message.contains("error 6") || message.contains("error 7")
        if (isSilenceTimeout && continuousListening && sessionActive) {
            beginListening()
            return
        }
        voiceOutput.speak(
            text = message,
            utteranceId = VoiceOutput.ERROR_UTTERANCE_ID,
        )
        transitionTo(VoiceSessionState.Errored(message))
    }

    fun endSession() {
        sessionActive = false
        scope.launch {
            geminiLiveConnector.stopSession()
        }
        speechInput.stopListening()
        voiceOutput.stop()
        transitionTo(VoiceSessionState.Ended)
    }

    fun release() {
        sessionActive = false
        speechInput.release()
        voiceOutput.release()
    }

    private fun beginListening() {
        speechInput.startListening()
        transitionTo(VoiceSessionState.Listening(source = "on_device_asr"))
    }

    private fun transitionTo(next: VoiceSessionState) {
        state = next
        onStateChanged(next)
    }
}
