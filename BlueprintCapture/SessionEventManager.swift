import Foundation
import FirebaseFirestore
import UIKit

final class SessionEventManager {
    static let shared = SessionEventManager()
    private init() {}

    private let db = Firestore.firestore()
    private lazy var eventsCollection = db.collection("sessionEvents")
    private var currentSessionId: String?
    private var sessionStartTime: Date?
    private var interactionCount: Int = 0
    private var currentUserId: String = ""
    private var currentBlueprintId: String = ""
    private var currentReferralBlueprintId: String?
    private var currentNetworkContext: String?
    private var currentNetworkSpeed: Double?
    private var device: String { UIDevice.current.model }
    private var osVersion: String { UIDevice.current.systemVersion }
    private var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown" }
    private var locale: String { Locale.current.identifier }

    // MARK: - New API per Data Tracking Plan
    @discardableResult
    func startSession(
        blueprintId: String,
        userId: String,
        networkContext: String,
        networkSpeedKbps: Double? = nil,
        referralBlueprintId: String? = nil
    ) -> String {
        let sessionId = eventsCollection.document().documentID
        currentSessionId = sessionId
        let startDate = Date()
        sessionStartTime = startDate
        interactionCount = 0
        currentBlueprintId = blueprintId
        currentUserId = userId
        currentReferralBlueprintId = referralBlueprintId
        currentNetworkContext = networkContext
        currentNetworkSpeed = networkSpeedKbps

        var doc = baseEventPayload(sessionId: sessionId, eventType: "sessionStart")
        doc["startTime"] = Timestamp(date: startDate)
        doc["networkContext"] = networkContext
        if let speed = networkSpeedKbps {
            doc["networkSpeedKbps"] = speed
        }
        if let referral = referralBlueprintId {
            doc["referralBlueprintId"] = referral
        }
        doc["interactionCount"] = 0

        eventsCollection.document(sessionId).setData(doc)
        return sessionId
    }

    // Backward-compat shim: maps legacy params to new API (replaces venue with blueprint)
    @discardableResult
    func startSession(
        userId: String,
        blueprintId: String,
        blueprintVersion: String,
        loadTimeMs: Double,
        scanSuccess: Bool,
        networkContext: String,
        networkSpeedKbps: Double?,
        referralBlueprintId: String?
    ) -> String {
        let sid = startSession(
            blueprintId: blueprintId,
            userId: userId,
            networkContext: networkContext,
            networkSpeedKbps: networkSpeedKbps,
            referralBlueprintId: referralBlueprintId
        )
        // immediately record the QR scan outcome if provided by legacy caller
        logQrScan(success: scanSuccess, loadTimeMs: Int(loadTimeMs))
        return sid
    }

    func logQrScan(success: Bool, loadTimeMs: Int) {
        guard let sessionId = currentSessionId else { return }
        var doc = baseEventPayload(sessionId: sessionId, eventType: "qrScan")
        doc["startTime"] = FieldValue.serverTimestamp()
        doc["loadTimeMs"] = loadTimeMs
        doc["scanSuccess"] = success
        doc["interactionCount"] = interactionCount
        if let context = currentNetworkContext {
            doc["networkContext"] = context
        }
        if let speed = currentNetworkSpeed {
            doc["networkSpeedKbps"] = speed
        }
        if let referral = currentReferralBlueprintId {
            doc["referralBlueprintId"] = referral
        }
        eventsCollection.addDocument(data: doc)
    }

    func logInteraction(kind: String, metadata: [String: Any]? = nil) {
        guard let sessionId = currentSessionId else { return }
        interactionCount += 1
        var doc = baseEventPayload(sessionId: sessionId, eventType: "interaction")
        doc["interactionKind"] = kind
        doc["interactionCount"] = interactionCount
        if let metadata = metadata {
            doc["metadata"] = metadata
        }
        eventsCollection.addDocument(data: doc)
    }

    // Backward-compat: old signature used across the app
    func logInteraction(sessionId: String, interactionType: String, details: [String: Any]? = nil) {
        // We don’t use the provided sessionId for routing; just map to the new API.
        logInteraction(kind: interactionType, metadata: details)
    }

    func endSession(crash: Bool, errorCode: String?) {
        guard let sessionId = currentSessionId, let start = sessionStartTime else { return }
        let end = Date()
        let lengthMs = Int(end.timeIntervalSince(start) * 1000)

        // Determine returned (bool) by checking user doc once
        var returnedValue: Bool = false
        let userRef = db.collection("users").document(currentUserId)
        userRef.getDocument { [weak self] snap, _ in
            if let data = snap?.data() {
                let count = (data["sessionCount"] as? Int) ?? 0
                returnedValue = count > 0
            }
            guard let self = self else { return }
            var doc = self.baseEventPayload(sessionId: sessionId, eventType: "sessionEnd")
            doc["startTime"] = Timestamp(date: start)
            doc["endTime"] = Timestamp(date: end)
            doc["sessionLengthMs"] = lengthMs
            doc["returned"] = returnedValue
            doc["crash"] = crash
            doc["interactionCount"] = self.interactionCount
            if let errorCode = errorCode {
                doc["errorCode"] = errorCode
            }
            if let referral = self.currentReferralBlueprintId {
                doc["referralBlueprintId"] = referral
            }
            if let context = self.currentNetworkContext {
                doc["networkContext"] = context
            }
            if let speed = self.currentNetworkSpeed {
                doc["networkSpeedKbps"] = speed
            }
            self.eventsCollection.addDocument(data: doc)
            // Reset state
            self.currentSessionId = nil
            self.sessionStartTime = nil
            self.interactionCount = 0
            self.currentReferralBlueprintId = nil
            self.currentNetworkContext = nil
            self.currentNetworkSpeed = nil
        }
    }

    // Backward-compat: map reason → crash flag
    func endSession(sessionId: String, reason: String, errorCode: String?) {
        endSession(crash: reason == "crash", errorCode: errorCode)
    }

    func logError(errorCode: String, metadata: [String: Any]? = nil) {
        guard let sessionId = currentSessionId else { return }
        var doc = baseEventPayload(sessionId: sessionId, eventType: "error")
        doc["errorCode"] = errorCode
        if let metadata = metadata {
            doc["metadata"] = metadata
        }
        eventsCollection.addDocument(data: doc)
    }

    private func baseEventPayload(sessionId: String, eventType: String) -> [String: Any] {
        var doc: [String: Any] = [
            "sessionId": sessionId,
            "eventType": eventType,
            "occurredAt": FieldValue.serverTimestamp(),
            "device": device,
            "osVersion": osVersion,
            "appVersion": appVersion,
            "locale": locale
        ]
        if !currentBlueprintId.isEmpty {
            doc["blueprintId"] = currentBlueprintId
        }
        if !currentUserId.isEmpty {
            doc["userId"] = currentUserId
        }
        return doc
    }
}
