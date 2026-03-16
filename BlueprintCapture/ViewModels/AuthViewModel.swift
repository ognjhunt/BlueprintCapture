import Foundation
import SwiftUI
import Combine
import UIKit
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class AuthViewModel: ObservableObject {
    enum Mode { case signIn, signUp }
    @Published var mode: Mode = .signIn
    @Published var name: String = ""
    @Published var email: String = ""
    @Published var password: String = ""
    @Published var confirmPassword: String = ""
    @Published var isBusy: Bool = false
    @Published var errorMessage: String?

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

    func toggleMode() { mode = (mode == .signIn ? .signUp : .signIn); errorMessage = nil }

    func submit() async {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }

        do {
            switch mode {
            case .signIn:
                try await signIn(email: email, password: password)
                NotificationCenter.default.post(name: .AuthStateDidChange, object: nil)
            case .signUp:
                try await signUp(name: name, email: email, password: password)
                NotificationCenter.default.post(name: .AuthStateDidChange, object: nil)
            }
        } catch {
            errorMessage = (error as NSError).localizedDescription
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
            NotificationCenter.default.post(name: .AuthStateDidChange, object: nil)
        } catch {
            errorMessage = (error as NSError).localizedDescription
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
        let result = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<AuthDataResult?, Error>) in
            Auth.auth().createUser(withEmail: email, password: password) { result, err in
                if let err = err { return cont.resume(throwing: err) }
                cont.resume(returning: result)
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

