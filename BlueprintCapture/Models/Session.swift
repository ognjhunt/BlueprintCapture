//
//  Session.swift
//  BlueprintVisionInternal
//
//  Created by Nijel A. Hunt on 10/8/23.
//

import Foundation
import UIKit
import FirebaseFirestore

public class Session {
    
    var id             : String = ""
    var userId      : String = ""
    var startTime            = Date()
    var endTime            = Date()
    var duration            : NSNumber = 0
    // New properties for enhanced context awareness
       var connectedBlueprintId: String?
       var roomsVisited: [String: TimeInterval] = [:]  // Room ID : Time spent
    var startLocation: (latitude: Double, longitude: Double)?

       var lastKnownLocation: (latitude: Double, longitude: Double)?
       var deviceType: String?
       var appVersion: String?
       
       // User behavior tracking
       var actionsPerformed: [String: Int] = [:]  // Action type : Count
       var contentInteractions: [String: Int] = [:]  // Content ID : Interaction count
       
       // Time-based data
       var timeOfDay: Int?  // Hour of the day (0-23)
       var dayOfWeek: Int?  // Day of the week (1-7)
       
       // Environmental data
       var ambientLightLevel: Float?
       var noiseLevel: Float?
       
       // User state
       var stepCount: Int?
       var lastMealTime: Date?
       var sleepDuration: TimeInterval?
       
       // External data integration
       var weatherCondition: String?
       var calendarEvents: [String]?  // Event IDs for the day
    
    init(_ userFirDoc: [String: Any]) {
            // Existing initializations
            if let id = userFirDoc["id"] as? String {
                self.id = id
            }
            
            if let userId = userFirDoc["userId"] as? String {
                self.userId = userId
            }
            
            if let timestamp = userFirDoc["startTime"] as? Timestamp {
                self.startTime = timestamp.dateValue()
            }
            
            if let timestamp = userFirDoc["endTime"] as? Timestamp {
                self.endTime = timestamp.dateValue()
            }
            
            if let duration = userFirDoc["duration"] as? NSNumber {
                self.duration = duration
            }
            
            // New initializations
            if let connectedBlueprintId = userFirDoc["connectedBlueprintId"] as? String {
                self.connectedBlueprintId = connectedBlueprintId
            }
            
            if let roomsVisited = userFirDoc["roomsVisited"] as? [String: TimeInterval] {
                self.roomsVisited = roomsVisited
            }
        
        if let startLocation = userFirDoc["startLocation"] as? [String: Double],
           let latitude = startLocation["latitude"],
           let longitude = startLocation["longitude"] {
            self.startLocation = (latitude, longitude)
        }
            
            if let location = userFirDoc["lastKnownLocation"] as? [String: Double],
               let latitude = location["latitude"],
               let longitude = location["longitude"] {
                self.lastKnownLocation = (latitude, longitude)
            }
            
            if let deviceType = userFirDoc["deviceType"] as? String {
                self.deviceType = deviceType
            }
            
            if let appVersion = userFirDoc["appVersion"] as? String {
                self.appVersion = appVersion
            }
            
            if let actionsPerformed = userFirDoc["actionsPerformed"] as? [String: Int] {
                self.actionsPerformed = actionsPerformed
            }
            
            if let contentInteractions = userFirDoc["contentInteractions"] as? [String: Int] {
                self.contentInteractions = contentInteractions
            }
            
            if let timeOfDay = userFirDoc["timeOfDay"] as? Int {
                self.timeOfDay = timeOfDay
            }
            
            if let dayOfWeek = userFirDoc["dayOfWeek"] as? Int {
                self.dayOfWeek = dayOfWeek
            }
            
            if let ambientLightLevel = userFirDoc["ambientLightLevel"] as? Float {
                self.ambientLightLevel = ambientLightLevel
            }
            
            if let noiseLevel = userFirDoc["noiseLevel"] as? Float {
                self.noiseLevel = noiseLevel
            }
            
            if let stepCount = userFirDoc["stepCount"] as? Int {
                self.stepCount = stepCount
            }
            
            if let lastMealTimestamp = userFirDoc["lastMealTime"] as? Timestamp {
                self.lastMealTime = lastMealTimestamp.dateValue()
            }
            
            if let sleepDuration = userFirDoc["sleepDuration"] as? TimeInterval {
                self.sleepDuration = sleepDuration
            }
            
            if let weatherCondition = userFirDoc["weatherCondition"] as? String {
                self.weatherCondition = weatherCondition
            }
            
            if let calendarEvents = userFirDoc["calendarEvents"] as? [String] {
                self.calendarEvents = calendarEvents
            }
        }
    
 }
