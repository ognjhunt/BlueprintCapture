import Foundation
import UIKit
import FirebaseAuth
import FirebaseCore

#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

enum GoogleAuthError: LocalizedError {
    case sdkUnavailable
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .sdkUnavailable: return "Google Sign-In is not available in this build."
        case .failed(let msg): return msg
        }
    }
}

final class GoogleAuthService {
    static let shared = GoogleAuthService()
    private init() {}

    func signIn(presenting viewController: UIViewController) async throws {
        #if canImport(GoogleSignIn)
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw GoogleAuthError.failed("Missing Google client ID")
        }

        // Configure Google Sign-In once using Firebase client ID
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config

        // Perform Google Sign-In with the new v9 API
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: viewController)
        let user = result.user

        guard let idToken = user.idToken?.tokenString else {
            throw GoogleAuthError.failed("Missing Google ID token")
        }
        let accessToken = user.accessToken.tokenString

        let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)

        // Bridge Firebase Auth sign-in to async/await
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Auth.auth().signIn(with: credential) { _, err in
                if let err = err { continuation.resume(throwing: err) } else { continuation.resume(returning: ()) }
            }
        }
        #else
        throw GoogleAuthError.sdkUnavailable
        #endif
    }
}

extension UIApplication {
    var topViewController: UIViewController? {
        guard let keyWindow = connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) else { return nil }

        var top = keyWindow.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}


