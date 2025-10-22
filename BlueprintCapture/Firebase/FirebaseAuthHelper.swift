//
//  FirebaseAuthHelper.swift
//  DecorateYourRoom
//
//  Created by Nijel Hunt on 1/10/22.
//  Copyright © 2022 Placenote. All rights reserved.
//

import Foundation
import Firebase
import FirebaseAuth

/// A helper class to manage Firebase authentication related tasks.
public class FirebaseAuthHelper {
    
    static private let auth = Auth.auth()
    
    //MARK: --- Get current auth user ---
    /// Retrieves the unique identifier for the currently logged-in user.
    /// - Returns: An optional string containing the UID of the current user, if signed in.
    public static func getCurrentUserUid() -> String? {
        return auth.currentUser?.uid
    }
    
    /// Retrieves the unique identifier for the current user or prints an error message and returns an empty string if no user is found.
    /// - Returns: A string containing the UID of the current user, or an empty string if no user is found.
    public static func getCurrentUserUid2() -> String {
        
        if let uid = auth.currentUser?.uid {
            return uid
        } else {
//            fatalError("Could not get uid of current User")
            print("Could not get uid of current User - FATAL ERROR")
            return ""
           // return
        }
    }
    
    /// Fetches the full `User` object of the currently authenticated user.
    /// - Parameter completion: A closure that gets called with the `User` object once retrieved.
    public static func getCurrentUser(completion: @escaping (User) -> Void) {
        
        let currentUser = getCurrentUserUid2()
        FirestoreManager.getUser(currentUser) { (user) in
            guard let user = user else {
                fatalError("Could not get current user")
            }
            completion(user)
        }
    }
    
    /// Attempts to log in a user with an email and password.
    /// - Parameters:
    ///   - email: The user's email address as an optional string.
    ///   - password: The user's password as an optional string.
    ///   - completion: A closure that gets called with an optional error message if login fails.
    public static func loginUser(email: String?, password: String?, completion: @escaping (String?) -> Void ) {
        
        // Validate email / pwd
        guard let email = email, let password = password else {
            return completion("Fields cannot be empty")
        }
        
        // sign in user via firebase auth
        auth.signIn(withEmail: email, password: password) { (authResult, err) in
            guard let authResult = authResult, err == nil else {
                return completion(err!.localizedDescription)
            }
            
            // upload fcm token
            let fcmToken = UserDefaults.standard.string(forKey: "fcmToken") ?? ""
            FirestoreManager.updateFCMToken(userUid: authResult.user.uid, fcmToken: fcmToken) { success in
                if !success {
                    print("Could not update FCMToken")
                    completion("Please try again")
                } else {
                    completion(nil)
                }
            }
        }
    }
    
    /// Signs out the currently logged-in user.
    /// - Parameter completion: A closure that gets called once the user is signed out.
    public static func signOut(completion: @escaping () -> Void) {
//        FirestoreManager.updateFCMToken(userUid: getCurrentUserUid2(), fcmToken: "") { success in
//            if !success {
//                fatalError("Could not remove users FCM token")
//            }
            do {
                try auth.signOut()
                completion()
            } catch let signOutError {
                fatalError("Error signing out: \(signOutError.localizedDescription)")
            }
            
        //}
    }
    
    /// Sends a password reset email to the specified email address.
    /// - Parameters:
    ///   - email: The email address to send the password reset to.
    ///   - completion: A closure that gets called with an optional error message if the password reset fails.
    public static func sendPasswordReset(email: String, completion: @escaping (String?) -> Void ) {
        auth.sendPasswordReset(withEmail: email) { err in
            if let err = err {
                print("ERROR - resetPassword: \(err.localizedDescription)")
                return completion(err.localizedDescription)
            }
            
            return completion(nil)
        }
    }
    
    /// Deletes the currently authenticated user from Firebase Authentication.
    /// - Parameter completion: A closure that gets called with a boolean indicating the success of the operation.
    static func deleteUser(completion: @escaping (Bool) -> Void) {
        
        guard let firUser = auth.currentUser else {
            print("ERROR - deleteUser: No current user to delete")
            return completion(false)
        }
        
        firUser.delete() { err in
            
            if let err = err {
                print("ERROR - deleteUser: \(err.localizedDescription)")
                return completion(false)
            }
            
            completion(true)
        }
    }
    
    /// Registers a new user with an email and password to Firebase Authentication.
    /// - Parameters:
    ///   - email: The email address to register with.
    ///   - password: The password for the new account.
    ///   - completion: A closure that gets called with an optional error message if the registration fails.
    public static func registerAuthUser(email: String, password: String, completion: @escaping (String?) -> Void) { //
                
        auth.createUser(withEmail: email, password: password) { (authResult, err) in
            
            if err != nil {
                print("ERROR - registerAuthUser: \(err!.localizedDescription)")
                return completion(err!.localizedDescription)
            }
            
            completion(nil)
        }
    }
}
