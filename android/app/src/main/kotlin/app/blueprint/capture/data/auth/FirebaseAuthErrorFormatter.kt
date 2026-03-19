package app.blueprint.capture.data.auth

import com.google.firebase.FirebaseNetworkException
import com.google.firebase.auth.FirebaseAuthException

object FirebaseAuthErrorFormatter {
    fun describeAnonymousSignInFailure(error: Throwable): String {
        val authError = error as? FirebaseAuthException
        return describeAnonymousSignInFailure(
            errorCode = authError?.errorCode,
            isNetworkError = error is FirebaseNetworkException,
            fallbackMessage = error.localizedMessage,
        )
    }

    fun describeAnonymousSignInFailure(
        errorCode: String?,
        isNetworkError: Boolean = false,
        fallbackMessage: String? = null,
    ): String {
        return when (errorCode) {
            "ERROR_OPERATION_NOT_ALLOWED" ->
                "Firebase Anonymous Auth is disabled for this project."
            "ERROR_TOO_MANY_REQUESTS" ->
                "Firebase blocked anonymous sign-in because the client has sent too many requests."
            "ERROR_APP_NOT_AUTHORIZED" ->
                "This app is not authorized to use the configured Firebase project."
            "ERROR_INVALID_API_KEY" ->
                "The Firebase API key in this build is invalid."
            else -> if (isNetworkError) {
                "Firebase anonymous sign-in failed because the device could not reach Firebase."
            } else {
                fallbackMessage ?: "Firebase anonymous sign-in failed."
            }
        }
    }
}
