//
//  UserDeviceService.swift
//  BlueprintCapture
//
//  Creates and manages a device-local temporary user until authentication.
//

import Foundation
import UIKit
import FirebaseAuth
import FirebaseFirestore

final class UserDeviceService {
    private static let temporaryUserDefaultsKey = "temporaryUser"
    private static let temporaryUserIdKey = "temporaryUserId"

    /// Returns the currently resolved user identifier. If authenticated, returns the Firebase uid.
    /// Otherwise returns the device-local tempID (creating if necessary).
    static func resolvedUserId() -> String {
        if let uid = Auth.auth().currentUser?.uid, !uid.isEmpty {
            return uid
        }
        let user = ensureTemporaryUser()
        return user["tempID"] as? String ?? ""
    }

    static func hasRegisteredAccount() -> Bool {
        guard let user = Auth.auth().currentUser else { return false }
        return !user.isAnonymous
    }

    static func ensureAnonymousFirebaseUserIfNeeded(onReady: @escaping () -> Void = {}) {
        if let currentUser = Auth.auth().currentUser {
            if currentUser.isAnonymous {
                bootstrapAnonymousUserDocument(for: currentUser, completion: onReady)
            } else {
                onReady()
            }
            return
        }

        Auth.auth().signInAnonymously { result, error in
            if let error {
                print("⚠️ [Auth] \(describeAnonymousAuthFailure(error))")
                onReady()
                return
            }
            guard let user = result?.user else {
                onReady()
                return
            }
            bootstrapAnonymousUserDocument(for: user) {
                NotificationCenter.default.post(name: .AuthStateDidChange, object: nil)
                onReady()
            }
        }
    }

    static func waitForAuthenticatedFirebaseUser(timeout: TimeInterval = 10) async -> Bool {
        guard timeout > 0 else {
            return Auth.auth().currentUser != nil
        }
        if Auth.auth().currentUser != nil {
            return true
        }

        return await withCheckedContinuation { continuation in
            let lock = NSLock()
            var didResume = false
            var observer: NSObjectProtocol?

            let finish: (Bool) -> Void = { success in
                lock.lock()
                defer { lock.unlock() }
                guard !didResume else { return }
                didResume = true
                if let observer {
                    NotificationCenter.default.removeObserver(observer)
                }
                continuation.resume(returning: success)
            }

            observer = NotificationCenter.default.addObserver(
                forName: .AuthStateDidChange,
                object: nil,
                queue: nil
            ) { _ in
                finish(Auth.auth().currentUser != nil)
            }

            ensureAnonymousFirebaseUserIfNeeded {
                finish(Auth.auth().currentUser != nil)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                finish(Auth.auth().currentUser != nil)
            }
        }
    }

    private static func describeAnonymousAuthFailure(_ error: Error) -> String {
        let nsError = error as NSError
        if let authCode = AuthErrorCode(rawValue: nsError.code) {
            switch authCode {
            case .operationNotAllowed:
                return "Anonymous sign-in failed: operationNotAllowed. Anonymous Auth is disabled for this Firebase project or blocked by project policy."
            case .networkError:
                return "Anonymous sign-in failed: networkError. Check connectivity and Firebase project reachability."
            default:
                return "Anonymous sign-in failed: \(authCode). \(error.localizedDescription)"
            }
        }
        return "Anonymous sign-in failed: \(error.localizedDescription)"
    }

    /// Ensures a temporary local user exists in UserDefaults and returns its document.
    /// If one already exists, returns the cached copy.
    @discardableResult
    static func ensureTemporaryUser() -> [String: Any] {
        if let existing = UserDefaults.standard.dictionary(forKey: temporaryUserDefaultsKey) {
            return existing
        }

        let tempId = UUID().uuidString
        let now = Date()

        var permissions: [String: Bool] = [
            "camera": false,
            "microphone": false,
            "location": false,
            "notifications": false
        ]

        // Seed with whatever we already know (rarely available on first launch)
        permissions["notifications"] = false

        let doc: [String: Any] = [
            "tempID": tempId,
            "name": "Guest",
            "email": "",
            "username": "",
            "planType": "guest",
            "fcmToken": "",
            "createdDate": now,
            "lastSessionDate": now,
            "lastLoginDate": now,
            "finishedOnboarding": false,
            // Counters and payouts
            "numSessions": 0,
            "numLocationsScanned": 0,
            "amountEarned": 0.0,
            "amountPaidOut": 0.0,
            // Permissions snapshot (mirrors Settings)
            "permissions": permissions,
            // Helpful device context
            "deviceModel": UIDevice.current.model,
            "deviceName": UIDevice.current.name,
            "systemVersion": UIDevice.current.systemVersion
        ]

        UserDefaults.standard.set(doc, forKey: temporaryUserDefaultsKey)
        UserDefaults.standard.set(tempId, forKey: temporaryUserIdKey)

        // Pretty-print to console for debugging
        printUserDocument(doc)
        return doc
    }

    /// Prints the current local user document to the console.
    static func printLocalUser() {
        if let doc = UserDefaults.standard.dictionary(forKey: temporaryUserDefaultsKey) {
            printUserDocument(doc)
        } else {
            let created = ensureTemporaryUser()
            printUserDocument(created)
        }
    }

    private static func printUserDocument(_ doc: [String: Any]) {
        if JSONSerialization.isValidJSONObject(doc),
           let data = try? JSONSerialization.data(withJSONObject: doc, options: [.prettyPrinted]),
           let json = String(data: data, encoding: .utf8) {
            print("[TemporaryUser] Document =\n\(json)")
        } else {
            print("[TemporaryUser] Document = \(doc)")
        }
    }

    private static func bootstrapAnonymousUserDocument(for user: FirebaseAuth.User, completion: @escaping () -> Void) {
        let tempUser = ensureTemporaryUser()
        let userRef = Firestore.firestore().collection("users").document(user.uid)
        userRef.getDocument { snapshot, error in
            if let error {
                print("⚠️ [Auth] Failed to inspect anonymous user document: \(error.localizedDescription)")
                completion()
                return
            }

            var payload: [String: Any] = [
                "uid": user.uid,
                "email": "",
                "name": tempUser["name"] as? String ?? "Guest",
                "role": "guest",
                "planType": "guest",
                "updatedAt": FieldValue.serverTimestamp(),
                "isAnonymous": true,
            ]

            if snapshot?.exists != true {
                payload["createdAt"] = FieldValue.serverTimestamp()
                payload["stats"] = [
                    "totalCaptures": 0,
                    "approvedCaptures": 0,
                    "avgQuality": 0,
                    "totalEarnings": 0,
                    "availableBalance": 0,
                    "referralEarningsCents": 0,
                    "referralBonusCents": 0,
                ]
            }

            userRef.setData(payload, merge: true) { writeError in
                if let writeError {
                    print("⚠️ [Auth] Failed to bootstrap anonymous user document: \(writeError.localizedDescription)")
                }
                completion()
            }
        }
    }

    /// Mutates stored local user with provided fields.
    static func updateLocalUser(fields: [String: Any]) {
        var current = ensureTemporaryUser()
        for (k, v) in fields { current[k] = v }
        UserDefaults.standard.set(current, forKey: temporaryUserDefaultsKey)
    }

    /// Sets a permission flag (camera/microphone/location/notifications) and persists it.
    static func setPermission(_ name: String, granted: Bool) {
        var current = ensureTemporaryUser()
        var permissions = current["permissions"] as? [String: Bool] ?? [:]
        permissions[name] = granted
        current["permissions"] = permissions
        current["lastLoginDate"] = Date()
        UserDefaults.standard.set(current, forKey: temporaryUserDefaultsKey)
    }

    /// Increments a numeric counter field on the local user (e.g. numLocationsScanned, numSessions).
    static func incrementCounter(_ field: String, by amount: Int = 1) {
        var current = ensureTemporaryUser()
        let oldValue = (current[field] as? Int) ?? 0
        current[field] = oldValue + amount
        UserDefaults.standard.set(current, forKey: temporaryUserDefaultsKey)
    }

    /// Adds a payout amount to amountPaidOut and amountEarned.
    static func addPayout(_ amount: Double) {
        var current = ensureTemporaryUser()
        let oldPaid = (current["amountPaidOut"] as? Double) ?? 0
        let oldEarned = (current["amountEarned"] as? Double) ?? 0
        current["amountPaidOut"] = oldPaid + amount
        current["amountEarned"] = oldEarned + amount
        UserDefaults.standard.set(current, forKey: temporaryUserDefaultsKey)
    }
}
