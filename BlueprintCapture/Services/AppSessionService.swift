//
//  AppSessionService.swift
//  BlueprintCapture
//
//  Creates a sessions document on app open and funnels interaction tracking.
//

import Foundation
import FirebaseFirestore
import CoreLocation

final class AppSessionService {
    static let shared = AppSessionService()
    private init() {}

    private let db = Firestore.firestore()
    private var sessions: CollectionReference { db.collection("sessions") }

    private var currentSessionId: String?
    private var sessionStart: Date?

    /// Starts a new app session, creates a `sessions` document and bootstraps event tracking.
    func startIfNeeded() {
        guard currentSessionId == nil else { return }
        let userId = UserDeviceService.resolvedUserId()

        // Re-use the session id produced by the event stream so both collections share the same id
        let sid = SessionEventManager.shared.startSession(
            blueprintId: "",
            userId: userId,
            networkContext: "appLaunch",
            networkSpeedKbps: nil,
            referralBlueprintId: nil
        )

        currentSessionId = sid
        sessionStart = Date()
        UserDefaults.standard.set(sid, forKey: "currentSessionId")

        var doc: [String: Any] = [
            "id": sid,
            "userId": userId,
            "startTime": Timestamp(date: sessionStart ?? Date()),
            "duration": 0,
            "device": UIDevice.current.model,
            "osVersion": UIDevice.current.systemVersion,
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        ]
        sessions.document(sid).setData(doc, merge: true)

        // Best-effort capture of start location when available
        Task {
            if let coord = await OneShotLocationFetcher.fetch() {
                let update: [String: Any] = [
                    "latitude": coord.latitude,
                    "longitude": coord.longitude
                ]
                try? await self.sessions.document(sid).setData(update, merge: true)
            }
        }

        // Increment local counter
        UserDeviceService.incrementCounter("numSessions")
    }

    /// Records the end of the session and writes duration to Firestore.
    func end(reasonCrash: Bool = false) {
        guard let sid = currentSessionId, let start = sessionStart else { return }
        let end = Date()
        let durationSec = Int(end.timeIntervalSince(start))

        SessionEventManager.shared.endSession(crash: reasonCrash, errorCode: nil)
        sessions.document(sid).setData([
            "endTime": Timestamp(date: end),
            "duration": durationSec
        ], merge: true)

        currentSessionId = nil
        sessionStart = nil
        UserDefaults.standard.removeObject(forKey: "currentSessionId")
    }

    /// Convenience wrapper to log an app-level interaction inside the current session.
    func log(_ action: String, metadata: [String: Any]? = nil) {
        SessionEventManager.shared.logInteraction(kind: action, metadata: metadata)
    }
}


