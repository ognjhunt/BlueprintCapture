package app.blueprint.capture.data.glasses.voice

import com.google.common.truth.Truth.assertThat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class VoiceSessionOrchestratorTest {
    @Test
    fun `falls back to on-device voice when gemini live is unavailable`() = runBlocking {
        val states = mutableListOf<VoiceSessionState>()
        val spoken = mutableListOf<String>()
        val transcripts = mutableListOf<String>()
        val scope = CoroutineScope(Dispatchers.Unconfined)
        val orchestrator = VoiceSessionOrchestrator(
            scope = scope,
            geminiLiveConnector = UnavailableGeminiLiveConnector("no live"),
            speechInput = FakeSpeechInput(),
            voiceOutput = FakeVoiceOutput(spoken),
            onStateChanged = states::add,
            onTranscript = transcripts::add,
        )

        orchestrator.startSession("Welcome to Blueprint XR", preferGeminiLive = true)

        assertThat(states.first()).isEqualTo(VoiceSessionState.Starting(prefersGeminiLive = true))
        assertThat(states.last()).isEqualTo(VoiceSessionState.Speaking("Welcome to Blueprint XR", fallback = true))
        assertThat(spoken).containsExactly("Welcome to Blueprint XR")
        scope.cancel()
    }

    @Test
    fun `selects most confident transcript`() {
        val transcripts = mutableListOf<String>()
        val scope = CoroutineScope(Dispatchers.Unconfined)
        val orchestrator = VoiceSessionOrchestrator(
            scope = scope,
            geminiLiveConnector = object : GeminiLiveConnector {
                override suspend fun startSession(): Result<Unit> = Result.success(Unit)
                override suspend fun stopSession() = Unit
            },
            speechInput = FakeSpeechInput(),
            voiceOutput = FakeVoiceOutput(mutableListOf()),
            onStateChanged = {},
            onTranscript = transcripts::add,
        )

        orchestrator.notifySpeechResults(
            matches = listOf("open scan", "stop capture"),
            confidences = floatArrayOf(0.2f, 0.9f),
        )

        assertThat(transcripts).containsExactly("stop capture")
        scope.cancel()
    }
}

private class FakeSpeechInput : OnDeviceSpeechInput {
    override fun startListening() = Unit
    override fun stopListening() = Unit
    override fun release() = Unit
}

private class FakeVoiceOutput(
    private val spoken: MutableList<String>,
) : VoiceOutput {
    override fun speak(text: String, utteranceId: String) {
        spoken += text
    }

    override fun stop() = Unit
    override fun release() = Unit
}
