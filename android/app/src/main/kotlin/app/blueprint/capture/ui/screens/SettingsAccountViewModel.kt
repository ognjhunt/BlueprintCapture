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

data class SettingsAccountUiState(
    val isDeletingAccount: Boolean = false,
    val deletionErrorMessage: String? = null,
)

@HiltViewModel
class SettingsAccountViewModel @Inject constructor(
    private val authRepository: AuthRepository,
) : ViewModel() {
    private val state = MutableStateFlow(SettingsAccountUiState())

    val uiState: StateFlow<SettingsAccountUiState> = state.asStateFlow()

    fun deleteAccount(onDeleted: () -> Unit) {
        if (state.value.isDeletingAccount) {
            return
        }

        viewModelScope.launch {
            state.value = state.value.copy(isDeletingAccount = true, deletionErrorMessage = null)
            runCatching {
                authRepository.deleteCurrentAccount()
            }.onSuccess {
                state.value = SettingsAccountUiState()
                onDeleted()
            }.onFailure { error ->
                state.value = state.value.copy(
                    isDeletingAccount = false,
                    deletionErrorMessage =
                        error.localizedMessage
                            ?: "We couldn't delete this account automatically. Use the support link for manual deletion.",
                )
            }
        }
    }

    fun dismissDeletionError() {
        state.value = state.value.copy(deletionErrorMessage = null)
    }
}
