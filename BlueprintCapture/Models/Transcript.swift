import Foundation

public struct Transcript: Codable {
    public var sessionId: String
    public var userId: String
    public var blueprintId: String
    public var startedAt: Date?
    public var endedAt: Date?

    public init(sessionId: String, userId: String, blueprintId: String, startedAt: Date? = nil, endedAt: Date? = nil) {
        self.sessionId = sessionId
        self.userId = userId
        self.blueprintId = blueprintId
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}

public struct TranscriptMessage: Codable {
    public var role: String
    public var text: String
    public var index: Int
    public var timestamp: Date?

    public init(role: String, text: String, index: Int, timestamp: Date? = nil) {
        self.role = role
        self.text = text
        self.index = index
        self.timestamp = timestamp
    }
}

