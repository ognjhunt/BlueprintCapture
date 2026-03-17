package app.blueprint.capture.ui.screens

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.blueprint.capture.data.auth.AuthRepository
import app.blueprint.capture.data.model.ContributorProfile
import app.blueprint.capture.data.profile.ContributorProfileRepository
import com.google.firebase.auth.FirebaseUser
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

data class ProfileUiState(
    val firebaseUser: FirebaseUser? = null,
    val profile: ContributorProfile? = null,
    val nameDraft: String = "",
    val phoneDraft: String = "",
    val companyDraft: String = "",
    val isSaving: Boolean = false,
    val errorMessage: String? = null,
) {
    val isSignedIn: Boolean = firebaseUser != null
}

@HiltViewModel
@OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
class ProfileViewModel @Inject constructor(
    private val authRepository: AuthRepository,
    private val contributorProfileRepository: ContributorProfileRepository,
) : ViewModel() {
    private val draftState = MutableStateFlow(ProfileUiState())

    val uiState: StateFlow<ProfileUiState> = combine(
        authRepository.authState,
        authRepository.authState.flatMapLatest { user ->
            contributorProfileRepository.observeProfile(user?.uid)
        },
        draftState,
    ) { firebaseUser, profile, draft ->
        val seededDraft = if (profile != null && draft.nameDraft.isBlank() && draft.phoneDraft.isBlank() && draft.companyDraft.isBlank()) {
            draft.copy(
                nameDraft = profile.name,
                phoneDraft = profile.phoneNumber,
                companyDraft = profile.company,
            )
        } else {
            draft
        }

        seededDraft.copy(
            firebaseUser = firebaseUser,
            profile = profile,
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = ProfileUiState(),
    )

    fun updateName(value: String) {
        mutate { copy(nameDraft = value, errorMessage = null) }
    }

    fun updatePhone(value: String) {
        mutate { copy(phoneDraft = value, errorMessage = null) }
    }

    fun updateCompany(value: String) {
        mutate { copy(companyDraft = value, errorMessage = null) }
    }

    fun saveProfile() {
        val state = uiState.value
        val uid = state.firebaseUser?.uid ?: return

        viewModelScope.launch {
            mutate { copy(isSaving = true, errorMessage = null) }
            try {
                contributorProfileRepository.updateProfile(
                    uid = uid,
                    name = uiState.value.nameDraft,
                    phoneNumber = uiState.value.phoneDraft,
                    company = uiState.value.companyDraft,
                )
                mutate { copy(isSaving = false) }
            } catch (error: Exception) {
                mutate {
                    copy(
                        isSaving = false,
                        errorMessage = error.localizedMessage ?: "Unable to save profile.",
                    )
                }
            }
        }
    }

    fun signOut() {
        authRepository.signOut()
        draftState.value = ProfileUiState()
    }

    private fun mutate(transform: ProfileUiState.() -> ProfileUiState) {
        draftState.value = draftState.value.transform()
    }
}
