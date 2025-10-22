//
//  Model.swift
//  DecorateYourRoom
//
//  Created by Nijel Hunt on 10/13/21.
//  Copyright © 2021 Placenote. All rights reserved.
//
import Foundation
import UIKit
import FirebaseFirestore
import simd

public enum BlueprintWelcomePersona: String, CaseIterable {
    case targetCustomer
    case casualVisitor
    case vipMember
    case staffMember
    case partnerPress

    private static let userDefaultsKey = "BlueprintVisitorPersona"

    public static func resolve(
        for blueprint: Blueprint?,
        defaults: UserDefaults = .standard
    ) -> BlueprintWelcomePersona {
        if let stored = defaults.string(forKey: userDefaultsKey) {
            let normalized = stored.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if let match = BlueprintWelcomePersona.allCases.first(where: { $0.rawValue.lowercased() == normalized }) {
                return match
            }
        }

        if let audience = blueprint?.onboardingData?.audienceType {
            let normalizedAudience = audience.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalizedAudience.contains("vip") || normalizedAudience.contains("premium") || normalizedAudience.contains("loyal") {
                return .vipMember
            }
            if normalizedAudience.contains("staff") || normalizedAudience.contains("employee") || normalizedAudience.contains("team") {
                return .staffMember
            }
            if normalizedAudience.contains("press") || normalizedAudience.contains("media") || normalizedAudience.contains("partner") {
                return .partnerPress
            }
            if normalizedAudience.contains("visitor") || normalizedAudience.contains("guest") || normalizedAudience.contains("tourist") {
                return .casualVisitor
            }
            if normalizedAudience.contains("customer") || normalizedAudience.contains("shopper") {
                return .targetCustomer
            }
        }

        return .targetCustomer
    }
}

public struct Coordinate3D: Codable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public init?(dictionary: [String: Double]) {
        guard let x = dictionary["x"],
              let y = dictionary["y"],
              let z = dictionary["z"] else {
            return nil
        }
        self.x = x
        self.y = y
        self.z = z
    }
}

public struct MarkedArea: Codable {
    public var id: String
    public var name: String
    public var color: String
    public var min: Coordinate3D
    public var max: Coordinate3D

    public init(id: String, name: String, color: String, min: Coordinate3D, max: Coordinate3D) {
        self.id = id
        self.name = name
        self.color = color
        self.min = min
        self.max = max
    }

    public init?(dictionary: [String: Any]) {
        guard let id = dictionary["id"] as? String,
              let name = dictionary["name"] as? String,
              let color = dictionary["color"] as? String,
              let minDict = dictionary["min"] as? [String: Double],
              let maxDict = dictionary["max"] as? [String: Double],
              let minCoord = Coordinate3D(dictionary: minDict),
              let maxCoord = Coordinate3D(dictionary: maxDict) else {
            return nil
        }
        self.id = id
        self.name = name
        self.color = color
        self.min = minCoord
        self.max = maxCoord
    }
}


public struct BlueprintSpatialAnchor: Codable, Identifiable {
    public let id: String
    public let name: String
    public let centroid: Coordinate3D?
    public let extent: Coordinate3D?
    public let radiusMeters: Double?
    public let tags: [String]
    public let summary: String?
    public let category: String?
    public let confidence: Double?
    public let metadata: [String: String]

    public init(
        id: String,
        name: String,
        centroid: Coordinate3D?,
        extent: Coordinate3D?,
        radiusMeters: Double?,
        tags: [String],
        summary: String?,
        category: String?,
        confidence: Double?,
        metadata: [String: String]
    ) {
        self.id = id
        self.name = name
        self.centroid = centroid
        self.extent = extent
        self.radiusMeters = radiusMeters
        self.tags = tags
        self.summary = summary
        self.category = category
        self.confidence = confidence
        self.metadata = metadata
    }

    public init?(id: String, data: [String: Any]) {
        func parseCoordinate(_ value: Any?) -> Coordinate3D? {
            if let dict = value as? [String: Double] {
                return Coordinate3D(dictionary: dict)
            }
            if let dict = value as? [String: NSNumber] {
                let converted = dict.reduce(into: [String: Double]()) { result, pair in
                    result[pair.key] = pair.value.doubleValue
                }
                return Coordinate3D(dictionary: converted)
            }
            return nil
        }

        func parseMetadata(_ value: Any?) -> [String: String] {
            guard let raw = value else { return [:] }
            if let map = raw as? [String: String] {
                return map
            }
            if let map = raw as? [String: Any] {
                var converted: [String: String] = [:]
                for (key, value) in map {
                    switch value {
                    case let string as String:
                        converted[key] = string
                    case let number as NSNumber:
                        converted[key] = number.stringValue
                    default:
                        converted[key] = String(describing: value)
                    }
                }
                return converted
            }
            return [:]
        }

        guard let rawName = data["name"] as? String ?? data["label"] as? String else {
            return nil
        }

        let cleanedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty else { return nil }

        self.id = id
        self.name = cleanedName
        self.centroid = parseCoordinate(data["centroid"] ?? data["center"] ?? data["origin"])
        self.extent = parseCoordinate(data["extent"] ?? data["dimensions"] ?? data["size"])

        if let radius = data["radiusMeters"] as? Double {
            self.radiusMeters = radius
        } else if let radius = data["radius"] as? Double {
            self.radiusMeters = radius
        } else if let radiusNumber = data["radius"] as? NSNumber {
            self.radiusMeters = radiusNumber.doubleValue
        } else if let influence = data["influenceRadius"] as? Double {
            self.radiusMeters = influence
        } else {
            self.radiusMeters = nil
        }

        if let tags = data["tags"] as? [String] {
            self.tags = tags
        } else if let labels = data["labels"] as? [String] {
            self.tags = labels
        } else if let keywords = data["keywords"] as? [String] {
            self.tags = keywords
        } else {
            self.tags = []
        }

        if let summary = data["summary"] as? String ?? data["description"] as? String {
            let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
            self.summary = trimmed.isEmpty ? nil : trimmed
        } else {
            self.summary = nil
        }

        if let category = data["category"] as? String ?? data["type"] as? String {
            let trimmed = category.trimmingCharacters(in: .whitespacesAndNewlines)
            self.category = trimmed.isEmpty ? nil : trimmed
        } else {
            self.category = nil
        }

        if let confidence = data["confidence"] as? Double {
            self.confidence = confidence
        } else if let confidence = data["score"] as? Double {
            self.confidence = confidence
        } else if let number = data["confidence"] as? NSNumber {
            self.confidence = number.doubleValue
        } else {
            self.confidence = nil
        }

        self.metadata = parseMetadata(data["metadata"])
    }

    public var centroidVector: SIMD3<Double>? {
        guard let centroid else { return nil }
        return SIMD3<Double>(centroid.x, centroid.y, centroid.z)
    }

    public var extentVector: SIMD3<Double>? {
        guard let extent else { return nil }
        return SIMD3<Double>(extent.x, extent.y, extent.z)
    }
}


public struct BlueprintKnowledgeSource: Hashable {
    public let title: String
    public let url: String
    public let category: String?
    public let details: String?
    public let updatedOn: String?

    init?(dictionary: [String: Any]) {
        guard let rawTitle = dictionary["title"] as? String ?? dictionary["name"] as? String,
              let rawUrl = dictionary["url"] as? String ?? dictionary["link"] as? String else {
            return nil
        }

        let trimmedTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUrl = rawUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedUrl.isEmpty else { return nil }

        self.title = trimmedTitle
        self.url = trimmedUrl
        if let category = dictionary["category"] as? String ?? dictionary["type"] as? String {
            let trimmed = category.trimmingCharacters(in: .whitespacesAndNewlines)
            self.category = trimmed.isEmpty ? nil : trimmed
        } else {
            self.category = nil
        }

        if let description = dictionary["description"] as? String ?? dictionary["why_it_matters"] as? String {
            let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
            self.details = trimmed.isEmpty ? nil : trimmed
        } else {
            self.details = nil
        }

        if let updated = dictionary["updated_on"] as? String ?? dictionary["updatedOn"] as? String {
            let trimmed = updated.trimmingCharacters(in: .whitespacesAndNewlines)
            self.updatedOn = trimmed.isEmpty ? nil : trimmed
        } else {
            self.updatedOn = nil
        }
    }

    func instructionLine() -> String {
        var segments: [String] = [title]
        if let category, !category.isEmpty {
            segments.append("[\(category)]")
        }
        if let details, !details.isEmpty {
            segments.append(details)
        }
        segments.append(url)
        if let updatedOn, !updatedOn.isEmpty {
            segments.append("Updated: \(updatedOn)")
        }
        return segments.joined(separator: " — ")
    }
}

public struct BlueprintOperationalDetails {
    public let hours: String?
    public let pricing: String?
    public let contact: String?
    public let accessibility: String?
    public let parking: String?
    public let wifi: String?

    init?(dictionary: [String: Any]) {
        func clean(_ value: Any?) -> String? {
            guard let raw = value as? String else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        let hours = clean(dictionary["hours"]) ?? clean(dictionary["Hours"])
        let pricing = clean(dictionary["pricing"]) ?? clean(dictionary["Pricing"])
        let contact = clean(dictionary["contact"]) ?? clean(dictionary["Contact"])
        let accessibility = clean(dictionary["accessibility"]) ?? clean(dictionary["Accessibility"])
        let parking = clean(dictionary["parking"]) ?? clean(dictionary["Parking"])
        let wifi = clean(dictionary["wifi"]) ?? clean(dictionary["WiFi"]) ?? clean(dictionary["wi-fi"])

        if [hours, pricing, contact, accessibility, parking, wifi].allSatisfy({ $0 == nil }) {
            return nil
        }

        self.hours = hours
        self.pricing = pricing
        self.contact = contact
        self.accessibility = accessibility
        self.parking = parking
        self.wifi = wifi
    }

    func asLines() -> [String] {
        var lines: [String] = []
        if let hours { lines.append("Hours: \(hours)") }
        if let pricing { lines.append("Pricing: \(pricing)") }
        if let contact { lines.append("Contact: \(contact)") }
        if let accessibility { lines.append("Accessibility: \(accessibility)") }
        if let parking { lines.append("Parking/Transit: \(parking)") }
        if let wifi { lines.append("Wi-Fi: \(wifi)") }
        return lines
    }
}

public struct BlueprintKnowledgeIndex {
    public let chunkCount: Int?
    public let sourceCount: Int?
    public let lastIndexedAt: Date?

    init?(dictionary: [String: Any]) {
        func parseInt(_ value: Any?) -> Int? {
            if let intValue = value as? Int { return intValue }
            if let doubleValue = value as? Double { return Int(doubleValue) }
            if let stringValue = value as? String { return Int(stringValue) }
            return nil
        }

        let chunkCount = parseInt(dictionary["chunkCount"]) ?? parseInt(dictionary["chunks"])
        let sourceCount = parseInt(dictionary["sourceCount"]) ?? parseInt(dictionary["sources"])

        let timestamp: Date?
        if let ts = dictionary["lastIndexedAt"] as? Timestamp {
            timestamp = ts.dateValue()
        } else if let ts = dictionary["last_indexed_at"] as? Timestamp {
            timestamp = ts.dateValue()
        } else if let stringValue = dictionary["lastIndexedAt"] as? String,
                  let parsed = ISO8601DateFormatter().date(from: stringValue) {
            timestamp = parsed
        } else {
            timestamp = nil
        }

        if chunkCount == nil, sourceCount == nil, timestamp == nil {
            return nil
        }

        self.chunkCount = chunkCount
        self.sourceCount = sourceCount
        self.lastIndexedAt = timestamp
    }
}

public struct BlueprintToolHint {
    public let name: String
    public let whenToUse: String?
    public let metaCall: String?

    init?(dictionary: [String: Any]) {
        guard let rawName = dictionary["name"] as? String ?? dictionary["tool"] as? String else {
            return nil
        }
        let trimmedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }

        self.name = trimmedName

        if let when = dictionary["when_to_use"] as? String ?? dictionary["whenToUse"] as? String {
            let trimmed = when.trimmingCharacters(in: .whitespacesAndNewlines)
            self.whenToUse = trimmed.isEmpty ? nil : trimmed
        } else {
            self.whenToUse = nil
        }

        if let meta = dictionary["meta_call"] as? String ?? dictionary["metaCall"] as? String {
            let trimmed = meta.trimmingCharacters(in: .whitespacesAndNewlines)
            self.metaCall = trimmed.isEmpty ? nil : trimmed
        } else {
            self.metaCall = nil
        }
    }

    func instructionLine() -> String {
        var details: [String] = []
        if let whenToUse, !whenToUse.isEmpty {
            details.append(whenToUse)
        }
        if let metaCall, !metaCall.isEmpty {
            details.append(metaCall)
        }
        if details.isEmpty {
            return "Use \(name) when it advances the guest's request."
        }
        return "\(name): \(details.joined(separator: " — "))"
    }
}

public struct BlueprintKnowledgeChunk: Hashable, Identifiable {
    public let id: String
    public let title: String?
    public let url: String?
    public let category: String?
    public let text: String
    public let order: Int?
    public let score: Double?
    public let sourceId: String?
    public let heading: String?
    public let updatedAt: Date?

    init?(id: String, data: [String: Any]) {
        func parseInt(_ value: Any?) -> Int? {
            if let intValue = value as? Int { return intValue }
            if let doubleValue = value as? Double { return Int(doubleValue) }
            if let stringValue = value as? String { return Int(stringValue) }
            return nil
        }

        func parseDouble(_ value: Any?) -> Double? {
            if let doubleValue = value as? Double { return doubleValue }
            if let intValue = value as? Int { return Double(intValue) }
            if let stringValue = value as? String { return Double(stringValue) }
            return nil
        }

        let rawText = data["text"] as? String             ?? data["content"] as? String             ?? data["chunk"] as? String             ?? data["body"] as? String             ?? data["summary"] as? String

        guard let text = rawText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }

        self.id = id
        self.text = text
        self.title = (data["title"] as? String ?? data["heading"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.url = (data["url"] as? String ?? data["sourceUrl"] as? String ?? data["link"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.category = (data["category"] as? String ?? data["type"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sourceId = (data["sourceId"] as? String ?? data["source_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.heading = (data["heading"] as? String ?? data["section"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.order = parseInt(data["order"]) ?? parseInt(data["rank"]) ?? parseInt(data["position"]) ?? parseInt(data["priority"])
        self.score = parseDouble(data["score"]) ?? parseDouble(data["similarity"]) ?? parseDouble(data["confidence"])

        if let ts = data["updatedAt"] as? Timestamp {
            self.updatedAt = ts.dateValue()
        } else if let ts = data["updated_at"] as? Timestamp {
            self.updatedAt = ts.dateValue()
        } else {
            self.updatedAt = nil
        }
    }

    public func snippet(maxLength: Int = 220) -> String {
        let collapsed = text
            .replacingOccurrences(of: "", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines) //oba

        guard collapsed.count > maxLength else { return collapsed }
        let index = collapsed.index(collapsed.startIndex, offsetBy: maxLength)
        var prefix = String(collapsed[..<index])
        if let lastSpace = prefix.lastIndex(of: " ") {
            prefix = String(prefix[..<lastSpace])
        }
        return prefix.trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}

public struct BlueprintOnboardingData: Codable {
    public var audienceType: String?
    public var expectedVisitors: String?
    public var goal: String?
    public var keyAreas: [String]
    public var preferredStyle: String?
    public var specialFeatures: [String]
    public var techComfort: String?
    public var useCases: [String]

    public init(
        audienceType: String?,
        expectedVisitors: String?,
        goal: String?,
        keyAreas: [String],
        preferredStyle: String?,
        specialFeatures: [String],
        techComfort: String?,
        useCases: [String]
    ) {
        self.audienceType = audienceType
        self.expectedVisitors = expectedVisitors
        self.goal = goal
        self.keyAreas = keyAreas
        self.preferredStyle = preferredStyle
        self.specialFeatures = specialFeatures
        self.techComfort = techComfort
        self.useCases = useCases
    }

    public init?(dictionary: [String: Any]) {
        let keyAreas = dictionary["keyAreas"] as? [String] ?? []
        let specialFeatures = dictionary["specialFeatures"] as? [String] ?? []
        let useCases = dictionary["useCases"] as? [String] ?? []

        self.init(
            audienceType: dictionary["audienceType"] as? String,
            expectedVisitors: dictionary["expectedVisitors"] as? String,
            goal: dictionary["goal"] as? String,
            keyAreas: keyAreas,
            preferredStyle: dictionary["preferredStyle"] as? String,
            specialFeatures: specialFeatures,
            techComfort: dictionary["techComfort"] as? String,
            useCases: useCases
        )
    }
}

public struct ConversationLog: Codable {
    public var userMessage: String
    public var assistantMessage: String
    public var timestamp: Date
    public var userId: String
    public var sessionId: String

    public init(userMessage: String, assistantMessage: String, timestamp: Date, userId: String, sessionId: String) {
        self.userMessage = userMessage
        self.assistantMessage = assistantMessage
        self.timestamp = timestamp
        self.userId = userId
        self.sessionId = sessionId
    }

    public init?(dictionary: [String: Any]) {
        guard let userMessage = dictionary["userMessage"] as? String,
              let assistantMessage = dictionary["assistantMessage"] as? String,
              let timestamp = dictionary["timestamp"] as? Timestamp,
              let userId = dictionary["userId"] as? String,
              let sessionId = dictionary["sessionId"] as? String else { return nil }
        self.init(userMessage: userMessage,
                  assistantMessage: assistantMessage,
                  timestamp: timestamp.dateValue(),
                  userId: userId,
                  sessionId: sessionId)
    }

    public func toDictionary() -> [String: Any] {
        return [
            "userMessage": userMessage,
            "assistantMessage": assistantMessage,
            "timestamp": Timestamp(date: timestamp),
            "userId": userId,
            "sessionId": sessionId
        ]
    }
}

public class Blueprint {
    static let GEOHASH       = "geohash"
    
    private(set) var latitude          : Double?// = ""
    private(set) var longitude          : Double?// = ""
    private(set) var altitude          : Double?
    var id             : String = ""
    var host      : String = ""
    var name            : String = ""
    var version         : String = "1.0.0"
    var size            : Double = 0
    var numSessions     : Int = 0
    var password       : String = ""
    var category       : String = ""
    var storage       : Double = 0
    var thumbnail       : String? = nil
    var isPrivate        : Bool?
    var address        : String?
    var createdDate       = Date()
    var connectedTime: TimeInterval = 0
    var photoLimit       : Double = 0
    var noteLimit       : Double = 0
    var objectLimit       : Double = 0
    var widgetLimit       : Double = 0
    var portalLimit       : Double = 0
    var websiteLimit       : Double = 0
    var fileLimit       : Double = 0 ///just for change
    var userCount     : Int = 0
    var photoCount      : Double = 0
    var noteCount       : Double = 0
    var widgetCount       : Double = 0
    var objectCount       : Double = 0
    var portalCount       : Double = 0
    var fileCount       : Double = 0
    var websiteCount       : Double = 0

    var conversationLogs: [ConversationLog] = []

    var lastSessionDate       = Date()
    var monthlySessionCounts    = [String: Int]()
    var monthlySessionDurations = [String: TimeInterval]()
    var monthlyUserCounts       = [String: Int]()

    
    private(set) var roomIDs    = [String]()
    private(set) var anchorIDs    = [String]()
    private(set) var websiteURLs    = [URL]()
    private(set) var websiteURLStrings: [String] = []
    var businessName: String?
    var locationType: String?
    var experienceMode: String?
    var locationURLs: [String] = []
    var phone: String?
    var onboardingData: BlueprintOnboardingData?
    private(set) var objectIDs    = [String]()
    private(set) var portalIDs    = [String]()
    private(set) var noteIDs    = [String]()
    private(set) var photoIDs    = [String]()
    private(set) var fileIDs    = [String]()
    private(set) var widgetIDs    = [String]()
    private(set) var users    = [String]()
    public var markedAreas: [MarkedArea]?
    var aiAssistantWelcomeMessages: [String: String] = [:]
    var aiAssistantWelcomeMessagesUpdatedAt: Date?
    var aiAssistantSystemInstructions: String?
    var aiAssistantVoice: String?
    var aiAssistantFallbackMessages: [String] = []
    var aiAssistantMetaRuntimeExpectations: [String] = []
    var aiAssistantToolHints: [BlueprintToolHint] = []
    var aiOperationalDetails: BlueprintOperationalDetails?
    var aiTopVisitorQuestions: [String] = []
    var aiKnowledgeSources: [BlueprintKnowledgeSource] = []
    var aiKnowledgeIndex: BlueprintKnowledgeIndex?
    var aiResearchSummary: String?
    var aiResearchRawReport: String?
    var knowledgeChunks: [BlueprintKnowledgeChunk] = []
  //  private(set) var currentUsers    = [String]()
    //    var price          : String = ""
    //   var timeStamp : Date()
    
    static let CREATOR         = "host"
    
    init(_ userFirDoc: [String:Any]) {
        
        // uid
        if let id = userFirDoc["id"] as? String {
            self.id = id
        }
        
        // name
        if let name = userFirDoc["name"] as? String {
            self.name = name
        }
        
        if let version = userFirDoc["version"] as? String {
            self.version = version
        }

        if let password = userFirDoc["password"] as? String {
            self.password = password
        }

        if let category = userFirDoc["category"] as? String {
            self.category = category
        }

        // emailStr
        if let host = userFirDoc["host"] as? String {
            self.host = host
        }

        if let businessName = userFirDoc["businessName"] as? String {
            self.businessName = businessName
        }

        if let locationType = userFirDoc["locationType"] as? String {
            self.locationType = locationType
        }

        if let experienceMode = userFirDoc["experienceMode"] as? String {
            self.experienceMode = experienceMode.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let address = userFirDoc["address"] as? String {
            self.address = address
        }

        if let phone = userFirDoc["phone"] as? String {
            self.phone = phone
        }

        if let onboardingDictionary = userFirDoc["onboardingData"] as? [String: Any] {
            self.onboardingData = BlueprintOnboardingData(dictionary: onboardingDictionary)
        }

        if let locationURLs = userFirDoc["locationURLs"] as? [String] {
            self.locationURLs = locationURLs
        }

        if let portalLimit = userFirDoc["portalLimit"] as? Double {
            self.portalLimit = portalLimit
        }
        
        if let objectLimit = userFirDoc["objectLimit"] as? Double {
            self.objectLimit = objectLimit
        }
        
        if let fileLimit = userFirDoc["fileLimit"] as? Double {
            self.fileLimit = fileLimit
        }
        
        if let photoLimit = userFirDoc["photoLimit"] as? Double {
            self.photoLimit = photoLimit
        }
        
        if let noteLimit = userFirDoc["noteLimit"] as? Double {
            self.noteLimit = noteLimit
        }
        
        if let widgetLimit = userFirDoc["widgetLimit"] as? Double {
            self.widgetLimit = widgetLimit
        }
        
        if let websiteLimit = userFirDoc["websiteLimit"] as? Double {
            self.websiteLimit = websiteLimit
        }
        
        if let portalCount = userFirDoc["portalCount"] as? Double {
            self.portalCount = portalCount
        }
        
        if let fileCount = userFirDoc["fileCount"] as? Double {
            self.fileCount = fileCount
        }
        
        if let websiteCount = userFirDoc["websiteCount"] as? Double {
            self.websiteCount = websiteCount
        }
        
        if let widgetCount = userFirDoc["widgetCount"] as? Double {
            self.widgetCount = widgetCount
        }
        
        if let objectCount = userFirDoc["objectCount"] as? Double {
            self.objectCount = objectCount
        }
        
        if let photoCount = userFirDoc["photoCount"] as? Double {
            self.photoCount = photoCount
        }
        
        if let noteCount = userFirDoc["noteCount"] as? Double {
            self.noteCount = noteCount
        }
        
        if let storage = userFirDoc["storage"] as? Double {
            self.storage = storage
        }
        
//        if let date = userFirDoc["date"] as? Date {
//            self.date = date
//        }
        
        if let timestamp = userFirDoc["createdDate"] as? Timestamp {
                self.createdDate = timestamp.dateValue()
            }
        
        if let timestamp = userFirDoc["lastSessionDate"] as? Timestamp {
                self.lastSessionDate = timestamp.dateValue()
            }

        if let monthlySessionCounts = userFirDoc["monthlySessionCounts"] as? [String: Int] {
            self.monthlySessionCounts = monthlySessionCounts
        } else if let monthlySessionCounts = userFirDoc["monthlySessionCounts"] as? [String: Double] {
            self.monthlySessionCounts = monthlySessionCounts.mapValues { Int($0) }
        }

        if let monthlySessionDurations = userFirDoc["monthlySessionDurations"] as? [String: TimeInterval] {
            self.monthlySessionDurations = monthlySessionDurations
        } else if let monthlySessionDurations = userFirDoc["monthlySessionDurations"] as? [String: Double] {
            self.monthlySessionDurations = monthlySessionDurations
        }

        if let monthlyUserCounts = userFirDoc["monthlyUserCounts"] as? [String: Int] {
            self.monthlyUserCounts = monthlyUserCounts
        } else if let monthlyUserCounts = userFirDoc["monthlyUserCounts"] as? [String: Double] {
            self.monthlyUserCounts = monthlyUserCounts.mapValues { Int($0) }
        }
        
        //usernameStr
        if let size = userFirDoc["size"] as? Double {
            self.size = size
        }
        
        if let isPrivate = userFirDoc["isPrivate"] as? Bool {
            self.isPrivate = isPrivate
        }
        
        if let thumbnail = userFirDoc["thumbnail"] as? String {
            self.thumbnail = thumbnail
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
        
        if let connectedTime = userFirDoc["connectedTime"] as? TimeInterval {
            self.connectedTime = connectedTime
        }
        
        if let numSessions = userFirDoc["numSessions"] as? Int {
            self.numSessions = numSessions
        }
        
        if let userCount = userFirDoc["userCount"] as? Int {
            self.userCount = userCount
        }
        
        if let users = userFirDoc["users"] as? [String] {
            self.users = users
        }

        if let conversationLogsArray = userFirDoc["conversationLogs"] as? [[String: Any]] {
            self.conversationLogs = conversationLogsArray.compactMap { ConversationLog(dictionary: $0) }
        }

        if let anchorIDs = userFirDoc["anchorIDs"] as? [String] {
            self.anchorIDs = anchorIDs
        }
        
        if let roomIDs = userFirDoc["roomIDs"] as? [String] {
            self.roomIDs = roomIDs
        }
        
        if let objectIDs = userFirDoc["objectIDs"] as? [String] {
            self.objectIDs = objectIDs
        }
        
        if let portalIDs = userFirDoc["portalIDs"] as? [String] {
            self.portalIDs = portalIDs
        }
        
        if let photoIDs = userFirDoc["photoIDs"] as? [String] {
            self.photoIDs = photoIDs
        }
        
        if let noteIDs = userFirDoc["noteIDs"] as? [String] {
            self.noteIDs = noteIDs
        }
        
        if let fileIDs = userFirDoc["fileIDs"] as? [String] {
            self.fileIDs = fileIDs
        }
        
        if let widgetIDs = userFirDoc["widgetIDs"] as? [String] {
            self.widgetIDs = widgetIDs
        }

        if let websiteURLStrings = userFirDoc["websiteURLs"] as? [String] {
            self.websiteURLStrings = websiteURLStrings
            self.websiteURLs = websiteURLStrings.compactMap { URL(string: $0) }
        } else if let websiteURLs = userFirDoc["websiteURLs"] as? [URL] {
            self.websiteURLs = websiteURLs
            self.websiteURLStrings = websiteURLs.map { $0.absoluteString }
        }

        if let markedAreasData = userFirDoc["markedAreas"] as? [[String: Any]] {
            self.markedAreas = markedAreasData.compactMap { MarkedArea(dictionary: $0) }
        }

        let legacyWelcome = Blueprint.extractWelcomeMessages(from: userFirDoc["welcome_messages"])
        let defaultWelcome = Blueprint.extractWelcomeMessages(from: userFirDoc["aiDefaultWelcomeMessages"])
        let assistantWelcome = Blueprint.extractWelcomeMessages(from: userFirDoc["aiAssistantWelcomeMessages"])

        var mergedWelcome: [String: String] = [:]
        mergedWelcome.merge(legacyWelcome) { current, _ in current }
        mergedWelcome.merge(defaultWelcome) { _, new in new }
        mergedWelcome.merge(assistantWelcome) { _, new in new }
        self.aiAssistantWelcomeMessages = mergedWelcome

        if let timestamp = userFirDoc["aiAssistantWelcomeMessagesUpdatedAt"] as? Timestamp {
            self.aiAssistantWelcomeMessagesUpdatedAt = timestamp.dateValue()
        } else if let timestamp = userFirDoc["aiDefaultWelcomeMessagesUpdatedAt"] as? Timestamp {
            self.aiAssistantWelcomeMessagesUpdatedAt = timestamp.dateValue()
        }
        self.aiAssistantSystemInstructions = Blueprint.cleanString(userFirDoc["aiAssistantSystemInstructions"])
            ?? Blueprint.cleanString(userFirDoc["aiAssistantInstructions"])
            ?? Blueprint.cleanString(userFirDoc["assistantInstructions"])

        self.aiAssistantVoice = Blueprint.cleanString(userFirDoc["aiAssistantVoice"])
            ?? Blueprint.cleanString(userFirDoc["assistantVoice"])

        self.aiAssistantFallbackMessages = Blueprint.cleanStrings(userFirDoc["aiAssistantFallbackMessages"])
        if self.aiAssistantFallbackMessages.isEmpty {
            self.aiAssistantFallbackMessages = Blueprint.cleanStrings(userFirDoc["aiAssistantFallbacks"])
        }

        self.aiAssistantMetaRuntimeExpectations = Blueprint.cleanStrings(userFirDoc["aiAssistantMetaRuntimeExpectations"])
        if self.aiAssistantMetaRuntimeExpectations.isEmpty {
            self.aiAssistantMetaRuntimeExpectations = Blueprint.cleanStrings(userFirDoc["metaRuntimeExpectations"])
        }

        if let hintArray = userFirDoc["aiAssistantToolHints"] as? [[String: Any]] {
            var hints: [BlueprintToolHint] = []
            var seenNames = Set<String>()
            for entry in hintArray {
                if let hint = BlueprintToolHint(dictionary: entry) {
                    let key = hint.name.lowercased()
                    if seenNames.insert(key).inserted {
                        hints.append(hint)
                    }
                }
            }
            self.aiAssistantToolHints = hints
        }

        if let operational = userFirDoc["aiOperationalDetails"] as? [String: Any] {
            self.aiOperationalDetails = BlueprintOperationalDetails(dictionary: operational)
        } else if let operational = userFirDoc["operational_details"] as? [String: Any] {
            self.aiOperationalDetails = BlueprintOperationalDetails(dictionary: operational)
        }

        self.aiTopVisitorQuestions = Blueprint.cleanStrings(userFirDoc["aiTopVisitorQuestions"])
        if self.aiTopVisitorQuestions.isEmpty {
            self.aiTopVisitorQuestions = Blueprint.cleanStrings(userFirDoc["top_questions"])
        }

        let sourceEntries = (userFirDoc["knowledgeSourceUrls"] as? [[String: Any]])
            ?? (userFirDoc["aiAssistantKnowledgeSources"] as? [[String: Any]])
            ?? (userFirDoc["knowledge_sources"] as? [[String: Any]])
        if let sourceEntries {
            var deduped: [BlueprintKnowledgeSource] = []
            var seen = Set<String>()
            for entry in sourceEntries {
                if let source = BlueprintKnowledgeSource(dictionary: entry) {
                    let key = source.url.lowercased()
                    if seen.insert(key).inserted {
                        deduped.append(source)
                    }
                }
            }
            self.aiKnowledgeSources = deduped
        }

        if let indexInfo = userFirDoc["aiKnowledgeIndex"] as? [String: Any] {
            self.aiKnowledgeIndex = BlueprintKnowledgeIndex(dictionary: indexInfo)
        }

        self.aiResearchSummary = Blueprint.cleanString(userFirDoc["aiResearchSummary"])
            ?? Blueprint.cleanString(userFirDoc["aiResearchSummaryText"])
            ?? Blueprint.cleanString(userFirDoc["summary"])

        self.aiResearchRawReport = Blueprint.cleanString(userFirDoc["aiResearchRawReport"])

    }

    private static func extractWelcomeMessages(from raw: Any?) -> [String: String] {
        guard let raw else { return [:] }
        if let typed = raw as? [String: String] {
            return typed.mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }

        if let dictionary = raw as? [String: Any] {
            var cleaned: [String: String] = [:]
            for (key, value) in dictionary {
                if let text = value as? String {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }
                    cleaned[key] = trimmed
                }
            }
            return cleaned
        }

        return [:]
    }

    func welcomeMessage(for persona: BlueprintWelcomePersona) -> String? {
        let primary = aiAssistantWelcomeMessages[persona.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let primary, !primary.isEmpty {
            return primary
        }

        if persona != .casualVisitor {
            if let fallback = aiAssistantWelcomeMessages[BlueprintWelcomePersona.casualVisitor.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines), !fallback.isEmpty {
                return fallback
            }
        }

        if let generic = aiAssistantWelcomeMessages[BlueprintWelcomePersona.targetCustomer.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines), !generic.isEmpty {
            return generic
        }

        return aiAssistantWelcomeMessages.values.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private static func cleanString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func cleanStrings(_ raw: Any?) -> [String] {
        if let strings = raw as? [String] {
            return strings.compactMap { cleanString($0) }
        }
        if let array = raw as? [Any] {
            return array.compactMap { cleanString($0) }
        }
        return []
    }
}

extension Blueprint {
    var isAudioExperience: Bool {
        return experienceMode?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "audio"
    }
    var isSpatialExperience: Bool {
        return experienceMode?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "spatial"
    }
}


struct KnowledgeChunk: Sendable {
    let id: String
    let text: String
    let sourceTitle: String?
    let sourceUrl: String?
}

struct ToolHint: Sendable {
    let name: String          // e.g., open_link
    let whenToUse: String     // guidance for model
    let metaCall: String?     // human-friendly summary
}

// Simple in-memory store; replace with Firestore later.
protocol BlueprintStore: Sendable {
    func load(by id: String) async throws -> Blueprint
}

/*
// Demo implementation so the app runs without Firestore.
actor InMemoryBlueprintStore: BlueprintStore {
    func load(by id: String) async throws -> Blueprint {
        if id == "10941af4-2200-4c85-bc4e-1470f93782ae" {
            let doc: [String: Any] = [
                "id": id,
                "name": "Viceroy, West Main Street, Durham, NC",
                "businessName": "Viceroy, West Main Street, Durham, NC",
                "address": "335 W Main St, Durham, NC 27701",
                "phone": "9196389913",
                "locationType": "retail",
                "aiAssistantSystemInstructions": "You are the on-location voice assistant for Viceroy, a modern Indian restaurant at 335 W Main St, Durham, NC. Hours: Mon/Wed-Thu/Sun 5-10pm, Fri-Sat 5-10:30pm, Closed Tue. Phone (919) 797-0413. Popular dishes: Jeera wings, Achari Paneer, Chicken Murg Mykanwala. Offers vegetarian/vegan/gluten-free options. Reservations recommended. Takeout available. Parking at Corcoran St. Garage behind building (free weekends/after 7pm). No high chairs. 90-minute dining window. Answer visitor questions about hours, menu, reservations, parking, dietary options. Default to one sentence, offer actions when helpful. Voice-first interface with brief HUD text only.",
                "aiAssistantVoice": "calm, helpful, efficient",
                "aiAssistantFallbackMessages": [
                    "Sorry, I can't reach that right now. Want hours and directions instead?",
                    "Let me connect you with our staff for that request.",
                    "Our hours today are 5pm to 10pm - want me to show parking directions?"
                ],
                "aiAssistantMetaRuntimeExpectations": [
                    "Prefer audio first; keep HUD text under 40 chars/line for <= 4s.",
                    "Log unresolved intents for future training.",
                    "Always get consent before capturing photos/audio clips.",
                    "Hand off complex reservations to staff or booking system."
                ],
                "aiAssistantWelcomeMessages": [
                    "casualVisitor": "Hi there! I'm your assistant at Viceroy. Exploring our modern Indian restaurant? I can share our hours, popular dishes, or answer any questions.",
                    "partnerPress": "Welcome to Viceroy! I'm here to assist with your visit. Need information about our restaurant, menu details, or connecting with management?",
                    "staffMember": "Hello! I'm here to support you during your shift at Viceroy. Need updates on reservations, menu items, or operational details for today?",
                    "targetCustomer": "Welcome to Viceroy! I'm here to help you discover our modern Indian cuisine and craft cocktails. Need a table reservation or menu recommendations?",
                    "vipMember": "Welcome back to Viceroy! I'm delighted to assist you again. Ready for your usual table or would you like to try something new today?"
                ],
                "aiOperationalDetails": [
                    "hours": "Sunday-Monday, Wednesday-Thursday 5:00 PM - 10:00 PM; Friday-Saturday 5:00 PM - 10:30 PM; Closed Tuesday",
                    "contact": "(919) 797-0413",
                    "accessibility": "Wheelchair accessible",
                    "parking": "Street parking available"
                ],
                "aiTopVisitorQuestions": [
                    "What are your hours today?",
                    "Do you take reservations?",
                    "What are your most popular dishes?",
                    "Do you have vegetarian or vegan options?",
                    "Is there parking nearby?",
                    "Do you have outdoor seating?",
                    "Can I order takeout?",
                    "How spicy are the dishes?",
                    "Do you serve lunch or just dinner?"
                ],
                "aiAssistantToolHints": [
                    ["name": "open_link", "when_to_use": "When user needs menu, reservations, or takeout ordering", "meta_call": "Opens viceroydurham.com for menu/reservations"],
                    ["name": "start_navigation", "when_to_use": "When user needs directions to parking or restaurant location", "meta_call": "Audio wayfinding to 335 W Main St or Corcoran St. Garage"],
                    ["name": "create_booking", "when_to_use": "When user wants to make a reservation", "meta_call": "Initiates reservation process with party size, date, time"],
                    ["name": "request_staff", "when_to_use": "When user needs server assistance or has special dietary needs", "meta_call": "Pages staff with context about guest request"]
                ],
                "knowledgeSourceUrls": [
                    ["title": "Official Website", "url": "https://www.viceroydurham.com", "category": "menu", "description": "Primary source for current menu, reservations, and takeout ordering"],
                    ["title": "TripAdvisor Listing", "url": "https://www.tripadvisor.com/Restaurant_Review-g49092-d12315756-Reviews-Viceroy-Durham_North_Carolina.html", "category": "reviews", "description": "Guest reviews, photos, hours, and restaurant features information"],
                    ["title": "Discover Durham Directory", "url": "https://www.discoverdurham.com/directory/viceroy/", "category": "other", "description": "Local tourism board listing with recommended dishes and visitor tips"],
                    ["title": "Downtown Durham Directory", "url": "https://downtowndurham.com/directory/viceroy/", "category": "other", "description": "Downtown district information including outdoor seating availability"]
                ],
                "aiKnowledgeIndex": [
                    "chunkCount": 38,
                    "sourceCount": 4
                ],
                "aiResearchSummary": "Viceroy is a highly-rated modern Indian restaurant and craft cocktail bar in downtown Durham, serving dishes like Jeera wings, Achari Paneer, and Chicken Murg Mykanwala. Visitors come for the upscale Indian cuisine, creative cocktails, and welcoming atmosphere with London-inspired decor.",
                "aiResearchRawReport": "<think> Let me analyze the search results to create a compact JSON knowledge kit for Viceroy restaurant in Durham, NC. From the search results, I can extract: 1. **Basic Info:** - Company: Viceroy - Address: 335 W Main St, Durham, NC 27701 - Phone: (919) 797-0413 - Website: http://www.viceroydurham.com/ (I need to convert this to https) - Type: Modern Indian restaurant with craft cocktails 2. **Hours from TripAdvisor:** - Sunday: 5:00 PM - 10:00 PM - Monday: 5:00 PM - 10:00 PM - Tuesday: Closed - Wednesday: 5:00 PM - 10:00 PM - Thursday: 5:00 PM - 10:00 PM - Friday: 5:00 PM - 10:30 PM - Saturday: 5:00 PM - 10:30 PM 3. **Ratings/Reviews:** - TripAdvisor: 4.5/5 with 92 reviews, ranked #29 of 708 restaurants in Durham - Discover Durham: 4.6 rating 4. **Features:** - Full bar, reservations, takeout, wheelchair accessible - Vegetarian friendly, vegan options, gluten free options - Outdoor seating available 5. **URLs I can identify:** - Primary website: https://www.viceroydurham.com (converting from http) - TripAdvisor page: https://www.tripadvisor.com/Restaurant_Review-g49092-d12315756-Reviews-Viceroy-Durham_North_Carolina.html - Discover Durham: https://www.discoverdurham.com/directory/viceroy/ - Downtown Durham Inc: https://downtowndurham.com/directory/viceroy/ I'll carefully compile the JSON structure, ensuring I only use verified information from the search results. The key will be creating a concise representation that captures Viceroy's unique dining experience without adding unconfirmed details. </think> { \"summary\": \"Viceroy is a highly-rated modern Indian restaurant and craft cocktail bar in downtown Durham, serving dishes like Jeera wings, Achari Paneer, and Chicken Murg Mykanwala. Visitors come for the upscale Indian cuisine, creative cocktails, and welcoming atmosphere with London-inspired decor.\", \"url_context\": { \"must_include\": [ { \"title\": \"Homepage\", \"url\": \"https://www.viceroydurham.com\", \"category\": \"home\", \"why_it_matters\": \"Official restaurant website for menu, reservations, and current information\", \"updated_on\": null } ], \"nice_to_have\": [ { \"title\": \"TripAdvisor Reviews\", \"url\": \"https://www.tripadvisor.com/Restaurant_Review-g49092-d12315756-Reviews-Viceroy-Durham_North_Carolina.html\", \"category\": \"reviews\", \"why_it_matters\": \"Recent guest reviews and detailed restaurant information including hours\", \"updated_on\": null } ], \"crawl_instructions\": { \"dedupe_rules\": \"Canonicalize; drop utm/*; prefer https; one URL per unique task\", \"max_total_urls\": 12 } }, \"knowledge_sources\": [ { \"title\": \"Official Website\", \"url\": \"https://www.viceroydurham.com\", \"category\": \"menu\", \"description\": \"Primary source for current menu, reservations, and takeout ordering\" }, { \"title\": \"TripAdvisor Listing\", \"url\": \"https://www.tripadvisor.com/Restaurant_Review-g49092-d12315756-Reviews-Viceroy-Durham_North_Carolina.html\", \"category\": \"reviews\", \"description\": \"Guest reviews, photos, hours, and restaurant features information\" }, { \"title\": \"Discover Durham Directory\", \"url\": \"https://www.discoverdurham.com/directory/viceroy/\", \"category\": \"other\", \"description\": \"Local tourism board listing with recommended dishes and visitor tips\" }, { \"title\": \"Downtown Durham Directory\", \"url\": \"https://downtowndurham.com/directory/viceroy/\", \"category\": \"other\", \"description\": \"Downtown district information including outdoor seating availability\" } ], \"top_questions\": [ \"What are your hours today?\", \"Do you take reservations?\", \"What are your most popular dishes?\", \"Do you have vegetarian or vegan options?\", \"Is there parking nearby?\", \"Do you have outdoor seating?\", \"Can I order takeout?\", \"How spicy are the dishes?\", \"Do you serve lunch or just dinner?\" ], \"operational_details\": { \"hours\": \"Sunday-Monday, Wednesday-Thursday 5:00 PM - 10:00 PM; Friday-Saturday 5:00 PM - 10:30 PM; Closed Tuesday\", \"pricing\": null, \"contact\": \"(919) 797-0413\", \"accessibility\": \"Wheelchair accessible\", \"parking\": \"Street parking available\", \"wifi\": null }, \"runtime_hints\": [ \"Restaurant is dinner-only, closed Tuesdays\", \"Recommend calling for reservations especially on weekends\", \"Suggest mild spice level for first-time visitors\", \"Mention popular appetizers like Jeera wings and Gobi Sukka\" ] }"
            ]
            let blueprint = Blueprint(doc)
            // Seed a few representative knowledge chunks for local retrieval
            var seededChunks: [BlueprintKnowledgeChunk] = []
            let rawChunks: [(String, [String: Any])] = [
                ("c0", ["text": "Hours: Sunday, Monday, Wednesday, Thursday 5-10pm; Friday, Saturday 5-10:30pm. Closed Tuesdays. Phone: (919) 797-0413. Address: 335 W Main St, Durham, NC 27701.", "title": "Hours & Contact", "url": "https://www.viceroydurham.com", "category": "home"]),
                ("c1", ["text": "Popular dishes: Jeera wings, Achari Paneer, Chicken Murg Mykanwala. Vegetarian/vegan/gluten-free options available. Reservations recommended.", "title": "Menu Highlights", "url": "https://www.viceroydurham.com", "category": "home"]),
                ("c2", ["text": "Parking: Corcoran St. Garage behind building; free weekends/after 7pm. No high chairs. 90-minute dining window.", "title": "Parking & Policies", "url": "https://www.viceroydurham.com", "category": "home"]),
                ("c3", ["text": "Dinner only; closed Tuesdays. Wheelchair accessible.", "title": "Service Window & Accessibility", "url": "https://www.tripadvisor.com/Restaurant_Review-g49092-d12315756-Reviews-Viceroy-Durham_North_Carolina.html", "category": "reviews"])
            ]
            for (chunkId, data) in rawChunks {
                if let chunk = BlueprintKnowledgeChunk(id: chunkId, data: data) {
                    seededChunks.append(chunk)
                }
            }
            blueprint.knowledgeChunks = seededChunks
            return blueprint
        }

        // Fallback minimal blueprint
        let minimalDoc: [String: Any] = [
            "id": id,
            "name": "On-site Assistant",
            "aiAssistantWelcomeMessages": ["default": "Hi! How can I help on site today?"]
        ]
        return Blueprint(minimalDoc)
    }
}
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            */*/
