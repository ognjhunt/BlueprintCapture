//
//  User.swift
//  Accel
//
//  Created by Nijel Hunt on 6/21/19.
//  Copyright © 2019 Nijel Hunt. All rights reserved.
//

import Foundation
import FirebaseFirestore
import UIKit

public class User {
    private(set) var uid          : String = ""
    private(set) var tempID          : String = ""
    private(set) var name         : String = ""
    private(set) var email        : String = ""
    private(set) var username     : String = ""
    private(set) var planType     : String = ""
    private(set) var deviceToken     : String = ""
    private(set) var referralCode     : String = ""
    private(set) var currentConnectedNetworkID     : String = ""
    private(set) var numSessions     : Int = 0
  //  private(set) var numBlueprintSessions     : Int = 0
    private(set) var uploadedContentCount     : Int = 0
    private(set) var collectedContentCount     : Int = 0
    private(set) var connectedBlueprintIDs     = [String]()
    private(set) var collectedObjectIDs     = [String]()
    private(set) var collectedPortalIDs     = [String]()
    private(set) var uploadedFileIDs     = [String]()
    private(set) var createdPhotoIDs     = [String]()
    private(set) var createdNoteIDs     = [String]()
    private(set) var createdReportIDs     = [String]()
    private(set) var createdSuggestionIDs     = [String]()
    private(set) var createdContentIDs     = [String]()
    private(set) var credits     : Int?
    private(set) var finishedOnboarding     : Bool?
    private(set) var hasEnteredNotes     : Bool?
    private(set) var hasEnteredInventory     : Bool?
    private(set) var hasEnteredCameraRoll     : Bool?
    private(set) var amountEarned     : Double?
    private(set) var blockedUserIDs    = [String]()
    // Followers and Following
    private(set) var followers    = [String]()
    private(set) var following    = [String]()
    
    var createdDate = Date()
    
    var lastSessionDate       = Date()

    
    private(set) var latitude          : Double?// = ""
    private(set) var longitude          : Double?
    private(set) var altitude          : Double?
    
    private(set) var historyConnectedBlueprintIDs    = [String: Timestamp]()
    private(set) var createdBlueprintIDs    = [String]()
    
    private(set) var likedAnchorIDs    = [String]()
    
    // Subscriptions
    private(set) var subscriptions  = [String]()
    private(set) var subscribers    = [String]()
    
    // Profile picture
    private(set) var profileImageUrl   : String?
    
    // Asset
    private(set) var assetUids    = [String]()
    private(set) var ownedAssets = [String]()
    
    var usageTime: TimeInterval = 0

    // New properties
        private(set) var modelInteractions: [String: Int] = [:]
        private(set) var blueprintInteractions: [String: Int] = [:]
        private(set) var portalInteractions: [String: Int] = [:]
        private(set) var categoryPreferences: [String: Int] = [:]
        
        private(set) var averageSessionDuration: Double = 0
        private(set) var peakUsageHours: [Int] = []
        private(set) var lastLoginDate: Date = Date()
        
        private(set) var featureUsageCount: [String: Int] = [:]
        private(set) var mostUsedFeatures: [String] = []
        
        private(set) var creationFrequency: [String: Double] = [:]
        private(set) var contentEditFrequency: [String: Double] = [:]
        
        private(set) var collaborationScore: Int = 0
        private(set) var sharedContentCount: Int = 0
        
        private(set) var preferredModelScales: [Double] = []
        private(set) var preferredRoomTypes: [String] = []
        private(set) var preferredColors: [String] = []
        
        private(set) var dailyActiveStreak: Int = 0
        private(set) var weeklyEngagementScore: Double = 0
        
        private(set) var completedTutorials: [String] = []
        private(set) var skillLevels: [String: Int] = [:]
        
        private(set) var mostFrequentLocation: String = ""
        private(set) var deviceTypes: [String] = []
        
        private(set) var providedRatings: [String: Double] = [:]
        private(set) var feedbackSentiment: [String: String] = [:]
        
        private(set) var customizationPreferences: [String: Any] = [:]
        private(set) var notificationPreferences: [String: Bool] = [:]
        
        private(set) var creativityScore: Double = 0
        private(set) var explorationIndex: Double = 0
        
        private(set) var connectedPlatforms: [String] = []
        private(set) var importedContentSources: [String] = []
//    // groups
//    private(set) var groups       = [[String:Any]]()
    
    //MARK: --- Methods ---
    init(_ userFirDoc: [String:Any]) {
        
        // uid
        if let uid = userFirDoc["uid"] as? String {
            self.uid = uid
        }
        
        if let tempID = userFirDoc["tempID"] as? String {
            self.tempID = tempID
        }
        
        if let finishedOnboarding = userFirDoc["finishedOnboarding"] as? Bool {
            self.finishedOnboarding = finishedOnboarding
        }
        
        if let hasEnteredNotes = userFirDoc["hasEnteredNotes"] as? Bool {
            self.hasEnteredNotes = hasEnteredNotes
        }
        
        if let hasEnteredCameraRoll = userFirDoc["hasEnteredCameraRoll"] as? Bool {
            self.hasEnteredCameraRoll = hasEnteredCameraRoll
        }
        
        if let hasEnteredInventory = userFirDoc["hasEnteredInventory"] as? Bool {
            self.hasEnteredInventory = hasEnteredInventory
        }
        
        
        // name
        if let name = userFirDoc["name"] as? String {
            self.name = name
        }
        
        // emailStr
        if let email = userFirDoc["email"] as? String {
            self.email = email
        }
        
        //usernameStr
        if let username = userFirDoc["username"] as? String {
            self.username = username
        }
        
        if let planType = userFirDoc["planType"] as? String {
            self.planType = planType
        }
        
        if let deviceToken = userFirDoc["deviceToken"] as? String {
            self.deviceToken = deviceToken
        }
        
        if let referralCode = userFirDoc["referralCode"] as? String {
            self.referralCode = referralCode
        }
        
        if let credits = userFirDoc["credits"] as? Int {
            self.credits = credits
        }
        
        if let usageTime = userFirDoc["usageTime"] as? TimeInterval {
            self.usageTime = usageTime
        }
        
        if let timestamp = userFirDoc["createdDate"] as? Timestamp {
                self.createdDate = timestamp.dateValue()
            }
        
        if let timestamp = userFirDoc["lastSessionDate"] as? Timestamp {
                self.lastSessionDate = timestamp.dateValue()
            }
        
        if let amountEarned = userFirDoc["amountEarned"] as? Double {
            self.amountEarned = amountEarned
        }
        
        if let numSessions = userFirDoc["numSessions"] as? Int {
            self.numSessions = numSessions
        }
        
//        if let numBlueprintSessions = userFirDoc["numBlueprintSessions"] as? Int {
//            self.numBlueprintSessions = numBlueprintSessions
//        }
        
        if let uploadedContentCount = userFirDoc["uploadedContentCount"] as? Int {
            self.uploadedContentCount = uploadedContentCount
        }
        
        if let collectedContentCount = userFirDoc["collectedContentCount"] as? Int {
            self.collectedContentCount = collectedContentCount
        }
        
        if let blockedUserIDs = userFirDoc["blockedUserIDs"] as? [String] {
            self.blockedUserIDs = blockedUserIDs
        }
        
        if let connectedBlueprintIDs = userFirDoc["connectedBlueprintIDs"] as? [String] {
            self.connectedBlueprintIDs = connectedBlueprintIDs
        }
        
        if let collectedObjectIDs = userFirDoc["collectedObjectIDs"] as? [String] {
            self.collectedObjectIDs = collectedObjectIDs
        }
        
        if let collectedPortalIDs = userFirDoc["collectedPortalIDs"] as? [String] {
            self.collectedPortalIDs = collectedPortalIDs
        }
        
        if let uploadedFileIDs = userFirDoc["uploadedFileIDs"] as? [String] {
            self.uploadedFileIDs = uploadedFileIDs
        }
        
        if let createdNoteIDs = userFirDoc["createdNoteIDs"] as? [String] {
            self.createdNoteIDs = createdNoteIDs
        }
        
        if let createdPhotoIDs = userFirDoc["createdPhotoIDs"] as? [String] {
            self.createdPhotoIDs = createdPhotoIDs
        }
        
        if let createdReportIDs = userFirDoc["createdReportIDs"] as? [String] {
            self.createdReportIDs = createdReportIDs
        }
        
        if let createdSuggestionIDs = userFirDoc["createdSuggestionIDs"] as? [String] {
            self.createdSuggestionIDs = createdSuggestionIDs
        }
        
        if let createdContentIDs = userFirDoc["createdContentIDs"] as? [String] {
            self.createdContentIDs = createdContentIDs
        }
        
        if let latitude = userFirDoc["latitude"] as? Double {
            self.latitude = latitude
        }
        
        if let longitude = userFirDoc["longitude"] as? Double {
            self.longitude = longitude
        }
        
        if let altitude = userFirDoc["altitude"] as? Double {
            self.altitude = altitude
        }

//        // bioStr
//        if let bioStr = userFirDoc["bio"] as? String {
//            self.bioStr = bioStr
//        }
//
//        // locationStr
//        if let locationStr = userFirDoc["location"] as? String {
//            self.locationStr = locationStr
//        }
        
//        // urlStr
//        if let urlStr = userFirDoc["urlStr"] as? String {
//            self.urlStr = urlStr
//        }
        
        // --------------------------------------------------------
    
        // followers
        if let followers = userFirDoc["followers"] as? [String] {
            self.followers = followers
        }
        
        // following
        if let following = userFirDoc["following"] as? [String] {
            self.following = following
        }
        
        if let likedAnchorIDs = userFirDoc["likedAnchorIDs"] as? [String] {
            self.likedAnchorIDs = likedAnchorIDs
        }
        
        if let historyConnectedBlueprintIDs = userFirDoc["historyConnectedBlueprintIDs"] as? [String: Timestamp] {
            self.historyConnectedBlueprintIDs = historyConnectedBlueprintIDs
        }
        
        if let currentConnectedNetworkID = userFirDoc["currentConnectedNetworkID"] as? String {
            self.currentConnectedNetworkID = currentConnectedNetworkID
        }
        
        // following
        if let createdBlueprintIDs = userFirDoc["createdBlueprintIDs"] as? [String] {
            self.createdBlueprintIDs = createdBlueprintIDs
        }
        
        // ---------------------------------------------------------
 
        self.profileImageUrl = userFirDoc["profileImageUrl"] as? String
        
        // ---------------------------------------------------------
        
        // Assets
        if let assetUids = userFirDoc["assetUids"] as? [String] {
            self.assetUids = assetUids
        }
        
        if let ownedAssets = userFirDoc["ownedAssets"] as? [String] {
            self.ownedAssets = ownedAssets
        }
        
        
        // subscriptions
        if let subscriptions = userFirDoc["subscriptions"] as? [String] {
            self.subscriptions = subscriptions
        }
        
        if let subscribers = userFirDoc["subscribers"] as? [String] {
            self.subscribers = subscribers
        }
        
        // New initializations
        // New initializations
        if let modelInteractions = userFirDoc["modelInteractions"] as? [String: Int] {
            self.modelInteractions = modelInteractions
        }

        if let blueprintInteractions = userFirDoc["blueprintInteractions"] as? [String: Int] {
            self.blueprintInteractions = blueprintInteractions
        }

        if let portalInteractions = userFirDoc["portalInteractions"] as? [String: Int] {
            self.portalInteractions = portalInteractions
        }

        if let categoryPreferences = userFirDoc["categoryPreferences"] as? [String: Int] {
            self.categoryPreferences = categoryPreferences
        }

        if let averageSessionDuration = userFirDoc["averageSessionDuration"] as? Double {
            self.averageSessionDuration = averageSessionDuration
        }

        if let peakUsageHours = userFirDoc["peakUsageHours"] as? [Int] {
            self.peakUsageHours = peakUsageHours
        }

        if let lastLoginTimestamp = userFirDoc["lastLoginDate"] as? Timestamp {
            self.lastLoginDate = lastLoginTimestamp.dateValue()
        }

        if let featureUsageCount = userFirDoc["featureUsageCount"] as? [String: Int] {
            self.featureUsageCount = featureUsageCount
        }

        if let mostUsedFeatures = userFirDoc["mostUsedFeatures"] as? [String] {
            self.mostUsedFeatures = mostUsedFeatures
        }

        if let creationFrequency = userFirDoc["creationFrequency"] as? [String: Double] {
            self.creationFrequency = creationFrequency
        }

        if let contentEditFrequency = userFirDoc["contentEditFrequency"] as? [String: Double] {
            self.contentEditFrequency = contentEditFrequency
        }

        if let collaborationScore = userFirDoc["collaborationScore"] as? Int {
            self.collaborationScore = collaborationScore
        }

        if let sharedContentCount = userFirDoc["sharedContentCount"] as? Int {
            self.sharedContentCount = sharedContentCount
        }

        if let preferredModelScales = userFirDoc["preferredModelScales"] as? [Double] {
            self.preferredModelScales = preferredModelScales
        }

        if let preferredRoomTypes = userFirDoc["preferredRoomTypes"] as? [String] {
            self.preferredRoomTypes = preferredRoomTypes
        }

        if let preferredColors = userFirDoc["preferredColors"] as? [String] {
            self.preferredColors = preferredColors
        }

        if let dailyActiveStreak = userFirDoc["dailyActiveStreak"] as? Int {
            self.dailyActiveStreak = dailyActiveStreak
        }

        if let weeklyEngagementScore = userFirDoc["weeklyEngagementScore"] as? Double {
            self.weeklyEngagementScore = weeklyEngagementScore
        }

        if let completedTutorials = userFirDoc["completedTutorials"] as? [String] {
            self.completedTutorials = completedTutorials
        }

        if let skillLevels = userFirDoc["skillLevels"] as? [String: Int] {
            self.skillLevels = skillLevels
        }

        if let mostFrequentLocation = userFirDoc["mostFrequentLocation"] as? String {
            self.mostFrequentLocation = mostFrequentLocation
        }

        if let deviceTypes = userFirDoc["deviceTypes"] as? [String] {
            self.deviceTypes = deviceTypes
        }

        if let providedRatings = userFirDoc["providedRatings"] as? [String: Double] {
            self.providedRatings = providedRatings
        }

        if let feedbackSentiment = userFirDoc["feedbackSentiment"] as? [String: String] {
            self.feedbackSentiment = feedbackSentiment
        }

        if let customizationPreferences = userFirDoc["customizationPreferences"] as? [String: Any] {
            self.customizationPreferences = customizationPreferences
        }

        if let notificationPreferences = userFirDoc["notificationPreferences"] as? [String: Bool] {
            self.notificationPreferences = notificationPreferences
        }

        if let creativityScore = userFirDoc["creativityScore"] as? Double {
            self.creativityScore = creativityScore
        }

        if let explorationIndex = userFirDoc["explorationIndex"] as? Double {
            self.explorationIndex = explorationIndex
        }

        if let connectedPlatforms = userFirDoc["connectedPlatforms"] as? [String] {
            self.connectedPlatforms = connectedPlatforms
        }

        if let importedContentSources = userFirDoc["importedContentSources"] as? [String] {
            self.importedContentSources = importedContentSources
        }
        
    }
}
