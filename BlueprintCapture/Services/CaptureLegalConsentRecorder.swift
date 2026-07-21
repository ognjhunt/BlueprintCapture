import Foundation
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore

// MARK: - CaptureLegalConsentRecorder
//
// Persists the capturer's legal-consent acceptance (terms / privacy / capture
// policy) so the acceptance is on record with a version, not just gated in UI.
// Written to the signed-in user's own `users/{uid}` document (field-allowlisted
// by firestore.rules — never touches `stats`). Best-effort: a network failure
// never blocks auth, and the local mirror keeps the last acceptance for
// re-consent checks when the policy version changes.

enum CaptureLegalConsentRecorder {
    private static let localAcceptedVersionKey = "com.blueprint.legalConsent.acceptedVersion"
    private static let localAcceptedAtKey = "com.blueprint.legalConsent.acceptedAt"

    /// Records acceptance of the current consent policy for the signed-in,
    /// non-anonymous user. Call after an auth flow that required the
    /// acknowledgement checkbox.
    static func recordAcceptance(defaults: UserDefaults = .standard) {
        defaults.set(CaptureLegalConsentPolicy.consentVersion, forKey: localAcceptedVersionKey)
        defaults.set(Date().timeIntervalSince1970, forKey: localAcceptedAtKey)

        guard FirebaseApp.app() != nil,
              let user = Auth.auth().currentUser,
              !user.isAnonymous else { return }

        let policy = CaptureLegalConsentPolicy.current()
        let consent: [String: Any] = [
            "acceptedAt": FieldValue.serverTimestamp(),
            "version": CaptureLegalConsentPolicy.consentVersion,
            "acknowledgementText": CaptureLegalConsentPolicy.acknowledgementText,
            "termsOfServiceURL": policy.termsOfServiceURL?.absoluteString ?? "",
            "privacyPolicyURL": policy.privacyPolicyURL?.absoluteString ?? "",
            "capturePolicyURL": policy.capturePolicyURL?.absoluteString ?? "",
        ]

        Firestore.firestore()
            .collection("users")
            .document(user.uid)
            .setData(["legalConsent": consent], merge: true) { error in
                if let error {
                    print("WARN - CaptureLegalConsentRecorder: \(error.localizedDescription)")
                }
            }
    }

    /// Locally recorded accepted version, if any. A mismatch against
    /// `CaptureLegalConsentPolicy.consentVersion` means re-consent is due.
    static func locallyAcceptedVersion(defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: localAcceptedVersionKey)
    }
}
