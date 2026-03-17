package app.blueprint.capture.ui.screens

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.blueprint.capture.data.auth.AuthRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

enum class AuthMode {
    SignIn,
    SignUp,
}

data class AuthUiState(
    val mode: AuthMode = AuthMode.SignIn,
    val name: String = "",
    val email: String = "",
    val password: String = "",
    val confirmPassword: String = "",
    val isBusy: Boolean = false,
    val errorMessage: String? = null,
) {
    val canSubmit: Boolean =
        if (isBusy) {
            false
        } else {
            when (mode) {
                AuthMode.SignIn -> email.isNotBlank() && password.isNotBlank()
                AuthMode.SignUp -> name.isNotBlank() && email.isNotBlank() && password.length >= 8 && password == confirmPassword
            }
        }
}

@HiltViewModel
class AuthViewModel @Inject constructor(
    private val authRepository: AuthRepository,
) : ViewModel() {
    private val mutableState = MutableStateFlow(AuthUiState())
    val uiState: StateFlow<AuthUiState> = mutableState.asStateFlow()

    fun updateName(value: String) {
        mutate { copy(name = value, errorMessage = null) }
    }

    fun updateEmail(value: String) {
        mutate { copy(email = value, errorMessage = null) }
    }

    fun updatePassword(value: String) {
        mutate { copy(password = value, errorMessage = null) }
    }

    fun updateConfirmPassword(value: String) {
        mutate { copy(confirmPassword = value, errorMessage = null) }
    }

    fun toggleMode() {
        mutate {
            copy(
                mode = if (mode == AuthMode.SignIn) AuthMode.SignUp else AuthMode.SignIn,
                errorMessage = null,
            )
        }
    }

    fun submit() {
        val state = mutableState.value
        if (!state.canSubmit) {
            return
        }

        viewModelScope.launch {
            mutate { copy(isBusy = true, errorMessage = null) }
            try {
                when (state.mode) {
                    AuthMode.SignIn -> authRepository.signIn(state.email, state.password)
                    AuthMode.SignUp -> authRepository.signUp(state.name, state.email, state.password)
                }
                mutate {
                    copy(
                        isBusy = false,
                        password = "",
                        confirmPassword = "",
                        errorMessage = null,
                    )
                }
            } catch (error: Exception) {
                mutate {
                    copy(
                        isBusy = false,
                        errorMessage = error.localizedMessage ?: "Authentication failed.",
                    )
                }
            }
        }
    }

    fun submitGoogleIdToken(idToken: String) {
        viewModelScope.launch {
            mutate { copy(isBusy = true, errorMessage = null) }
            try {
                authRepository.signInWithGoogle(idToken)
                mutate { copy(isBusy = false, password = "", confirmPassword = "") }
            } catch (error: Exception) {
                mutate {
                    copy(
                        isBusy = false,
                        errorMessage = error.localizedMessage ?: "Google sign-in failed.",
                    )
                }
            }
        }
    }

    fun setGoogleError(message: String) {
        mutate { copy(isBusy = false, errorMessage = message) }
    }

    private fun mutate(transform: AuthUiState.() -> AuthUiState) {
        mutableState.value = mutableState.value.transform()
    }
}
