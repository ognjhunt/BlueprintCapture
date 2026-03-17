package app.blueprint.capture.data.auth

import app.blueprint.capture.data.util.awaitResult
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.FirebaseUser
import com.google.firebase.auth.GoogleAuthProvider
import com.google.firebase.auth.UserProfileChangeRequest
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.SetOptions
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.distinctUntilChanged

@Singleton
class AuthRepository @Inject constructor(
    private val auth: FirebaseAuth,
    private val firestore: FirebaseFirestore,
) {
    val authState: Flow<FirebaseUser?> = callbackFlow {
        val listener = FirebaseAuth.AuthStateListener { firebaseAuth ->
            trySend(firebaseAuth.currentUser)
        }
        auth.addAuthStateListener(listener)
        trySend(auth.currentUser)
        awaitClose { auth.removeAuthStateListener(listener) }
    }.distinctUntilChanged()

    suspend fun signIn(email: String, password: String) {
        auth.signInWithEmailAndPassword(email.trim(), password).awaitResult()
        auth.currentUser?.let { bootstrapUserDocument(it, it.displayName) }
    }

    suspend fun signUp(name: String, email: String, password: String) {
        val result = auth.createUserWithEmailAndPassword(email.trim(), password).awaitResult()
        result.user?.let { user ->
            val profileUpdate = UserProfileChangeRequest.Builder()
                .setDisplayName(name.trim())
                .build()
            user.updateProfile(profileUpdate).awaitResult()
            bootstrapUserDocument(user, name.trim())
        }
    }

    suspend fun signInWithGoogle(idToken: String) {
        val credential = GoogleAuthProvider.getCredential(idToken, null)
        val result = auth.signInWithCredential(credential).awaitResult()
        result.user?.let { bootstrapUserDocument(it, it.displayName) }
    }

    fun signOut() {
        auth.signOut()
    }

    private suspend fun bootstrapUserDocument(
        user: FirebaseUser,
        nameOverride: String?,
    ) {
        val userRef = firestore.collection("users").document(user.uid)
        val existingSnapshot = userRef.get().awaitResult()

        val payload = mutableMapOf<String, Any>(
            "uid" to user.uid,
            "email" to (user.email ?: ""),
            "name" to (nameOverride ?: user.displayName ?: ""),
            "phone_number" to (user.phoneNumber ?: ""),
            "company" to "",
            "role" to "capturer",
            "updatedAt" to FieldValue.serverTimestamp(),
        )

        if (!existingSnapshot.exists()) {
            payload["createdAt"] = FieldValue.serverTimestamp()
            payload["stats"] = mapOf(
                "totalCaptures" to 0,
                "approvedCaptures" to 0,
                "avgQuality" to 0,
                "totalEarnings" to 0,
                "availableBalance" to 0,
                "referralEarningsCents" to 0,
                "referralBonusCents" to 0,
            )
        }

        userRef.set(payload, SetOptions.merge()).awaitResult()
    }
}
