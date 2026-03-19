package app.blueprint.capture.data.auth

import android.content.ClipboardManager
import android.content.Context
import android.util.Log
import app.blueprint.capture.data.util.awaitResult
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.FirebaseUser
import com.google.firebase.auth.GoogleAuthProvider
import com.google.firebase.auth.UserProfileChangeRequest
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.SetOptions
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

@Singleton
class AuthRepository @Inject constructor(
    @ApplicationContext private val context: Context,
    private val auth: FirebaseAuth,
    private val firestore: FirebaseFirestore,
) {
    private val repositoryScope = CoroutineScope(Dispatchers.IO)

    val authState: Flow<FirebaseUser?> = callbackFlow {
        val listener = FirebaseAuth.AuthStateListener { firebaseAuth ->
            trySend(firebaseAuth.currentUser)
        }
        auth.addAuthStateListener(listener)
        trySend(auth.currentUser)
        awaitClose { auth.removeAuthStateListener(listener) }
    }.distinctUntilChanged()

    val registeredAuthState: Flow<FirebaseUser?> = authState
        .map { user -> user?.takeUnless { it.isAnonymous } }
        .distinctUntilChanged()

    suspend fun ensureAnonymousSession() {
        val currentUser = auth.currentUser
        if (currentUser == null) {
            val result = try {
                auth.signInAnonymously().awaitResult()
            } catch (error: Exception) {
                Log.w(
                    "AuthRepository",
                    "Anonymous sign-in failed: ${FirebaseAuthErrorFormatter.describeAnonymousSignInFailure(error)}",
                    error,
                )
                throw error
            }
            result.user?.let { user ->
                bootstrapUserDocument(user, "Guest")
            }
            return
        }
        if (currentUser.isAnonymous) {
            bootstrapUserDocument(currentUser, "Guest")
        }
    }

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
            // Guarantee a referral code exists for the new user (iOS ReferralService parity)
            ensureReferralCode(user.uid)
            // Attribute any clipboard referral code at sign-up time
            consumeClipboardReferralIfNeeded(user.uid, name.trim())
        }
    }

    suspend fun signInWithGoogle(idToken: String) {
        val credential = GoogleAuthProvider.getCredential(idToken, null)
        val result = auth.signInWithCredential(credential).awaitResult()
        result.user?.let { user ->
            bootstrapUserDocument(it = user, nameOverride = user.displayName)
            // Guarantee referral code on every Google sign-in (covers new + returning users)
            ensureReferralCode(user.uid)
        }
    }

    fun signOut() {
        auth.signOut()
        repositoryScope.launch {
            runCatching { ensureAnonymousSession() }
        }
    }

    fun currentUserId(): String? = auth.currentUser?.uid

    // ---------------------------------------------------------------------------
    // Referral code guarantee (mirrors iOS ReferralService.ensureReferralCode)
    // ---------------------------------------------------------------------------

    /**
     * Generates and stores a 6-character referral code if the user doesn't already have one.
     * Also writes to `referralCodes/{code}` for O(1) lookup validation.
     */
    suspend fun ensureReferralCode(userId: String): String? = runCatching {
        val userRef = firestore.collection("users").document(userId)
        val snapshot = userRef.get().awaitResult()

        val existing = snapshot.data?.get("referralCode") as? String
        if (!existing.isNullOrBlank()) {
            // Backfill lookup entry if missing (handles pre-migration users)
            val lookupRef = firestore.collection("referralCodes").document(existing)
            val lookupSnap = lookupRef.get().awaitResult()
            if (!lookupSnap.exists()) {
                lookupRef.set(mapOf("ownerId" to userId)).awaitResult()
            }
            return@runCatching existing
        }

        val code = generateReferralCode()
        val batch = firestore.batch()
        batch.set(
            userRef,
            mapOf(
                "referralCode" to code,
                "updatedAt" to FieldValue.serverTimestamp(),
            ),
            SetOptions.merge(),
        )
        batch.set(
            firestore.collection("referralCodes").document(code),
            mapOf("ownerId" to userId),
        )
        batch.commit().awaitResult()
        code
    }.getOrNull()

    /**
     * Checks the system clipboard at sign-up for a referral URL or bare 6-char code.
     * If found and valid, attributes the new user to the referrer's account.
     * Mirrors iOS consumePasteboardReferralIfNeeded().
     */
    suspend fun consumeClipboardReferralIfNeeded(newUserId: String, newUserName: String) {
        runCatching {
            val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
            val rawText = clipboard?.primaryClip?.getItemAt(0)?.text?.toString()?.trim()
                ?: return@runCatching
            val code = extractReferralCode(rawText) ?: return@runCatching

            // Don't attribute if already attributed
            val newUserSnap = firestore.collection("users").document(newUserId).get().awaitResult()
            val alreadyAttributed = (newUserSnap.data?.get("referredBy") as? String)?.isNotBlank() == true
            if (alreadyAttributed) return@runCatching

            // Resolve referrer
            val lookupSnap = firestore.collection("referralCodes").document(code).get().awaitResult()
            val referrerId = lookupSnap.data?.get("ownerId") as? String ?: return@runCatching
            if (referrerId == newUserId) return@runCatching // self-referral guard

            val batch = firestore.batch()
            batch.set(
                firestore.collection("users").document(newUserId),
                mapOf(
                    "referredBy" to referrerId,
                    "updatedAt" to FieldValue.serverTimestamp(),
                ),
                SetOptions.merge(),
            )
            batch.set(
                firestore.collection("users").document(referrerId)
                    .collection("referrals").document(newUserId),
                mapOf(
                    "referredUserId" to newUserId,
                    "referredUserName" to newUserName,
                    "referredAt" to FieldValue.serverTimestamp(),
                    "status" to "signed_up",
                    "lifetimeEarningsCents" to 0,
                ),
                SetOptions.merge(),
            )
            batch.commit().awaitResult()
        }
    }

    // ---------------------------------------------------------------------------
    // Internal helpers
    // ---------------------------------------------------------------------------

    private suspend fun bootstrapUserDocument(it: FirebaseUser, nameOverride: String?) {
        val userRef = firestore.collection("users").document(it.uid)
        val existingSnapshot = userRef.get().awaitResult()

        val payload = mutableMapOf<String, Any>(
            "uid" to it.uid,
            "email" to (it.email ?: ""),
            "name" to (nameOverride ?: it.displayName ?: ""),
            "phone_number" to (it.phoneNumber ?: ""),
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

    private fun generateReferralCode(): String {
        val chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // Exclude ambiguous chars (matches iOS)
        return (1..6).map { chars.random() }.joinToString("")
    }

    private fun extractReferralCode(raw: String): String? {
        // Try URL form: https://blueprintcapture.app/join?ref=XXXXXX
        val urlMatch = "ref=([A-Z0-9]{6})".toRegex(RegexOption.IGNORE_CASE).find(raw)
        if (urlMatch != null) return normalizeCode(urlMatch.groupValues[1])
        // Try bare 6-char code
        return normalizeCode(raw.trim())
    }

    private fun normalizeCode(raw: String): String? {
        val code = raw.trim().uppercase()
        val allowed = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return if (code.length == 6 && code.all { it in allowed }) code else null
    }
}
