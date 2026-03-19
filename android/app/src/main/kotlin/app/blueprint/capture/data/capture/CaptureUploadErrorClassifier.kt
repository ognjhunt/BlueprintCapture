package app.blueprint.capture.data.capture

internal object CaptureUploadErrorClassifier {
    fun isAlreadyFinalized(error: Throwable): Boolean =
        errorMessages(error).any { message ->
            val normalized = message.lowercase()
            normalized.contains("already been finalized") || normalized.contains("already finalized")
        }

    private fun errorMessages(error: Throwable?): Sequence<String> = sequence {
        var current = error
        while (current != null) {
            current.message?.let(::yield)
            current.localizedMessage
                ?.takeUnless { it == current.message }
                ?.let(::yield)
            current = current.cause
        }
    }
}
