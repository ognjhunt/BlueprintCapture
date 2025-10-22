//
//  FirestoreManager.swift
//  DecorateYourRoom
//
//  Created by Nijel Hunt on 1/10/22.
//  Copyright © 2022 Placenote. All rights reserved.
//

import Foundation
import Firebase
import FirebaseAuth
import FirebaseFirestore
//import GeoFire
 
import Geohasher
import CoreLocation

struct BlueprintCache {
    var blueprintIDs: [String]
    var lastUpdated: Date
}

 
/// `LocationCoordinate` represents a geographical coordinate using latitude and longitude.
struct LocationCoordinate {
    var latitude: Double
    var longitude: Double
    var altitude: Double
}

/// `FirestoreManager` is a utility class responsible for handling all interactions
/// with the Firestore database. It includes caching mechanisms and provides static methods
/// to fetch various objects from the database such as User, Photo, Blueprint, etc.
public class FirestoreManager {

     private static let db = Firestore.firestore()
    static private let auth = Auth.auth()

    

    public static func save<T: Encodable>(collection: String, id: String, value: T) {
        do {
            let encoded = try Firestore.Encoder().encode(value)
            db.collection(collection).document(id).setData(encoded, merge: true)
        } catch {
            print("Failed to save \(T.self): \(error)")
        }
    }
    
    //MARK: ------------------------ USER ------------------------
    
    // Create a cache for the users
    private static var userCache = NSCache<NSString, User>()
//
//    /// Retrieves a `User` object for a given UID. It first attempts to retrieve the user from
//    /// a cache. If the user is not found in the cache, it fetches from Firestore and then stores
//    /// it in the cache before returning it via the completion handler.
//    /// - Parameters:
//    ///   - userUid: The unique identifier for the user.
//    ///   - completion: A completion handler with an optional `User` object.
    public static func getUser(_ userUid: String, completion: @escaping (User?) -> Void ) {
        let functionStartTime = Date()
        print("\(functionStartTime) - getUser called for UID: \(userUid)")
        userCache.countLimit = 50
        userCache.evictsObjectsWithDiscardedContent = true
        
        // Check if the user is in the cache
        if let cachedUser = userCache.object(forKey: userUid as NSString) {
            print("\(Date()) - getUser: User \(userUid) served from cache.")
            // Return the cached user
            return completion(cachedUser)
        }
        print("\(Date()) - getUser: User \(userUid) not in cache, fetching from Firestore.")
        // Check if the user is authenticated
        if Auth.auth().currentUser != nil {
            // User is authenticated, fetch it from Firestore
            let docRef = db.collection("users").document(userUid)
            docRef.getDocument { docSnapshot, err in
                if let err = err {
                    print("ERROR - getUser: \(err)")
                    return completion(nil)
                }

                guard let docSnapshot = docSnapshot, let userFirDoc = docSnapshot.data() else {
                    print("ERROR - getUser: Could not get user \(userUid)")
                    return completion(nil)
                }

                // Create a new user object from the retrieved data
                let user = User(userFirDoc)

                // Add the user to the cache
                userCache.setObject(user, forKey: userUid as NSString)

                let functionEndTime = Date()
                print("\(functionEndTime) - getUser: User \(userUid) fetched from Firestore. Duration: \(functionEndTime.timeIntervalSince(functionStartTime)) seconds.")
                completion(user)
            }
        } else {
            // User is not authenticated, check for temporary user in UserDefaults
            if let userData = UserDefaults.standard.dictionary(forKey: "temporaryUser") as? [String: Any],
               let tempUserID = userData["tempID"] as? String, tempUserID == userUid {
                let user = User(userData)
                let functionEndTime = Date()
                print("\(functionEndTime) - getUser: Temporary user \(userUid) served from UserDefaults. Duration: \(functionEndTime.timeIntervalSince(functionStartTime)) seconds.")
                completion(user)
            } else {
                let functionEndTime = Date()
                print("\(functionEndTime) - getUser: User \(userUid) not found. Duration: \(functionEndTime.timeIntervalSince(functionStartTime)) seconds.")
                completion(nil)
            }
        }
    }

    /// Fetches a `Blueprint` object by its ID from Firestore. If the object is found, it's returned via
    /// the completion handler, otherwise `nil` is returned.
    /// - Parameters:
    ///   - id: The unique identifier for the blueprint.
    ///   - completion: A completion handler with an optional `Blueprint` object.
    public static func getBlueprint(_ id: String, completion: @escaping (Blueprint?) -> Void ) {
        let functionStartTime = Date()
        print("\(functionStartTime) - getBlueprint called for ID: \(id)")
        
        let docRef = db.collection("blueprints").document(id)
        
        docRef.getDocument { docSnapshot, err in
            let functionEndTime = Date()
            if let err = err {
                print("\(functionEndTime) - ERROR - getBlueprint: \(err). ID: \(id). Duration: \(functionEndTime.timeIntervalSince(functionStartTime)) seconds.")
            }
            
            guard let docSnapshot = docSnapshot, let userFirDoc = docSnapshot.data() else {
                print("\(functionEndTime) - ERROR - getBlueprint: Could not get blueprint \(id). Duration: \(functionEndTime.timeIntervalSince(functionStartTime)) seconds.")
                return completion(nil)
            }
            
            print("\(functionEndTime) - getBlueprint: Blueprint \(id) fetched successfully. Duration: \(functionEndTime.timeIntervalSince(functionStartTime)) seconds.")
            completion(Blueprint(userFirDoc))
        }
    }

    public struct MarkedPointData {
      public let id: String
      public let name: String
      public let x: Double
      public let y: Double
      public let z: Double

      init?(dictionary: [String: Any]) {
        guard let id = dictionary["id"] as? String,
              let name = dictionary["name"] as? String,
              let x = dictionary["x"] as? Double,
              let y = dictionary["y"] as? Double,
              let z = dictionary["z"] as? Double else { return nil }
        self.id = id
        self.name = name
        self.x = x
        self.y = y
        self.z = z
      }
    }

    public static func getMarkedPoints(blueprintId: String,
                                       completion: @escaping ([MarkedPointData]) -> Void) {
      let docRef = db.collection("blueprints").document(blueprintId)
      docRef.getDocument { snapshot, _ in
        guard let data = snapshot?.data(),
              let points = data["markedPoints"] as? [[String: Any]] else {
          completion([])
          return
        }
        let mapped = points.compactMap { MarkedPointData(dictionary: $0) }
        completion(mapped)
      }
    }

    

    public static func fetchKnowledgeChunks(blueprintId: String, limit: Int = 12, completion: @escaping ([BlueprintKnowledgeChunk]) -> Void) {
        let collection = db.collection("blueprints").document(blueprintId).collection("knowledge_chunks")
        var query: Query = collection
        if limit > 0 {
            query = query.limit(to: limit)
        }
        query.getDocuments { snapshot, error in
            if let error = error {
                print("Failed to fetch knowledge chunks: \(error.localizedDescription)")
                completion([])
                return
            }
            guard let documents = snapshot?.documents else {
                completion([])
                return
            }
            let chunks = documents.compactMap { doc -> BlueprintKnowledgeChunk? in
                BlueprintKnowledgeChunk(id: doc.documentID, data: doc.data())
            }
            let sorted = chunks.sorted { lhs, rhs in
                let lhsOrder = lhs.order ?? Int.max
                let rhsOrder = rhs.order ?? Int.max
                if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
                let lhsScore = lhs.score ?? 0
                let rhsScore = rhs.score ?? 0
                if lhsScore != rhsScore { return lhsScore > rhsScore }
                return lhs.id < rhs.id
            }
            completion(sorted)
        }
    }

    

    private static var blueprintCache = NSCache<NSString, Blueprint>()

    /// Requests a `Session` object from Firestore using a document ID and passes it to the completion handler.
    /// - Parameters:
    ///   - id: The unique identifier for the session.
    ///   - completion: A completion handler with an optional `Session` object.
    public static func getSession(_ id: String, completion: @escaping (Session?) -> Void ) {
        
        let docRef = db.collection("sessionEvents").document(id)
        
        docRef.getDocument { docSnapshot, err in
            if let err = err {
                print("ERROR - getSession: \(err)")
            }
            
            guard let docSnapshot = docSnapshot, let userFirDoc = docSnapshot.data() else {
                print("ERROR - getSession: Could not get session \(id)")
                return completion(nil)
            }
            
            completion(Session(userFirDoc))
        }
    }

    // MARK: - Generic Typed Save Helper
    /// Saves an Encodable value to a Firestore collection/document.
    /// - Parameters:
    ///   - collection: Top-level collection name.
    ///   - id: Document ID to write.
    ///   - value: Encodable value to serialize.
    ///   - completion: Optional completion with error if any.
    public static func save<T: Encodable>(collection: String, id: String, value: T, completion: ((Error?) -> Void)? = nil) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(value)
            let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
            guard var dict = jsonObject as? [String: Any] else {
                completion?(NSError(domain: "FirestoreManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Encoding failed"]))
                return
            }
            // Always attach a server-side updatedAt to track freshness
            dict["updatedAt"] = FieldValue.serverTimestamp()
            db.collection(collection).document(id).setData(dict) { error in
                completion?(error)
            }
        } catch {
            completion?(error)
        }
    }
    

    
    

    
 
   
    /// Retrieves the blueprints created by a specific user from Firestore.
    /// - Parameters:
    ///   - userUid: The unique identifier for the user.
    ///   - completion: A closure that gets called with an array of `Blueprint` objects once retrieval is complete.
    static func getCreatedBlueprints(_ userUid: String, completion: @escaping ([Blueprint]) -> Void) {
        
        var ret = [Blueprint]()
            
        db.collection("blueprints").whereField(Blueprint.CREATOR, isEqualTo: userUid).getDocuments() { querySnapshot, err in
                    
            if let err = err {
                print("ERROR - getCreatedBlueprints: \(err.localizedDescription)")
                return completion(ret)
            }

            guard let querySnapshot = querySnapshot else {
                print ("ERROR - getCreatedBlueprints: querySnapshot is nil")
                return completion(ret)
            }
                
            for docSnapshot in querySnapshot.documents {
                
                if let blueprint = try? Blueprint(docSnapshot.data()) {
                    ret.append(blueprint)
                } else {
                    print("ERROR - getCreatedBlueprints: malformed event \(docSnapshot.documentID)")
                }
            }
                
            return completion(ret)
        }
    }
    
    /// Fetches the blueprints created by the user whose profile is being viewed.
    /// If the profile belongs to the current user, it uses `getCreatedBlueprints` method.
    /// This might change in future if there are changes in authentication status.
    /// - Parameters:
    ///   - userUid: The unique identifier for the profile user.
    ///   - completion: A closure that gets called with an array of `Blueprint` objects once retrieval is complete.
    static func getProfileCreatedBlueprints(_ userUid: String, completion: @escaping ([Blueprint]) -> Void) {
            // Get the current authenticated user's UID, if available
            let currentUserUid = Auth.auth().currentUser?.uid

            // Check if the userUid is the same as the authenticated user's UID
            if currentUserUid == userUid {
                // Fetch created blueprints for the authenticated current user
                getUserBlueprintIDs(userID: userUid) { blueprintIDs in
                    fetchBlueprints(fromIDs: blueprintIDs, completion: completion)
                }
            } else {
                // Fetch blueprints for a different user or a temporary user (always from Firestore)
                getCreatedBlueprints(userUid) { createdBlueprints in
                    completion(createdBlueprints)
                }
            }
        }

     // Helper method to fetch user's blueprint IDs
     private static func getUserBlueprintIDs(userID: String, completion: @escaping ([String]) -> Void) {
         if Auth.auth().currentUser != nil {
             // Fetch from Firestore
             getUser(userID) { user in
                 completion(user?.createdBlueprintIDs ?? [])
             }
         } else {
             // Fetch from UserDefaults for a temporary user
             if let userData = UserDefaults.standard.dictionary(forKey: "temporaryUser") as? [String: Any],
                let createdBlueprintIDs = userData["createdBlueprintIDs"] as? [String] {
                 completion(createdBlueprintIDs)
             } else {
                 completion([])
             }
         }
     }

     // Helper method to fetch blueprints from their IDs
     private static func fetchBlueprints(fromIDs blueprintIDs: [String], completion: @escaping ([Blueprint]) -> Void) {
         let dispatchGroup = DispatchGroup()
         var fetchedBlueprints: [Blueprint] = []

         for blueprintID in blueprintIDs {
             if !blueprintID.isEmpty {
                 dispatchGroup.enter()
                 getBlueprint(blueprintID) { blueprint in
                     if let blueprint = blueprint {
                         fetchedBlueprints.append(blueprint)
                     }
                     dispatchGroup.leave()
                 }
             }
         }

         dispatchGroup.notify(queue: .main) {
             completion(fetchedBlueprints)
         }
     }
    
    static func fetchBlueprintName(blueprintID: String, completion: @escaping (String?) -> Void) {
            let db = Firestore.firestore()
            let blueprintRef = db.collection("blueprints").document(blueprintID)

            blueprintRef.getDocument { document, error in
                if let error = error {
                    print("Error fetching blueprint: \(error)")
                    completion(nil)
                } else if let document = document, document.exists, let blueprintName = document.data()?["name"] as? String {
                    completion(blueprintName)
                } else {
                    completion(nil)
                }
            }
        }
    
    static func getAllBlueprints(completion: @escaping ([Blueprint]) -> Void) {
            let collectionRef = db.collection("blueprints")
            collectionRef.getDocuments { (snapshot, error) in
                guard let documents = snapshot?.documents else {
                    print("Error fetching documents: \(error?.localizedDescription ?? "Unknown error")")
                    completion([])
                    return
                }
                let blueprints = documents.compactMap { document -> Blueprint? in
                    return Blueprint(document.data())
                }
                completion(blueprints)
            }
        }
    
    
          
    
    var blueprint: Blueprint!

    /// Fetches blueprints within a certain radius of a given central geographical coordinate.
    /// Utilizes Firestore queries based on latitude and longitude fields.
    /// - Parameters:
    ///   - centerCoord: The central geographical coordinate around which to search.
    ///   - radiusInMeters: The radius within which to search for blueprints.
    ///   - completion: A closure that gets called with an array of `Blueprint` objects found within the radius.
//    static func getBlueprintsInRange(centerCoord: CLLocationCoordinate2D, withRadius radiusInMeters: Double, completion: @escaping ([Blueprint]) -> Void) {
//        let db = Firestore.firestore()
//
//        let latitudeQuery =  db.collection("blueprints").whereField("isPrivate", isEqualTo: false)
//            .whereField("latitude", isGreaterThan: centerCoord.latitude - 0.015)
//            .whereField("latitude", isLessThan: centerCoord.latitude + 0.015)
//        //TODO: add altitude to this
//
//        latitudeQuery.getDocuments { latitudeSnapshot, latitudeError in
//            if let latitudeError = latitudeError {
//                print("Error fetching blueprints based on latitude: \(latitudeError)")
//                completion([])
//                return
//            }
//
//            guard let latitudeSnapshot = latitudeSnapshot else {
//                print("Error: latitudeSnapshot is nil")
//                completion([])
//                return
//            }
//
//            let filteredBlueprints = latitudeSnapshot.documents.compactMap { document -> Blueprint? in
//                let blueprint = Blueprint(document.data())
//                let location = CLLocation(latitude: blueprint.latitude ?? 0, longitude: blueprint.longitude ?? 0)
//                let centerLocation = CLLocation(latitude: centerCoord.latitude, longitude: centerCoord.longitude)
//                return (centerLocation.distance(from: location) <= radiusInMeters) ? blueprint : nil
//            }
//
//            completion(filteredBlueprints)
//        }
//    }
    
    static func getBlueprintsInRange(centerCoord: CLLocationCoordinate2D, withRadius radiusInMiles: Double, completion: @escaping ([Blueprint]) -> Void) {
        let radiusInMeters = radiusInMiles * 1609.34
        let precision = geohashPrecision(forRadiusMeters: radiusInMeters)
        let centerHash = Geohasher.encode(latitude: centerCoord.latitude, longitude: centerCoord.longitude, length: precision)
        var prefixes = Set([centerHash])
        geohashNeighbors(for: centerHash).forEach { prefixes.insert($0) }

        if prefixes.isEmpty {
            completion([])
            return
        }

        let centerLocation = LocationCoordinate(latitude: centerCoord.latitude, longitude: centerCoord.longitude, altitude: 0)
        var uniqueBlueprints = [String: Blueprint]()
        let group = DispatchGroup()

        for prefix in prefixes {
            group.enter()
            db.collection("blueprints")
                .whereField("isPrivate", isEqualTo: false)
                .whereField(Blueprint.GEOHASH, isGreaterThanOrEqualTo: prefix)
                .whereField(Blueprint.GEOHASH, isLessThanOrEqualTo: prefix + "~")
                .getDocuments { snapshot, error in
                    defer { group.leave() }
                    if let error = error {
                        print("Error getting documents for geohash prefix \(prefix): \(error)")
                        return
                    }

                    guard let documents = snapshot?.documents else { return }
                    for document in documents {
                        var blueprint = Blueprint(document.data())
                        blueprint.id = document.documentID
                        guard let latitude = blueprint.latitude,
                              let longitude = blueprint.longitude else { continue }
                        let location = LocationCoordinate(latitude: latitude, longitude: longitude, altitude: blueprint.altitude ?? 0.0)
                        let distance = calculateDistanceInMiles(from: centerLocation, to: location)
                        if distance <= radiusInMiles {
                            uniqueBlueprints[document.documentID] = blueprint
                        }
                    }
                }
        }

        group.notify(queue: .main) {
            completion(Array(uniqueBlueprints.values))
        }
    }
    
    
    static func getUserBlueprintsInRange(userID: String, centerCoord: CLLocationCoordinate2D, withRadius radiusInMiles: Double, completion: @escaping ([Blueprint]) -> Void) {
            let db = Firestore.firestore()
            let radiusInMeters = radiusInMiles * 1609.34 // Convert miles to meters
            
        
            // Query all public blueprints
            let query = db.collection("blueprints").whereField("host", isEqualTo: userID)
            
            query.getDocuments { (querySnapshot, error) in
                if let error = error {
                    print("Error getting documents: \(error)")
                    completion([])
                    return
                }
                
                guard let documents = querySnapshot?.documents else {
                    print("No documents")
                    completion([])
                    return
                }
                
                let filteredBlueprints = documents.compactMap { document -> Blueprint? in
                    let blueprint = Blueprint(document.data())
                    guard let latitude = blueprint.latitude,
                          let longitude = blueprint.longitude else {
                        return nil
                    }
                    
                    let blueprintLocation = LocationCoordinate(latitude: latitude, longitude: longitude, altitude: blueprint.altitude ?? 0.0)
                    let distanceInMiles = calculateDistanceInMiles(from: LocationCoordinate(latitude: centerCoord.latitude, longitude: centerCoord.longitude, altitude: 0), to: blueprintLocation)
                    
                    // Check if the blueprint is within the specified radius
                    return (distanceInMiles <= radiusInMiles) ? blueprint : nil
                }
                
                completion(filteredBlueprints)
            }
        }
        
        // Helper function to calculate distance in miles
        private static func calculateDistanceInMiles(from origin: LocationCoordinate, to destination: LocationCoordinate) -> Double {
            let earthRadius: Double = 6371000 // Radius of the Earth in meters
            
            let deltaLatitude = radians(from: destination.latitude - origin.latitude)
            let deltaLongitude = radians(from: destination.longitude - origin.longitude)
            
            let a = sin(deltaLatitude/2) * sin(deltaLatitude/2) + cos(radians(from: origin.latitude)) * cos(radians(from: destination.latitude)) * sin(deltaLongitude/2) * sin(deltaLongitude/2)
            let c = 2 * atan2(sqrt(a), sqrt(1-a))
            
            let distanceInMeters = earthRadius * c
            return distanceInMeters * 0.000621371 // Convert meters to miles
        }
        
        private static func radians(from degrees: Double) -> Double {
            return degrees * .pi / 180
        }

        private enum GeohashDirection {
            case north, south, east, west
        }

        private static let geohashBase32: [Character] = Array("0123456789bcdefghjkmnpqrstuvwxyz")

        private static let geohashNeighborMap: [GeohashDirection: [[Character]]] = [
            .north: [Array("p0r21436x8zb9dcf5h7kjnmqesgutwvy"), Array("bc01fg45238967deuvhjyznpkmstqrwx")],
            .south: [Array("14365h7k9dcfesgujnmqp0r2twvyx8zb"), Array("238967debc01fg45kmstqrwxuvhjyznp")],
            .east:  [Array("bc01fg45238967deuvhjyznpkmstqrwx"), Array("p0r21436x8zb9dcf5h7kjnmqesgutwvy")],
            .west:  [Array("238967debc01fg45kmstqrwxuvhjyznp"), Array("14365h7k9dcfesgujnmqp0r2twvyx8zb")]
        ]

        private static let geohashBorderMap: [GeohashDirection: [Set<Character>]] = [
            .north: [Set("prxz"), Set("bcfguvyz")],
            .south: [Set("028b"), Set("0145hjnp")],
            .east:  [Set("bcfguvyz"), Set("prxz")],
            .west:  [Set("0145hjnp"), Set("028b")]
        ]

        private static func geohashPrecision(forRadiusMeters radius: Double) -> Int {
            if radius <= 0 { return 9 }
            if radius < 5 { return 9 }
            if radius < 20 { return 8 }
            if radius < 150 { return 7 }
            if radius < 610 { return 6 }
            if radius < 2400 { return 5 }
            if radius < 20000 { return 4 }
            if radius < 78000 { return 3 }
            if radius < 630000 { return 2 }
            return 1
        }

        private static func geohashNeighbors(for hash: String) -> [String] {
            let north = adjacent(hash: hash, direction: .north)
            let south = adjacent(hash: hash, direction: .south)
            let east = adjacent(hash: hash, direction: .east)
            let west = adjacent(hash: hash, direction: .west)
            let northeast = adjacent(hash: north, direction: .east)
            let northwest = adjacent(hash: north, direction: .west)
            let southeast = adjacent(hash: south, direction: .east)
            let southwest = adjacent(hash: south, direction: .west)
            return [north, south, east, west, northeast, northwest, southeast, southwest]
        }

        private static func adjacent(hash: String, direction: GeohashDirection) -> String {
            guard !hash.isEmpty else { return hash }
            let parityIndex = hash.count % 2 == 0 ? 0 : 1
            var base = String(hash.dropLast())
            let lastChar = hash.last!
            if geohashBorderMap[direction]?[parityIndex].contains(lastChar) == true {
                base = adjacent(hash: base, direction: direction)
            }
            guard let neighborChars = geohashNeighborMap[direction]?[parityIndex],
                  let index = neighborChars.firstIndex(of: lastChar) else {
                return base + String(lastChar)
            }
            let replacement = geohashBase32[index]
            return base + String(replacement)
        }

    /// Checks if the provided username is unique by querying the Firestore "users" collection.
    /// - Parameters:
    ///   - username: The username to check for uniqueness.
    ///   - completion: A closure that returns a boolean indicating the uniqueness of the username.
    public static func usernameUnique(_ username: String, completion: @escaping (Bool) -> Void) {
        db.collection("users").whereField("username", isEqualTo: username).getDocuments { querySnapshot, err in
            if let err = err {
                print("ERROR - usernameUnique: \(err.localizedDescription)")
                completion(false)
                return
            }
            
            guard let querySnapshot = querySnapshot else {
                print("ERROR - usernameUnique: querySnapshot is nil")
                completion(false)
                return
            }
            
            completion(querySnapshot.documents.isEmpty)
        }
    }
    
//    //WITH LIMITS TO RESULTS
//    static func searchModels(queryStr: String, limit: Int = 10, completion: @escaping ([Model]) -> Void) {
//        let group = DispatchGroup()
//        var ret = [String: Model]()
//
//        // Convert the search query to lowercase
//        let lowercasedQuery = queryStr.lowercased()
//
//        let searchByField: (String, @escaping ([Model]) -> Void) -> Void = { field, completion in
//            group.enter()
//            db.collection("models")
//                .order(by: field)
//                .start(at: [lowercasedQuery]) // Start at documents where 'field' is greater or equal to the search term
//                .end(at: [lowercasedQuery + "\u{f8ff}"]) // End at documents where 'field' is less than or equal to the search term
//                .limit(to: limit) // Limit the number of documents returned
//                .getDocuments { querySnapshot, err in
//                    defer { group.leave() }
//
//                    if let err = err {
//                        print("ERROR - searchModels: \(err.localizedDescription)")
//                        completion([])
//                        return
//                    }
//
//                    guard let querySnapshot = querySnapshot else {
//                        print("ERROR - searchModels: querySnapshot is nil")
//                        completion([])
//                        return
//                    }
//
//                    let models = querySnapshot.documents.compactMap { docSnapshot -> Model? in
//                        if var model = try? Model(docSnapshot.data()), model.id != "s8i5XBgPuUgGPOX1NY48tAWOfsl1" {
//                            // Convert the field to lowercase before comparison
//                            let modelNameLowercased = model.name.lowercased()
//                            let modelModelNameLowercased = model.modelName.lowercased()
//                            if modelNameLowercased.contains(lowercasedQuery) || modelModelNameLowercased.contains(lowercasedQuery) {
//                                return model
//                            }
//                        }
//                        return nil
//                    }
//
//                    completion(models)
//                }
//        }
//
//        searchByField("name") { models in
//            for model in models {
//                ret[model.id] = model
//            }
//        }
//
//        group.notify(queue: .main) {
//            completion(Array(ret.values))
//        }
//    }

    
    /// Searches for models in Firestore by name or modelName that match the given query string.
    /// It performs a Firestore query with range operators to match the search term.
    /// - Parameters:
    ///   - queryStr: The string to search for in the model's name or modelName.
    ///   - completion: A closure that gets called with an array of `Model` objects once the search is complete.
    

    
    
    
//    static func searchBlueprints(queryStr: String, completion: @escaping ([Blueprint]) -> Void) {
//        let group = DispatchGroup()
//        var ret = [String: Blueprint]()
//
//        // Convert the search query to lowercase
//        let lowercasedQuery = queryStr.lowercased()
//
//        let searchByName: (String, @escaping ([Blueprint]) -> Void) -> Void = { field, completion in
//            group.enter()
////            db.collection("blueprints")
//            db.collection("blueprints").whereField("isPrivate", isEqualTo: false)
//                .order(by: field)
//                .getDocuments { querySnapshot, err in
//                    defer { group.leave() }
//
//                    if let err = err {
//                        print("ERROR - searchBlueprints: \(err.localizedDescription)")
//                        completion([])
//                        return
//                    }
//
//                    guard let querySnapshot = querySnapshot else {
//                        print("ERROR - searchBlueprints: querySnapshot is nil")
//                        completion([])
//                        return
//                    }
//
//                    let blueprints = querySnapshot.documents.compactMap { docSnapshot -> Blueprint? in
//                        guard var blueprint = try? Blueprint(docSnapshot.data()) else { return nil }
//                        // Convert the blueprint name to lowercase before comparison
//                        let blueprintNameLowercased = blueprint.name.lowercased()
//                        if blueprintNameLowercased.contains(lowercasedQuery) {
//                            return blueprint
//                        }
//                        return nil
//                    }
//
//                    completion(blueprints)
//                }
//        }
//
//        searchByName("name") { blueprints in
//            for blueprint in blueprints {
//                ret[blueprint.id] = blueprint
//            }
//        }
//
//        group.notify(queue: .main) {
//            completion(Array(ret.values))
//        }
//    }
    
    static func searchBlueprints(queryStr: String, limit: Int = 12, lastDocument: DocumentSnapshot? = nil, completion: @escaping ([Blueprint], DocumentSnapshot?) -> Void) {
        let lowercasedQuery = queryStr.lowercased()
        
        var query = db.collection("blueprints")
            .whereField("isPrivate", isEqualTo: false)
            .order(by: "name")
        
        if let lastDocument = lastDocument {
            query = query.start(afterDocument: lastDocument)
        }
        
        query = query.limit(to: limit)
        
        query.getDocuments { querySnapshot, err in
            if let err = err {
                print("ERROR - searchBlueprints: \(err.localizedDescription)")
                completion([], nil)
                return
            }
            
            guard let querySnapshot = querySnapshot else {
                print("ERROR - searchBlueprints: querySnapshot is nil")
                completion([], nil)
                return
            }
            
            let blueprints = querySnapshot.documents.compactMap { docSnapshot -> Blueprint? in
                guard var blueprint = try? Blueprint(docSnapshot.data()) else { return nil }
                let blueprintNameLowercased = blueprint.name.lowercased()
                if blueprintNameLowercased.contains(lowercasedQuery) {
                    return blueprint
                }
                return nil
            }
            
            let lastDocumentSnapshot = querySnapshot.documents.last
            completion(blueprints, lastDocumentSnapshot)
        }
    }


    /// Saves user data to Firestore.
    /// - Parameters:
    ///   - uid: The unique identifier of the user.
    ///   - data: A dictionary of key-value pairs that represent the user's data.
    ///   - completion: A closure that gets called with an optional error string if the save operation fails.
    public static func saveUser(withID uid: String, withData data: [String:Any], completion: @escaping (String?) -> Void ) {

        db.collection("users").document(uid).setData(data) { err in
            if err != nil {
                return completion(err!.localizedDescription)
            }
            completion(nil)
        }
    }
    
    /// Retrieves the UID of the currently authenticated user, if available.
    /// - Returns: An optional string representing the UID of the currently logged-in user.
    static func getCurrentUserUid() -> String? {
        return auth.currentUser?.uid
    }
    
    /// Attempts to fetch the UID of the current user and prints an error if not found.
    /// - Returns: A string representing the UID of the current user or an empty string if no user is found.
    static func getCurrentUserUid2() -> String {
        
        if let uid = auth.currentUser?.uid {
            return uid
        } else {
            //fatalError("Could not get uid of current User")
            print("not a user")
            return ""
        }
    }
    
    // Static method to authenticate a user with email and password.
    // It performs a check to ensure neither email nor password is empty before attempting to sign in.
    // Upon successful authentication or failure, the completion handler is called with an Error object if any.
    public static func loginUser(email: String?, password: String?, completion: @escaping (Error?) -> Void ) {
        guard let email = email, !email.isEmpty, let password = password, !password.isEmpty else {
            let error = NSError(domain: "Auth Error", code: 400, userInfo: [NSLocalizedDescriptionKey: "Email and password fields cannot be empty"])
            completion(error)
            return
        }
        
        Auth.auth().signIn(withEmail: email, password: password) { (authResult, error) in
            completion(error)
        }
    }

    
    // Static method to update the current user's document with the provided key-value pairs.
    // It verifies if there is a logged-in user and if not, prints an error and calls the completion with `false`.
    // If an error occurs during the update, it is printed and the completion handler is called with `false`.
    // On a successful update, the completion handler is called with `true`.
    public static func updateUser(_ updateDoc: [String: Any], completion: @escaping (Bool) -> Void) {
        guard let currentUserUid = getCurrentUserUid() else {
            print("ERROR - updateUser: User not logged in")
            return completion(false)
        }
        
        db.document("users/\(currentUserUid)").updateData(updateDoc) { err in
            if let err = err {
                print("ERROR - updateUser: \(err.localizedDescription)")
                completion(false)
            } else {
                completion(true)
            }
        }
    }

    // Static method to update the current blueprint document with new data.
    // It first attempts to retrieve the blueprint ID from UserDefaults and if not found, prints an error and completes with `false`.
    // An error during the update is logged, and the completion is called with the result of the update operation.
    public static func updateBlueprint(_ updateDoc: [String: Any], completion: @escaping (Bool) -> Void) {
        guard let blueprintId = UserDefaults.standard.string(forKey: "BlueprintSettingsID") else {
            print("ERROR - updateBlueprint: Blueprint ID not found")
            return completion(false)
        }
        
        db.document("blueprints/\(blueprintId)").updateData(updateDoc) { err in
            if let err = err {
                print("ERROR - updateBlueprint: \(err.localizedDescription)")
                completion(false)
            } else {
                completion(true)
            }
        }
    }

    public static func addConversationLog(blueprintID: String, log: ConversationLog, completion: ((Bool) -> Void)? = nil) {
        let docRef = db.collection("blueprints").document(blueprintID)
        docRef.updateData([
            "conversationLogs": FieldValue.arrayUnion([log.toDictionary()])
        ]) { error in
            if let error = error {
                print("ERROR - addConversationLog: \(error.localizedDescription)")
                completion?(false)
            } else {
                completion?(true)
            }
        }
    }


    public struct TranscriptMemory {
        public let transcriptId: String
        public let sessionId: String
        public let blueprintId: String
        public let userId: String
        public let startedAt: Date?
        public let endedAt: Date?
        public let transcript: String

        init(
            transcriptId: String,
            sessionId: String,
            blueprintId: String,
            userId: String,
            startedAt: Date?,
            endedAt: Date?,
            transcript: String
        ) {
            self.transcriptId = transcriptId
            self.sessionId = sessionId
            self.blueprintId = blueprintId
            self.userId = userId
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.transcript = transcript
        }
    }

    private static func joinedTranscriptMessages(from documents: [QueryDocumentSnapshot]) -> String {
        documents.compactMap { doc -> String? in
            let payload = doc.data()
            guard let role = payload["role"] as? String,
                  let text = payload["text"] as? String else {
                return nil
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return "\(role.capitalized): \(trimmed)"
        }.joined(separator: "\n")
    }

    public static func startTranscript(
        blueprintId: String,
        sessionId: String,
        userId: String,
        completion: @escaping (String?) -> Void
    ) {
        let trimmedSessionId = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedSessionId: String
        if trimmedSessionId.isEmpty {
            resolvedSessionId = UserDefaults.standard.string(forKey: "currentSessionId") ?? UUID().uuidString
        } else {
            resolvedSessionId = trimmedSessionId
        }

        let transcripts = db.collection("transcripts")
        let transcriptRef = transcripts.document()

        let data: [String: Any] = [
            "sessionId": resolvedSessionId,
            "userId": userId,
            "blueprintId": blueprintId,
            "startedAt": FieldValue.serverTimestamp(),
            "finalTranscript": ""
        ]

        transcriptRef.setData(data) { error in
            if let error = error {
                print("ERROR - startTranscript: \(error.localizedDescription)")
                completion(nil)
            } else {
                completion(transcriptRef.documentID)
            }
        }
    }


    public static func addTranscriptMessage(transcriptId: String, message: TranscriptMessage, completion: ((Error?) -> Void)? = nil) {
        var data: [String: Any] = [
            "role": message.role,
            "text": message.text,
            "index": message.index,
            "timestamp": FieldValue.serverTimestamp()
        ]

        if let timestamp = message.timestamp {
            data["clientTimestamp"] = Timestamp(date: timestamp)
        }
        db.collection("transcripts").document(transcriptId).collection("messages").addDocument(data: data) { error in
                    completion?(error)
        }
    }

    public static func endTranscript(transcriptId: String, finalText: String?) {
        var updatePayload: [String: Any] = [
            "endedAt": FieldValue.serverTimestamp()
        ]

        if let finalText, !finalText.isEmpty {
            updatePayload["finalTranscript"] = finalText
        }

        db.collection("transcripts").document(transcriptId).updateData(updatePayload)
    }

    public static func fetchTranscriptMemories(
        blueprintId: String,
        userId: String,
        limit: Int = 5,
        completion: @escaping ([TranscriptMemory]) -> Void
    ) {
        db.collection("transcripts")
            .whereField("blueprintId", isEqualTo: blueprintId)
            .whereField("userId", isEqualTo: userId)
            .order(by: "startedAt", descending: true)
            .limit(to: limit)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("ERROR - fetchTranscriptMemories: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        completion([])
                    }
                    return
                }

                guard let documents = snapshot?.documents, !documents.isEmpty else {
                    DispatchQueue.main.async {
                        completion([])
                    }
                    return
                }

                let lock = NSLock()
                var memories: [TranscriptMemory] = []
                let group = DispatchGroup()

                for document in documents {
                    let data = document.data()
                    let finalText = (data["finalTranscript"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let resolvedSessionId = (data["sessionId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let resolvedBlueprintId = (data["blueprintId"] as? String) ?? blueprintId
                    let resolvedUserId = (data["userId"] as? String) ?? userId
                    let startedAt = (data["startedAt"] as? Timestamp)?.dateValue()
                    let endedAt = (data["endedAt"] as? Timestamp)?.dateValue()

                    let makeMemory: (String) -> TranscriptMemory = { transcript in
                        TranscriptMemory(
                            transcriptId: document.documentID,
                            sessionId: resolvedSessionId,
                            blueprintId: resolvedBlueprintId,
                            userId: resolvedUserId,
                            startedAt: startedAt,
                            endedAt: endedAt,
                            transcript: transcript
                        )
                    }

                    if !finalText.isEmpty {
                        let memory = makeMemory(finalText)
                        lock.lock()
                        memories.append(memory)
                        lock.unlock()
                    } else {
                        group.enter()
                        document.reference.collection("messages")
                            .order(by: "index")
                            .getDocuments { messagesSnapshot, messagesError in
                                defer { group.leave() }

                                if let messagesError = messagesError {
                                    print("ERROR - fetchTranscriptMemories(messages): \(messagesError.localizedDescription)")
                                    return
                                }

                                guard let messageDocs = messagesSnapshot?.documents, !messageDocs.isEmpty else {
                                    return
                                }

                                let joined = joinedTranscriptMessages(from: messageDocs)
                                let trimmed = joined.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !trimmed.isEmpty else { return }

                                let memory = makeMemory(trimmed)
                                lock.lock()
                                memories.append(memory)
                                lock.unlock()
                            }
                    }
                }

                group.notify(queue: .global(qos: .userInitiated)) {
                    lock.lock()
                    let sorted = memories.sorted { lhs, rhs in
                        let lhsDate = lhs.startedAt ?? lhs.endedAt ?? .distantPast
                        let rhsDate = rhs.startedAt ?? rhs.endedAt ?? .distantPast
                        return lhsDate > rhsDate
                    }
                    lock.unlock()

                    DispatchQueue.main.async {
                        completion(sorted)
                    }
                }
            }
    }

    public static func fetchLatestTranscript(
        blueprintId: String,
        userId: String,
        completion: @escaping (String?) -> Void
    ) {
        fetchTranscriptMemories(blueprintId: blueprintId, userId: userId, limit: 1) { memories in
            completion(memories.first?.transcript)
        }
    }

    // Static method to update the Firebase Cloud Messaging (FCM) token of a user's document.
    // An error during updating the FCM token is printed and the completion is called with `false`.
    // If the update is successful, the completion handler is called with `true`.
    public static func updateFCMToken(userUid: String, fcmToken: String, completion: @escaping (Bool) -> Void) {
        let userDoc = db.collection("users").document(userUid)
        userDoc.updateData(["fcmToken" : fcmToken]) { err in
            if err != nil {
                print("ERROR - updateFCMToken: \(err!.localizedDescription)")
                return completion(false)
            }
            completion(true)
        }
    }
//
    // Static method to update the profile picture reference of the current user.
    // It checks for the current user ID and if not available, it calls completion with `false`.
    // An error during the update is printed and the completion handler is called with `false`.
    // On successful update, the completion handler is called with `true`.
    public static func updateProPic(withProPicRef proPicRef: String, completion: @escaping (Bool) -> Void ) {
        guard let currentUserUid = FirebaseAuthHelper.getCurrentUserUid() else {
            return completion(false)
        }
        let currentUserDoc = db.collection("users").document(currentUserUid)

        currentUserDoc.updateData(["proPicRef": proPicRef]) { err in
            if let err = err {
                print("Error - updateProPic", err.localizedDescription)
                completion(false)
            } else {
                completion(true)
            }

        }
    }
    
    // Static method to delete the current user's account.
    // It checks if the user is logged in before attempting to delete the user's document.
    // If there's an error during the deletion, it is printed and the completion is called with `false`.
    // Otherwise, it proceeds to delete the user from FirebaseAuth and calls completion with the result.
    public static func deleteAccount(completion: @escaping (Bool) -> Void) {
        guard let currentUserUid = Auth.auth().currentUser?.uid else {
            print("ERROR - deleteAccount: User not logged in")
            return completion(false)
        }
        
        db.collection("users").document(currentUserUid).delete { err in
            if let err = err {
                print("ERROR - deleteAccount \(currentUserUid): \(err.localizedDescription)")
                completion(false)
                return
            }
            
            FirebaseAuthHelper.deleteUser(completion: completion)
        }
    }

    

    // MARK: - Wearables assistance logging

    public static func createServiceRequest(
        blueprintId: String,
        sessionId: String,
        userId: String,
        zone: String?,
        intent: String,
        details: String?,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        var payload: [String: Any] = [
            "blueprintId": blueprintId,
            "sessionId": sessionId,
            "userId": userId,
            "intent": intent,
            "status": "pending",
            "createdAt": FieldValue.serverTimestamp()
        ]
        if let zone, !zone.isEmpty { payload["zone"] = zone }
        if let details, !details.isEmpty { payload["details"] = details }

        let docRef = db.collection("serviceRequests").document()
        docRef.setData(payload) { error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                } else {
                    completion(.success(docRef.documentID))
                }
            }
        }
    }

    public static func logIncident(
        blueprintId: String,
        sessionId: String,
        userId: String,
        zone: String?,
        category: String,
        summary: String,
        severity: String?,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        var payload: [String: Any] = [
            "blueprintId": blueprintId,
            "sessionId": sessionId,
            "userId": userId,
            "category": category,
            "summary": summary,
            "createdAt": FieldValue.serverTimestamp()
        ]
        if let zone, !zone.isEmpty { payload["zone"] = zone }
        if let severity, !severity.isEmpty { payload["severity"] = severity }

        let docRef = db.collection("incidentReports").document()
        docRef.setData(payload) { error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                } else {
                    completion(.success(docRef.documentID))
                }
            }
        }
    }

    public static func createQueueUpdate(
        blueprintId: String,
        sessionId: String,
        userId: String,
        channel: String,
        message: String,
        etaMinutes: Double?,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        var payload: [String: Any] = [
            "blueprintId": blueprintId,
            "sessionId": sessionId,
            "userId": userId,
            "channel": channel,
            "message": message,
            "createdAt": FieldValue.serverTimestamp()
        ]
        if let etaMinutes { payload["etaMinutes"] = etaMinutes }

        let docRef = db.collection("queueUpdates").document()
        docRef.setData(payload) { error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                } else {
                    completion(.success(docRef.documentID))
                }
            }
        }
    }

    public static func recordSopStep(
        blueprintId: String,
        sessionId: String,
        userId: String,
        checklist: String,
        step: String,
        status: String,
        notes: String?,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        var payload: [String: Any] = [
            "blueprintId": blueprintId,
            "sessionId": sessionId,
            "userId": userId,
            "checklist": checklist,
            "step": step,
            "status": status,
            "recordedAt": FieldValue.serverTimestamp()
        ]
        if let notes, !notes.isEmpty { payload["notes"] = notes }

        let docRef = db.collection("sopRuns").document()
        docRef.setData(payload) { error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                } else {
                    completion(.success(docRef.documentID))
                }
            }
        }
    }





  }
//
