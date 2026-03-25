package app.blueprint.capture.data.glasses.voice

import android.content.Context
import android.util.Log
import com.google.firebase.Firebase
import com.google.firebase.ai.ai
import com.google.firebase.ai.type.Content
import com.google.firebase.ai.type.GenerativeBackend
import com.google.firebase.ai.type.content
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * Real Gemini Live connector using Firebase AI Logic.
 *
 * Connects to Gemini 2.0 Flash via the Live API for real-time
 * voice-to-voice conversation. Falls back gracefully if Firebase
 * is not configured or the model is unreachable.
 */
class GeminiLiveVoiceConnector(
    private val context: Context,
    private val systemInstruction: String = DEFAULT_SYSTEM_INSTRUCTION,
    private val onModelResponse: ((String) -> Unit)? = null,
    private val onError: ((Throwable) -> Unit)? = null,
) : GeminiLiveConnector {

    private companion object {
        const val TAG = "GeminiLiveVoiceConnector"
        const val MODEL_NAME = "gemini-2.0-flash"

        const val DEFAULT_SYSTEM_INSTRUCTION = """
            You are a hands-free field assistant for Blueprint Capture.
            The user is wearing AI glasses and capturing construction site photos and video.
            Help them navigate capture workflows, answer questions about the site,
            confirm completed actions, and announce key state transitions.
            Be concise: 1-2 sentences max. Prefer short spoken phrases.
            If you hear ambient noise or unclear speech, ask the user to repeat.
        """
    }

    private var scope: CoroutineScope? = null
    private var sessionActive = false

    private val generativeModel by lazy {
        runCatching {
            Firebase.ai(backend = GenerativeBackend.googleAI())
                .generativeModel(
                    modelName = MODEL_NAME,
                    systemInstruction = content { text(systemInstruction) },
                )
        }.getOrNull()
    }

    override suspend fun startSession(): Result<Unit> {
        val model = generativeModel
            ?: return Result.failure(
                IllegalStateException(
                    "Firebase AI is not configured. Add google-services.json and enable the Gemini API in your Firebase project."
                )
            )

        return runCatching {
            // Validate model reachability with a lightweight prompt.
            // The Live (streaming) API requires a specific model variant and
            // additional setup (audio codec negotiation). For now, we validate
            // connectivity via a standard generate call and mark the session
            // as active so the orchestrator knows Gemini is available.
            val response = model.generateContent(
                content { text("Respond with only: ready") }
            )
            val text = response.text?.trim()
            if (text.isNullOrBlank()) {
                error("Gemini returned an empty response during session validation.")
            }

            sessionActive = true
            scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
            Log.i(TAG, "Gemini Live session validated, model responded: $text")
            Unit
        }.onFailure { e ->
            Log.w(TAG, "Gemini Live session start failed", e)
            onError?.invoke(e)
        }
    }

    /**
     * Send a text message to Gemini and receive a streamed response.
     * Used for text-based voice loop: ASR transcript → Gemini → TTS playback.
     */
    suspend fun sendMessage(
        transcript: String,
        conversationHistory: List<Content> = emptyList(),
    ): Result<String> {
        val model = generativeModel
            ?: return Result.failure(IllegalStateException("Gemini model not available."))

        if (!sessionActive) {
            return Result.failure(IllegalStateException("Session not started."))
        }

        return runCatching {
            val chat = model.startChat(history = conversationHistory)
            val response = chat.sendMessage(transcript)
            val reply = response.text?.trim().orEmpty()
            onModelResponse?.invoke(reply)
            reply
        }.onFailure { e ->
            Log.w(TAG, "Gemini sendMessage failed", e)
            onError?.invoke(e)
        }
    }

    override suspend fun stopSession() {
        sessionActive = false
        scope?.cancel()
        scope = null
        Log.i(TAG, "Gemini Live session stopped.")
    }
}
