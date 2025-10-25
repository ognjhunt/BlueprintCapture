import Foundation
import SwiftUI
import Combine
import UIKit
import FirebaseAuth

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
            try await GoogleAuthService.shared.signIn(presenting: presenter)
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
    }

    private func signUp(name: String, email: String, password: String) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            Auth.auth().createUser(withEmail: email, password: password) { result, err in
                if let err = err { return cont.resume(throwing: err) }
                // Optionally set display name
                if let changeReq = result?.user.createProfileChangeRequest() {
                    changeReq.displayName = name
                    changeReq.commitChanges { _ in cont.resume(returning: ()) }
                } else {
                    cont.resume(returning: ())
                }
            }
        }
    }
}


