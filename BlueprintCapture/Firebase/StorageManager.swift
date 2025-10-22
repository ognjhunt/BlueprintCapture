//
//  StorageManager.swift
//  DecorateYourRoom
//
//  Created by Nijel Hunt on 1/16/22.
//  Copyright © 2022 Placenote. All rights reserved.
//

import Foundation
import UIKit
import FirebaseStorage
import Alamofire
import CryptoKit

// StorageManager: A utility class for managing uploads and downloads with Firebase Storage.
public class StorageManager {
    
    // BlueprintError: Custom error types for storage operations.
    enum BlueprintError: Error {
        case currentUserNotFound
        case uploadFailed
        case downloadFailed
    }

    // Storage reference initialized with Firebase storage.
    static let fs = Storage.storage()
    
    // Static strings to hold various unique identifiers for storage operations.
    static var photoAnchorRandomID = ""
    static var videoAnchorRandomID = ""
    static var thumbnailRandomID = ""
    static var blueprintID = ""
    
    static var storageURL = ""
    
    
    public static func authorizeBackblazeAccount(completion: @escaping (Bool, String?, String?) -> Void) {
        let keyID = "00550218f7653950000000001" // Your keyID from the dashboard
        let applicationKey = "K00521En3D6GNXS9VFKTLXFVctlPP3Y" // Your applicationKey from the dashboard

        // Encode your keyID and applicationKey
        let credentials = Data("\(keyID):\(applicationKey)".utf8).base64EncodedString()

        let headers: HTTPHeaders = [
            "Authorization": "Basic \(credentials)"
        ]

        let url = "https://api.backblazeb2.com/b2api/v1/b2_authorize_account"

        AF.request(url, method: .get, headers: headers).responseJSON { response in
            switch response.result {
            case .success(let value):
                if let json = value as? [String: Any],
                   let authToken = json["authorizationToken"] as? String,
                   let uploadUrl = json["apiUrl"] as? String {
                    // The URL used for uploading files is combined with the API endpoint to get the complete upload URL
                    let completeUploadUrl = "\(uploadUrl)/b2api/v1"
                    print("\(completeUploadUrl) is completeUploadUrl")
                    completion(true, authToken, completeUploadUrl)
                } else {
                    print("Authorization failed, unexpected response format.")
                    completion(false, nil, nil)
                }
            case .failure(let error):
                print("Authorization failed: \(error.localizedDescription)")
                completion(false, nil, nil)
            }
        }
    }
    
    public static func getUploadUrl(authorizationToken: String, apiUrl: String, bucketId: String, completion: @escaping (Bool, String?, String?) -> Void) {
        let headers: HTTPHeaders = [
            "Authorization": authorizationToken
        ]
        
        let parameters: Parameters = [
            "bucketId": bucketId
        ]
        
        let url = "\(apiUrl)/b2_get_upload_url"
        print("\(url) is url")
        AF.request(url, method: .post, parameters: parameters, encoding: JSONEncoding.default, headers: headers).responseJSON { response in
            switch response.result {
            case .success(let value):
                if let json = value as? [String: Any], let uploadUrl = json["uploadUrl"] as? String, let uploadAuthorizationToken = json["authorizationToken"] as? String {
                    completion(true, uploadUrl, uploadAuthorizationToken)
                } else {
                    print("Failed to get upload URL, response: \(response)")
                    completion(false, nil, nil)
                }
            case .failure(let error):
                print("Failed to get upload URL: \(error.localizedDescription), response: \(response)")
                completion(false, nil, nil)
            }
        }
    }
    
    public static func updateProfilePicture(withData data: Data, completion: @escaping (String?) -> Void) {
        guard let currentUserUid = FirebaseAuthHelper.getCurrentUserUid() else {
            return completion(nil)
        }
        
        var bucketString: String
        #if DEBUG
        bucketString = "054022e1986fd72685d30915"
        #elseif TEST
        bucketString = "05b052a1281fd72685d30915"
        #elseif RELEASE
        bucketString = "95d072c1281fd72685d30915"
        #else
        bucketString = "054022e1986fd72685d30915"
        #endif
        
        // Replace with your Backblaze B2 bucket name
        let bucketId = bucketString

        // Step 1: Get authorization token and API URL
        authorizeBackblazeAccount { (success, authToken, apiUrl) in
            guard success, let authToken = authToken, let apiUrl = apiUrl else {
                print("Authorization failed")
                return completion(nil)
            }

            // Step 2: Get upload URL
            getUploadUrl(authorizationToken: authToken, apiUrl: apiUrl, bucketId: bucketId) { (success, uploadUrl, uploadAuthToken) in
                guard success, let uploadUrl = uploadUrl, let uploadAuthToken = uploadAuthToken else {
                    print("Failed to get upload URL")
                    return completion(nil)
                }

                // Step 3: Upload file
                let headers: HTTPHeaders = [
                    "Authorization": uploadAuthToken,
                    "X-Bz-File-Name": currentUserUid + ".jpg",
                    "Content-Type": "image/jpeg",
                    "X-Bz-Content-Sha1": data.sha1() // Compute SHA1 of the data
                ]

                AF.upload(data, to: uploadUrl, method: .post, headers: headers).responseJSON { response in
                    switch response.result {
                    case .success(let value):
                        if let json = value as? [String: Any], let fileID = json["fileId"] as? String {
                            print("Upload successful, file ID: \(fileID)")
                            completion(fileID)
                        } else {
                            print("File upload failed, response: \(response)")
                            completion(nil)
                        }
                    case .failure(let error):
                        print("Error uploading to Backblaze B2: \(error)")
                        if let data = response.data, let responseString = String(data: data, encoding: .utf8) {
                            print("Response data: \(responseString)")
                        }
                        completion(nil)
                    }
                }
            }
        }
    }


    
    // updateProfilePicture: Uploads a profile picture to Firebase Storage and returns the unique ID upon completion.
//    public static func updateProfilePicture(withData data: Data, completion: @escaping (String?) -> Void ) {
//        guard let currentUserUid = FirebaseAuthHelper.getCurrentUserUid() else {
//            return completion(nil)
//        }
//
//        #if DEBUG
//        storageURL = "gs://blueprint-8c1ca.appspot.com"
//        #elseif TEST
//        storageURL = "gs://blueprint-test-55a23.appspot.com"
//        #elseif RELEASE
//        storageURL = "gs://blueprint-prod-f0f19.appspot.com"
//        #else
//        storageURL = "gs://blueprint-8c1ca.appspot.com"
//        #endif
//
//        let ref = fs.reference(forURL: "\(storageURL)").child("profileImages")
//        let refUid = "\(currentUserUid)"
//        let photoRef = ref.child(refUid)
//
//        photoRef.putData(data, metadata: nil) {storageMetaData, err in
//            if let err = err { print(err.localizedDescription); completion(nil); return }
//            completion(refUid)
//        }
//    }
    
    // randomStorageString: Generates a random alphanumeric string of specified length.
    public static func randomStorageString(length: Int) -> String {
      let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
      return String((0..<length).map{ _ in letters.randomElement()! })
    }
    
    // uploadBlueprint: Uploads a blueprint model file to Firebase Storage with metadata and returns a custom file name upon completion.
    public static func uploadBlueprint(withData data: Data, name: String, completion: @escaping (String?) -> Void) {
      //  guard let currentUserUid = FirebaseAuthHelper.getCurrentUserUid() else {
            let ref = fs.reference(forURL: "gs://blueprint-8c1ca.appspot.com").child("blueprints")
            let randID = NSUUID().uuidString
            let blueprintID = "\(randID)-\(name).usdz"
            let networkRef = ref.child(blueprintID)

            let metadata = StorageMetadata()
            metadata.contentType = "model/vnd.usdz+zip"

            networkRef.putData(data, metadata: metadata) { storageMetaData, error in
                if let error = error {
                    print(error.localizedDescription)
                    completion(nil)
                    return
                }
                
                completion(blueprintID)
            }
    }

    // uploadBlueprint(withFileURL:completion:): Uploads a blueprint model file using a file URL to Firebase Storage and returns the unique ID upon completion.
    public static func uploadBlueprint(withFileURL fileURL: URL, completion: @escaping (String?) -> Void ) {
        guard let currentUserUid = FirebaseAuthHelper.getCurrentUserUid() else {
            return completion(nil)
        }

        let ref = fs.reference(forURL: "gs://blueprint-8c1ca.appspot.com").child("blueprints")
      //  let refUid = "\(currentUserUid)"
        let randID = NSUUID().uuidString// self.randomStorageString(length: 30)
        self.blueprintID = randID
        let networkRef = ref.child(randID)
        
        do {
            let data = try Data(contentsOf: fileURL)

            networkRef.putData(data, metadata: nil) {storageMetaData, err in
                if let err = err { print(err.localizedDescription); completion(nil); return }
                completion(randID)
            }
        } catch {
            print(error.localizedDescription)
            completion(nil)
        }
    }

    // uploadThumbnail: Uploads a thumbnail image to Firebase Storage and returns the unique ID upon completion.
    public static func uploadThumbnail(withData data: Data, completion: @escaping (String?) -> Void ) {
        guard let currentUserUid = FirebaseAuthHelper.getCurrentUserUid() else {
            return completion(nil)
        }

        let ref = fs.reference(forURL: "gs://blueprint-8c1ca.appspot.com").child("thumbnails")
        let randID = NSUUID().uuidString
        self.thumbnailRandomID = randID
        let photoRef = ref.child(randID)

        photoRef.putData(data, metadata: nil) { storageMetaData, error in
            if let error = error {
                print("Error uploading thumbnail:", error.localizedDescription)
                completion(nil)
                return
            }
            completion(randID)
        }
    }

    
    
    // uploadVideo: Uploads a video file to Firebase Storage and returns the unique ID upon completion.
    public static func uploadVideo(withData data: Data, completion: @escaping (String?) -> Void ) {
        guard let currentUserUid = FirebaseAuthHelper.getCurrentUserUid() else {
            return completion(nil)
        }

        let ref = fs.reference(forURL: "gs://blueprint-8c1ca.appspot.com").child("videos")
      //  let refUid = "\(currentUserUid)"
        let randID = NSUUID().uuidString// self.randomStorageString(length: 30)
        self.videoAnchorRandomID = randID
        let photoRef = ref.child(randID)
        
        photoRef.putData(data, metadata: nil) {storageMetaData, err in
            if let err = err {
                print(err.localizedDescription)
                completion(nil)
                return
                
            }
            completion(randID)
        }
    }
    
    // deleteUserDirectory: Deletes all files in a user's directory in Firebase Storage and returns a boolean upon completion.
    public static func deleteUserDirectory(_ userUid: String, completion: @escaping (Bool) -> Void) {
        
        let fileRef = fs.reference(withPath: userUid)
        
        fileRef.listAll { storageListResult, err in
            var count = 0
            for fileRef in storageListResult!.items {
                print("Deleting \(fileRef.fullPath)")
                fileRef.delete { err in
                    if let err = err {
                        print("ERROR - deleteUserDirectory: \(err)")
                    }
                    completion(false)
                    
                    count += 1
                    if (count == storageListResult?.items.count) {
                        return completion(true)
                    }
                }
            }
        }
    }
    
    
    // Create a cache for the images
    private static var profilePicCache = configureCache()
    private static var photoPicCache = configureCache()

    // Initializes and configures a cache specific for image storage, setting an object limit and enabling eviction of objects with discarded content for optimal memory management.
    private static func configureCache() -> NSCache<NSString, UIImage> {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 10
        cache.evictsObjectsWithDiscardedContent = true
        return cache
    }

    // Retrieves a user's profile picture from the cache or remotely if not cached. It uses a specified cache for profile images and handles asynchronous completion via a closure.
//    public static func getProPic(_ userId: String, completion: @escaping (UIImage) -> Void) {
//        getImage(from: "profileImages", id: userId, cache: profilePicCache, completion: completion)
//    }
    public static func getProPic(_ userId: String, completion: @escaping (UIImage) -> Void) {
        // Construct the URL to the photo in Backblaze B2
        var urlString: String
        #if DEBUG
        urlString = "uploadedProfileImages-dev"
        #elseif TEST
        urlString = "uploadedProfileImages-test"
        #elseif RELEASE
        urlString = "uploadedProfileImages-prod"
        #else
        urlString = "uploadedProfileImages-dev"
        #endif
        
        let backblazeURL = "https://f005.backblazeb2.com/file/\(urlString)/\(userId).jpg"

        AF.request(backblazeURL).responseData { response in
            switch response.result {
            case .success(let data):
                let image = UIImage(data: data) ?? UIImage(named: "nouser")!
                completion(image)
            case .failure(let error):
                print("Error downloading image: \(error.localizedDescription)")
                // Return a default image in case of error
                completion(UIImage(named: "nouser")!)
            }
        }
    }


    // Retrieves a photo by its ID from the cache or remotely if not cached. It uses a specified cache for photo images and invokes the provided completion handler once the image is retrieved.
//    public static func getPhotoPic(_ photoId: String, completion: @escaping (UIImage?) -> Void) {
//        getImage(from: "photos", id: "\(photoId).jpg", cache: photoPicCache, completion: completion)
//    }
//
    public static func getPhotoPic(_ photoId: String, completion: @escaping (UIImage?) -> Void) {
        
        var urlString: String
        #if DEBUG
        urlString = "uploadedPhotos-dev"
        #elseif TEST
        urlString = "uploadedPhotos-test"
        #elseif RELEASE
        urlString = "uploadedPhotos-prod"
        #else
        urlString = "uploadedPhotos-dev"
        #endif
        
        // Construct the URL to the photo in Backblaze B2
        let backblazeURL = "https://f005.backblazeb2.com/file/\(urlString)/\(photoId).jpg"

        AF.request(backblazeURL).responseData { response in
            switch response.result {
            case .success(let data):
                let image = UIImage(data: data)
                completion(image)
            case .failure(let error):
                print("Error downloading image: \(error.localizedDescription)")
                completion(nil)
            }
        }
    }
    
//    public static func downloadFileContent(fileID: String, fileName: String, fileType: String, completion: @escaping (URL?) -> Void) {
//
//        var urlString: String
//            #if DEBUG
//            urlString = "uploadedFiles-dev"
//            #elseif TEST
//            urlString = "uploadedFiles-test"
//            #elseif RELEASE
//            urlString = "uploadedFiles-prod"
//            #else
//            urlString = "uploadedFiles-dev"
//            #endif
//
//            let downloadURLString = "https://f005.backblazeb2.com/file/uploadedFiles-dev/6B1059F6-4D55-4E93-9BB6-F5DAC017ED7A.Screenshot+2024-02-22+at+4.23.08%E2%80%AFPM.png" //"https://f005.backblazeb2.com/file/\(urlString)/\(fileID).\(fileName).\(fileType)"
//        print("\(downloadURLString)) is downloadURLString")
//
//            let destination: DownloadRequest.Destination = { _, _ in
//                let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
//                let fileURL = documentsURL.appendingPathComponent("\(fileID)")
//                return (fileURL, [.removePreviousFile, .createIntermediateDirectories])
//            }
//
//            AF.download(downloadURLString, to: destination).response { response in
//                switch response.result {
//                case .success(let url):
//                    print("File downloaded successfully: \(url?.path ?? "unknown path")")
//                    completion(url)
//                case .failure(let error):
//                    print("Error downloading file: \(error.localizedDescription)")
//                    completion(nil)
//                }
//            }
//        }
    
    public static func downloadFileContent(fileID: String, fileName: String, fileType: String, completion: @escaping (URL?) -> Void) {
        
        var bucketString: String
        #if DEBUG
        bucketString = "uploadedFiles-dev"
        #elseif TEST
        bucketString = "uploadedFiles-test"
        #elseif RELEASE
        bucketString = "uploadedFiles-prod"
        #else
        bucketString = "uploadedFiles-dev"
        #endif
        
        let fileExtension = fileType.hasPrefix(".") ? "" : "."
        let urlString = "https://f005.backblazeb2.com/file/\(bucketString)/\(fileID)_\(fileName)"
        
        print("\(urlString) is downloadURLString")

        // Determine local file URL
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("Error: Could not get document directory URL")
            completion(nil)
            return
        }
//        let localFileURL = documentsURL.appendingPathComponent("\(fileID)\(fileExtension)\(fileType)")
        let localFileURL = documentsURL.appendingPathComponent("\(fileID).\(fileType)")
        print("\(localFileURL) is localFileURL")

        
        // Check if the file already exists locally, if so, return it immediately
        if FileManager.default.fileExists(atPath: localFileURL.path) {
            completion(localFileURL)
            return
        }

        // Download and write to file
        AF.download(urlString, to: { _, _ in (localFileURL, [.removePreviousFile, .createIntermediateDirectories]) })
            .response { response in
                switch response.result {
                case .success(let url):
                    print("File downloaded successfully: \(url?.path ?? "unknown path")")
                    completion(localFileURL)
                case .failure(let error):
                    print("Error downloading file: \(error.localizedDescription)")
                    completion(nil)
                }
            }
    }

    
//    public static func downloadFileContent(storagePath: String, completion: @escaping (URL?) -> Void) {
//
//        var urlString: String
//            #if DEBUG
//            urlString = "uploadedFiles-dev"
//            #elseif TEST
//            urlString = "uploadedFiles-test"
//            #elseif RELEASE
//            urlString = "uploadedFiles-prod"
//            #else
//            urlString = "uploadedFiles-dev"
//            #endif
//
//            let downloadURLString = "https://f005.backblazeb2.com/b2api/v1/b2_download_file_by_id?fileId=\(storagePath)"
//        print("\(downloadURLString)) is downloadURLString")
//
//            let destination: DownloadRequest.Destination = { _, _ in
//                let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
//                let fileURL = documentsURL.appendingPathComponent(storagePath.components(separatedBy: "/").last ?? "downloadedFile")
//                return (fileURL, [.removePreviousFile, .createIntermediateDirectories])
//            }
//
//            AF.download(downloadURLString, to: destination).response { response in
//                switch response.result {
//                case .success(let url):
//                    print("File downloaded successfully: \(url?.path ?? "unknown path")")
//                    completion(url)
//                case .failure(let error):
//                    print("Error downloading file: \(error.localizedDescription)")
//                    completion(nil)
//                }
//            }
//        }

    
    
    public static func getDownloadAuthorization(bucketId: String, fileNamePrefix: String, completion: @escaping (Bool, String?) -> Void) {
        authorizeBackblazeAccount { (success, authToken, apiUrl) in
            guard success, let authToken = authToken, let apiUrl = apiUrl else {
                print("Authorization failed")
                return completion(false, nil)
            }
            
            let headers: HTTPHeaders = [
                "Authorization": authToken
            ]
            
            let parameters: Parameters = [
                "bucketId": bucketId,
                "fileNamePrefix": fileNamePrefix // Filename or prefix to get authorization for
            ]
            
            let url = "\(apiUrl)/b2_get_download_authorization"
            print("\(url) is url")
            AF.request(url, method: .post, parameters: parameters, encoding: JSONEncoding.default, headers: headers).responseJSON { response in
                switch response.result {
                case .success(let value):
                    if let json = value as? [String: Any], let downloadAuthToken = json["authorizationToken"] as? String {
                        completion(true, downloadAuthToken)
                    } else {
                        print("Failed to get download authorization, response: \(response)")
                        completion(false, nil)
                    }
                case .failure(let error):
                    print("Failed to get download authorization: \(error.localizedDescription)")
                    completion(false, nil)
                }
            }
        }
    }


    // Core method to fetch an image either from cache or Firebase storage based on the directory and id provided. If the image isn't cached, it fetches from remote storage, caches it, and then returns it via the completion handler.
    private static func getImage(from directory: String, id: String, cache: NSCache<NSString, UIImage>, completion: @escaping (UIImage) -> Void) {
        if let cachedImage = cache.object(forKey: id as NSString) {
            return completion(cachedImage)
        }

        #if DEBUG
        storageURL = "gs://blueprint-8c1ca.appspot.com"
        #elseif TEST
        storageURL = "gs://blueprint-test-55a23.appspot.com"
        #elseif RELEASE
        storageURL = "gs://blueprint-prod-f0f19.appspot.com"
        #else
        storageURL = "gs://blueprint-8c1ca.appspot.com"
        #endif
        
        let defaultImage = UIImage(named: "nouser") ?? UIImage()
        let ref = fs.reference(forURL: "\(storageURL)").child(directory).child(id)
        ref.getData(maxSize: 10000000) { (data, err) in
            if let err = err {
                print("ERROR - getImage: \(err.localizedDescription)")
            }

            guard let data = data, let image = UIImage(data: data) else {
                return completion(defaultImage)
            }

            cache.setObject(image, forKey: id as NSString)
            completion(image)
        }
    }

    // Defines and initializes a cache dedicated to portal video content with a count limit to conserve memory usage.
    private static let portalVideoCache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.countLimit = 5 // Limit to 5 videos; adjust as needed
        return cache
    }()

    // Retrieves a video from the cache or downloads it if it's not available in the cache. The completion handler is called with the video data or nil if an error occurs.
    public static func getPortalVideo(_ storagePath: String, completion: @escaping (Data?) -> Void) {
        if let cachedData = portalVideoCache.object(forKey: storagePath as NSString) {
            completion(cachedData as Data)
            return
        }

        fetchAndCacheVideo(storagePath: storagePath, completion: completion)
    }

    // Downloads video data from Firebase storage, caches it, and provides it through the completion handler. Errors in download are handled gracefully with appropriate log messages.
    private static func fetchAndCacheVideo(storagePath: String, completion: @escaping (Data?) -> Void) {
        let ref = fs.reference(forURL: "gs://blueprint-8c1ca.appspot.com").child("portalVideos").child(storagePath)
        ref.getData(maxSize: 400 * 1024 * 1024) { (data, err) in
            if let err = err {
                print("ERROR - getPortalVideo: \(err.localizedDescription)")
                completion(nil)
                return
            }

            guard let videoData = data else {
                print("ERROR - getPortalVideo: Could not get video data for \(storagePath)")
                completion(nil)
                return
            }

            portalVideoCache.setObject(videoData as NSData, forKey: storagePath as NSString)
            completion(videoData)
        }
    }


    // Establishes a general-purpose image cache with a specific object count limit and discarding policy for content that has been evicted from the cache.
    private static var imageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 70
        cache.evictsObjectsWithDiscardedContent = true
        return cache
    }()

    // Comment for ThumbnailType:
    // Enumerates types of thumbnails that can be retrieved, defining the category under which the thumbnail image is stored.
    public enum ThumbnailType: String {
        case model
        case portal
        case blueprint
        case widget
    }

    // Comment for getThumbnail:
    // Fetches a thumbnail image from cache or Firebase storage based on the type and name. If not found, a default image is returned. The image is cached upon retrieval for future use.
    public static func getThumbnail(ofType type: ThumbnailType, named thumbnailName: String, completion: @escaping (UIImage) -> Void) {
        if let cachedImage = imageCache.object(forKey: thumbnailName as NSString) {
            return completion(cachedImage)
        }

        let defaultImage = UIImage(named: "nouser") ?? UIImage()
        
        // Check if the thumbnail name has a .jpeg extension and change it to .jpg
        var updatedThumbnailName = thumbnailName
        if thumbnailName.hasSuffix(".jpeg") {
            updatedThumbnailName = String(thumbnailName.dropLast(5)) + ".jpg"
        }
        
        var urlString: String
        #if DEBUG
        urlString = "contentThumbnails-dev"
        #elseif TEST
        urlString = "contentThumbnails-test"
        #elseif RELEASE
        urlString = "contentThumbnails-prod"
        #else
        urlString = "contentThumbnails-dev"
        #endif
        
        let downloadURL = "https://f005.backblazeb2.com/file/\(urlString)/\(updatedThumbnailName)"

        AF.request(downloadURL).responseData { response in
            debugPrint("Response: \(response)") // Logging the response

            switch response.result {
            case .success(let data):
                print("Data size: \(data.count) bytes") // Log the size of the incoming data

                if let responseString = String(data: data, encoding: .utf8) {
                    print("Received data: \(responseString)")
                }
                
                if let image = UIImage(data: data) {
                    imageCache.setObject(image, forKey: updatedThumbnailName as NSString)
                    completion(image)
                } else {
                    print("Could not convert data to UIImage.") // Log conversion failure
                    completion(defaultImage)
                }
            case .failure(let error):
                print("ERROR - getThumbnail: \(error.localizedDescription)")
                completion(defaultImage)
            }
        }
    }




    
    
    
    // Comment for deleteProPic:
    // Deletes a user's profile picture from Firebase storage and informs of success or failure through the completion handler.
//    static func deleteProPic(_ userUid: String, completion: @escaping (Bool) -> Void) {
//
//        fs.reference().child("\(userUid)").delete() { err in
//
//            if let err = err {
//                print("ERROR - deleteProPic: \(err.localizedDescription)")
//                return completion(false)
//            }
//
//            return completion(true)
//        }
//    }
    
    // Comment for deleteProPic:
    // Deletes a user's profile picture from Backblaze B2 storage and informs of success or failure through the completion handler.
    static func deleteProPic(_ userUid: String, completion: @escaping (Bool) -> Void) {
        
        // Step 1: Get authorization token and API URL
        authorizeBackblazeAccount { (success, authToken, apiUrl) in
            guard success, let authToken = authToken, let apiUrl = apiUrl else {
                print("Authorization failed")
                completion(false)
                return
            }

            // Step 2: Obtain the file name to be deleted
            let fileName = "\(userUid).jpg"
            
            var bucketString: String
            #if DEBUG
            bucketString = "054022e1986fd72685d30915"
            #elseif TEST
            bucketString = "05b052a1281fd72685d30915"
            #elseif RELEASE
            bucketString = "95d072c1281fd72685d30915"
            #else
            bucketString = "054022e1986fd72685d30915"
            #endif
            
            let bucketId = bucketString
            
            // Step 3: Call the B2 API to delete the file
            let headers: HTTPHeaders = [
                "Authorization": authToken
            ]
            
            let parameters: Parameters = [
                "fileName": fileName,
                "bucketId": bucketId // Replace with your actual bucket ID
            ]
            
            let deleteUrl = "\(apiUrl)/b2api/v1/b2_delete_file_version"

            AF.request(deleteUrl, method: .post, parameters: parameters, encoding: JSONEncoding.default, headers: headers).responseJSON { response in
                switch response.result {
                case .success:
                    print("File deletion successful for file: \(fileName)")
                    completion(true)
                case .failure(let error):
                    print("Error during file deletion: \(error.localizedDescription)")
                    completion(false)
                }
            }
        }
    }


}

extension Data {
    func sha1() -> String {
        let digest = Insecure.SHA1.hash(data: self)
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
}
