import Foundation
import SwiftUI
import Combine
import UIKit
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class AuthViewModel: ObservableObject {
    enum Mode { case signIn, signUp }
    @Published var mode: Mode

    init(mode: Mode = .signIn) {
        self.mode = mode
    }
    @Published var name: String = ""
    @Published var email: String = ""
    @Published var password: String = ""
    @Published var confirmPassword: String = ""
    @Published var isBusy: Bool = false
    @Published var errorMessage: String?
    /// Non-error status line (e.g. "reset email sent").
    @Published var infoMessage: String?

    /// Referral code entered by the user or captured from a deep link.
    @AppStorage(PendingReferralStore.storageKey) var pendingReferralCode: String = ""

    var canSubmit: Bool {
        if isBusy { return false }
        switch mode {
        case .signIn:
            return !email.isEmpty && !password.isEmpty
        case .signUp:
            return !name.isEmpty && !email.isEmpty && password.count >= 8 && password == confirmPassword
        }
    }

    func toggleMode() { mode = (mode == .signIn ? .signUp : .signIn); errorMessage = nil; infoMessage = nil }

    /// Sends a Firebase password-reset email for the address in the email field.
    /// The audit flagged the absence of any recovery path as a literal dead end.
    func sendPasswordReset() async {
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else {
            errorMessage = "Enter your email above first, then tap “Forgot password?”."
            return
        }
        errorMessage = nil
        infoMessage = nil
        isBusy = true
        defer { isBusy = false }
        do {
            try await Auth.auth().sendPasswordReset(withEmail: address)
            infoMessage = "Password reset email sent to \(address). Check your inbox, then sign in with your new password."
        } catch {
            errorMessage = Self.friendlyAuthMessage(for: error)
        }
    }

    /// Maps Firebase Auth failures to actionable copy — raw SDK strings must
    /// not reach capturers (audit UX finding).
    static func friendlyAuthMessage(for error: Error) -> String {
        let ns = error as NSError
        guard let code = AuthErrorCode(rawValue: ns.code) else {
            return ns.localizedDescription
        }
        switch code {
        case .wrongPassword, .invalidCredential:
            return "That email and password don't match. Try again, or tap “Forgot password?” to reset it."
        case .userNotFound:
            return "No account found with that email. Check the address, or create an account."
        case .invalidEmail:
            return "That doesn't look like a valid email address."
        case .emailAlreadyInUse, .credentialAlreadyInUse:
            return "An account already exists with that email. Try signing in instead."
        case .weakPassword:
            return "Choose a stronger password — at least 8 characters."
        case .networkError:
            return "Couldn't reach the server. Check your connection and try again."
        case .tooManyRequests:
            return "Too many attempts. Wait a few minutes, then try again."
        case .userDisabled:
            return "This account has been disabled. Contact support for help."
        default:
            return ns.localizedDescription
        }
    }

    func submit() async {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }

        do {
            switch mode {
            case .signIn:
                try await signIn(email: email, password: password)
                ActivationFunnelStore.shared.record(
                    .accountCreatedOrSignedIn,
                    metadata: ["auth_mode": "sign_in", "auth_provider": "email"]
                )
                NotificationCenter.default.post(name: .AuthStateDidChange, object: nil)
            case .signUp:
                try await signUp(name: name, email: email, password: password)
                ActivationFunnelStore.shared.record(
                    .accountCreatedOrSignedIn,
                    metadata: ["auth_mode": "sign_up", "auth_provider": "email"]
                )
                NotificationCenter.default.post(name: .AuthStateDidChange, object: nil)
            }
        } catch {
            errorMessage = Self.friendlyAuthMessage(for: error)
        }
    }

    func signInWithGoogle() async {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }
        do {
            guard let presenter = UIApplication.shared.topViewController else { throw NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to present Google Sign-In"]) }
            let result = try await GoogleAuthService.shared.signIn(presenting: presenter)
            if let user = result.user as FirebaseAuth.User? {
                try await bootstrapUserDocument(for: user, nameOverride: user.displayName)
                if result.additionalUserInfo?.isNewUser == true {
                    await handleReferralAttribution(newUserId: user.uid, newUserName: user.displayName ?? user.email ?? "Capturer")
                }
            }
            ActivationFunnelStore.shared.record(
                .accountCreatedOrSignedIn,
                metadata: [
                    "auth_mode": result.additionalUserInfo?.isNewUser == true ? "sign_up" : "sign_in",
                    "auth_provider": "google"
                ]
            )
            NotificationCenter.default.post(name: .AuthStateDidChange, object: nil)
        } catch {
            errorMessage = Self.friendlyAuthMessage(for: error)
        }
    }

    private func signIn(email: String, password: String) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            Auth.auth().signIn(withEmail: email, password: password) { _, err in
                if let err = err { cont.resume(throwing: err) } else { cont.resume(returning: ()) }
            }
        }
        if let user = Auth.auth().currentUser {
            try await bootstrapUserDocument(for: user, nameOverride: user.displayName)
        }
    }

    private func signUp(name: String, email: String, password: String) async throws {
        // CAP-07: if the capturer is currently an anonymous guest, UPGRADE that user
        // in place by linking the email credential instead of minting a new uid. Guest
        // captures and earnings are keyed to request.auth.uid at capture time, so a
        // fresh uid would orphan them. Falls back to createUser when there is no
        // anonymous session to upgrade.
        let result: AuthDataResult?
        if let current = Auth.auth().currentUser, current.isAnonymous {
            let credential = EmailAuthProvider.credential(withEmail: email, password: password)
            result = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<AuthDataResult?, Error>) in
                current.link(with: credential) { linkResult, err in
                    if let err = err { return cont.resume(throwing: err) }
                    cont.resume(returning: linkResult)
                }
            }
        } else {
            result = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<AuthDataResult?, Error>) in
                Auth.auth().createUser(withEmail: email, password: password) { result, err in
                    if let err = err { return cont.resume(throwing: err) }
                    cont.resume(returning: result)
                }
            }
        }

        // Set display name
        if let changeReq = result?.user.createProfileChangeRequest() {
            changeReq.displayName = name
            try? await changeReq.commitChanges()
        }

        if let user = result?.user {
            try await bootstrapUserDocument(for: user, nameOverride: name)
        }

        // Handle referral attribution
        await handleReferralAttribution(newUserId: result?.user.uid, newUserName: name)
    }

    private func handleReferralAttribution(newUserId: String?, newUserName: String) async {
        let code = pendingReferralCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, let newUserId else { return }

        do {
            let result = try await ReferralService.shared.attributeReferral(
                code: code,
                newUserId: newUserId,
                newUserName: newUserName
            )
            switch result {
            case .attributed, .invalidCode, .alreadyAttributed, .selfReferral:
                pendingReferralCode = ""
            }
        } catch {
            // Referral attribution is best-effort — don't block sign-up
            print("⚠️ [Referral] Attribution failed: \(error.localizedDescription)")
        }
    }

    func consumePasteboardReferralIfNeeded() {
        guard pendingReferralCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let code = ReferralService.referralCode(from: UIPasteboard.general.string) else { return }
        pendingReferralCode = code
    }

    private func bootstrapUserDocument(for user: FirebaseAuth.User, nameOverride: String?) async throws {
        let userRef = Firestore.firestore().collection("users").document(user.uid)
        let snapshot = try await userRef.getDocument()

        var payload: [String: Any] = [
            "uid": user.uid,
            "email": user.email ?? "",
            "name": nameOverride ?? user.displayName ?? "",
            "role": "capturer",
            "updatedAt": FieldValue.serverTimestamp()
        ]

        if !snapshot.exists {
            payload["createdAt"] = FieldValue.serverTimestamp()
            payload["stats"] = [
                "totalCaptures": 0,
                "approvedCaptures": 0,
                "avgQuality": 0,
                "totalEarnings": 0,
                "availableBalance": 0,
                "referralEarningsCents": 0,
                "referralBonusCents": 0
            ]
        }

        try await userRef.setData(payload, merge: true)

        // Guarantee every user has a referral code immediately after sign-up so they
        // can share it right away without needing to open the referral dashboard first.
        try? await ReferralService.shared.ensureReferralCode(userId: user.uid)
    }
}
