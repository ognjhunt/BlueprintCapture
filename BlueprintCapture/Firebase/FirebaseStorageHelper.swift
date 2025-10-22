//
//  FirebaseStorageHelper.swift
//  DecorateYourRoom
//
//  Created by Nijel Hunt on 10/13/21.
//  Copyright © 2021 Placenote. All rights reserved.
//

import Foundation
import Firebase
import FirebaseStorage
import FirebaseFirestore

/// A utility class for interacting with Firebase Cloud Storage, providing methods to perform download tasks.
class FirebaseStorageHelper {
    
    static private let cloudStorage = Storage.storage()
    
    private static let db = Firestore.firestore()
    
    /// Asynchronously downloads a file from Firebase Storage and saves it to the local file system.
    /// - Parameters:
    ///   - relativePath: The path within Firebase Storage where the file is located.
    ///   - handler: A closure that is invoked with the local file URL on successful download, or nil if an error occurs.
    class func asyncDownloadToFilesystem(relativePath: String, handler: @escaping (_ fileUrl: URL?) -> Void) {
        // Create local filesystem URL
        guard let docsUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("Error: Could not get document directory URL")
            handler(nil)
            return
        }
        
        let fileUrl = docsUrl.appendingPathComponent(relativePath)
        
        // Check if the file already exists
        if FileManager.default.fileExists(atPath: fileUrl.path) {
            handler(fileUrl)
            return
        }
        
        // Reference to cloud storage
        let storageRef = cloudStorage.reference(withPath: relativePath)
        
        // Download and write to file
        storageRef.write(toFile: fileUrl) { url, error in
            if let error = error {
                print("Firebase storage: Error downloading file with relativePath: \(relativePath), Error: \(error.localizedDescription)")
                handler(nil)
                return
            }
            
            guard let localUrl = url else {
                print("Firebase storage: Unexpected error, URL is nil")
                handler(nil)
                return
            }
            
            handler(localUrl)
        }.resume()
    }
}
