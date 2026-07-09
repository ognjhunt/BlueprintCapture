//
//  CrashTelemetryService.swift
//  BlueprintCapture
//
//  Lightweight, dependency-free crash + error telemetry for the capture client
//  (audit finding R051). The capture app was previously observability-dark: it
//  logged errors locally via SessionEventManager but shipped nothing about
//  crashes to an operator-visible sink and used no crash reporter.
//
//  This reuses the app's existing Firebase stack (no new third-party crash SDK):
//    • An uncaught-exception handler and POSIX signal handlers persist a small
//      crash breadcrumb to UserDefaults *synchronously in-handler* (crashes can
//      not reliably do async network from within a dying process).
//    • On the NEXT launch, any pending breadcrumb is shipped to the operator-
//      visible Firestore collection `clientCrashReports`.
//    • SessionEventManager error events are routed (best-effort, non-blocking)
//      to `clientErrorTelemetry`.
//
//  Fail-safe contract: telemetry must NEVER crash the app or block capture. All
//  network is best-effort and no-ops cleanly when Firebase / auth is unavailable.
//

import Foundation
import UIKit
import Darwin
import FirebaseAuth
import FirebaseFirestore

/// Pure, side-effect-free builders for telemetry payloads. Kept free of Firebase
/// and UIKit so they are unit-testable in the hermetic lane (no simulator).
enum CrashTelemetryPayloadBuilder {
    /// Upper bound on retained call-stack frames (keeps the persisted breadcrumb small).
    static let maxCallStackFrames = 30
    /// Upper bound on metadata keys forwarded with an error event.
    static let maxMetadataKeys = 20
    /// Upper bound on a single string value's length (defence against unbounded/PII text).
    static let maxMetadataValueLength = 256

    /// Builds a plist-safe crash breadcrumb (String / Double / [String] only) so it can
    /// be persisted to UserDefaults from within a crash handler and re-read next launch.
    static func crashBreadcrumb(
        kind: String,
        name: String,
        reason: String?,
        callStack: [String],
        appVersion: String,
        buildNumber: String,
        deviceModel: String,
        osVersion: String,
        occurredAt: Date
    ) -> [String: Any] {
        var record: [String: Any] = [
            "kind": kind,
            "name": name,
            "appVersion": appVersion,
            "buildNumber": buildNumber,
            "deviceModel": deviceModel,
            "osVersion": osVersion,
            "occurredAtEpoch": occurredAt.timeIntervalSince1970
        ]
        if let reason = reason, !reason.isEmpty {
            record["reason"] = String(reason.prefix(maxMetadataValueLength))
        }
        if !callStack.isEmpty {
            record["callStack"] = Array(callStack.prefix(maxCallStackFrames))
        }
        return record
    }

    /// Keeps only bounded scalar metadata (String / Bool / Int / Double). Raw capture
    /// bytes (`Data`), nested containers, and any other non-scalar values are dropped so
    /// no PII or raw capture content leaves the device.
    static func sanitizedMetadata(_ metadata: [String: Any]?) -> [String: Any] {
        guard let metadata = metadata else { return [:] }
        var result: [String: Any] = [:]
        for key in metadata.keys.sorted() {
            if result.count >= maxMetadataKeys { break }
            let value = metadata[key]
            if let stringValue = value as? String {
                result[key] = String(stringValue.prefix(maxMetadataValueLength))
            } else if let boolValue = value as? Bool {
                result[key] = boolValue
            } else if let intValue = value as? Int {
                result[key] = intValue
            } else if let doubleValue = value as? Double {
                result[key] = doubleValue
            }
            // Data, nested dictionaries/arrays, and other non-scalars are intentionally
            // dropped: they can carry raw capture bytes or unbounded/PII payloads.
        }
        return result
    }

    /// Builds an error-telemetry breadcrumb: an errorCode plus sanitized metadata and
    /// the standard app/device envelope. No PII / raw capture content is included.
    static func errorBreadcrumb(
        errorCode: String,
        metadata: [String: Any]?,
        appVersion: String,
        buildNumber: String,
        deviceModel: String,
        osVersion: String,
        occurredAt: Date
    ) -> [String: Any] {
        var record: [String: Any] = [
            "errorCode": String(errorCode.prefix(maxMetadataValueLength)),
            "appVersion": appVersion,
            "buildNumber": buildNumber,
            "deviceModel": deviceModel,
            "osVersion": osVersion,
            "occurredAtEpoch": occurredAt.timeIntervalSince1970
        ]
        let cleaned = sanitizedMetadata(metadata)
        if !cleaned.isEmpty {
            record["metadata"] = cleaned
        }
        return record
    }
}

final class CrashTelemetryService {
    static let shared = CrashTelemetryService()
    private init() {}

    /// UserDefaults key holding the queue of crash breadcrumbs persisted in-handler.
    static let pendingCrashesKey = "com.blueprint.pendingCrashReports"
    /// Hard cap on the persisted queue so a crash loop cannot grow storage without bound.
    private static let maxPendingCrashes = 20

    // Mirror the proven Firestore-write idiom from SessionEventManager / AppSessionService:
    //   private let db = Firestore.firestore()
    //   private var <name>: CollectionReference { db.collection("<name>") }
    private let db = Firestore.firestore()
    private var crashReports: CollectionReference { db.collection("clientCrashReports") }
    private var errorTelemetry: CollectionReference { db.collection("clientErrorTelemetry") }

    // Device / app metadata is cached at install() time so the crash handlers — which run
    // in a fragile, async-signal-unsafe context — only read primitives, never touch the
    // Bundle/UIDevice machinery while the process is dying.
    fileprivate static var cachedAppVersion = "unknown"
    fileprivate static var cachedBuildNumber = "unknown"
    fileprivate static var cachedDeviceModel = "unknown"
    fileprivate static var cachedOSVersion = "unknown"

    private static var isInstalled = false
    private let signalsToTrap: [Int32] = [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGTRAP]

    // MARK: - Install (call once at app launch, after FirebaseApp.configure())

    /// Installs the uncaught-exception and signal handlers. Idempotent; safe to call once.
    func install() {
        guard !Self.isInstalled else { return }
        Self.isInstalled = true

        // Cache the envelope up front (mirrors the version/model keys used by
        // SessionEventManager and AppSessionService).
        Self.cachedAppVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        Self.cachedBuildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        Self.cachedDeviceModel = UIDevice.current.model
        Self.cachedOSVersion = UIDevice.current.systemVersion

        // Uncaught Objective-C/Swift exceptions. The handler must be a non-capturing
        // @convention(c) function, so it only references global/static symbols.
        let uncaughtHandler: @convention(c) (NSException) -> Void = { exception in
            CrashTelemetryService.persistCrash(
                kind: "uncaughtException",
                name: exception.name.rawValue,
                reason: exception.reason,
                callStack: exception.callStackSymbols
            )
        }
        NSSetUncaughtExceptionHandler(uncaughtHandler)

        // Fatal POSIX signals. After persisting, restore the default disposition and
        // re-raise so the process still terminates exactly as it would have unhandled.
        let signalHandler: @convention(c) (Int32) -> Void = { signalValue in
            CrashTelemetryService.persistCrash(
                kind: "signal",
                name: CrashTelemetryService.signalName(signalValue),
                reason: "signal \(signalValue)",
                callStack: Thread.callStackSymbols
            )
            _ = signal(signalValue, SIG_DFL)
            _ = raise(signalValue)
        }
        for trapped in signalsToTrap {
            _ = signal(trapped, signalHandler)
        }
    }

    // MARK: - In-handler persistence (synchronous, no network)

    /// Persists a crash breadcrumb to UserDefaults. Runs inside the crash handler, so it
    /// does only synchronous, allocation-light work and forces a flush to disk.
    fileprivate static func persistCrash(kind: String, name: String, reason: String?, callStack: [String]) {
        let breadcrumb = CrashTelemetryPayloadBuilder.crashBreadcrumb(
            kind: kind,
            name: name,
            reason: reason,
            callStack: callStack,
            appVersion: cachedAppVersion,
            buildNumber: cachedBuildNumber,
            deviceModel: cachedDeviceModel,
            osVersion: cachedOSVersion,
            occurredAt: Date()
        )
        let defaults = UserDefaults.standard
        var pending = defaults.array(forKey: pendingCrashesKey) as? [[String: Any]] ?? []
        if pending.count >= maxPendingCrashes {
            pending.removeFirst(pending.count - (maxPendingCrashes - 1))
        }
        pending.append(breadcrumb)
        defaults.set(pending, forKey: pendingCrashesKey)
        // Force a write to disk: the process is about to terminate and the default
        // periodic flush may not run in time. synchronize() is deprecated but remains
        // the only synchronous flush available and is appropriate in a crash handler.
        defaults.synchronize()
    }

    /// Human-readable name for the trapped signal.
    fileprivate static func signalName(_ signalValue: Int32) -> String {
        switch signalValue {
        case SIGABRT: return "SIGABRT"
        case SIGILL: return "SIGILL"
        case SIGSEGV: return "SIGSEGV"
        case SIGFPE: return "SIGFPE"
        case SIGBUS: return "SIGBUS"
        case SIGTRAP: return "SIGTRAP"
        default: return "SIG(\(signalValue))"
        }
    }

    // MARK: - Upload next launch

    /// Ships any pending crash breadcrumbs to Firestore, then clears the queue. Best-effort:
    /// no-ops (and keeps the queue for a later launch) if no Firebase identity is available.
    func flushPendingCrashReports() {
        let defaults = UserDefaults.standard
        guard let pending = defaults.array(forKey: Self.pendingCrashesKey) as? [[String: Any]],
              !pending.isEmpty else {
            return
        }
        guard Auth.auth().currentUser != nil else { return }
        let userId = UserDeviceService.resolvedUserId()
        for breadcrumb in pending {
            let doc = Self.firestoreDocument(from: breadcrumb, userId: userId)
            crashReports.addDocument(data: doc)
        }
        defaults.removeObject(forKey: Self.pendingCrashesKey)
    }

    /// Converts a persisted (plist-safe) breadcrumb into a Firestore document, translating
    /// the epoch timestamp into a `Timestamp` and attaching server-side upload metadata.
    static func firestoreDocument(from breadcrumb: [String: Any], userId: String) -> [String: Any] {
        var doc = breadcrumb
        doc.removeValue(forKey: "occurredAtEpoch")
        if let epoch = breadcrumb["occurredAtEpoch"] as? Double {
            doc["occurredAt"] = Timestamp(date: Date(timeIntervalSince1970: epoch))
        } else {
            doc["occurredAt"] = FieldValue.serverTimestamp()
        }
        doc["uploadedAt"] = FieldValue.serverTimestamp()
        doc["platform"] = "ios"
        if !userId.isEmpty {
            doc["userId"] = userId
        }
        return doc
    }

    // MARK: - Error routing (best-effort, non-blocking)

    /// Ships a sanitized error event to the operator-visible sink. Never throws, never
    /// blocks capture; no-ops when no Firebase identity is available.
    func recordError(errorCode: String, metadata: [String: Any]? = nil) {
        guard Auth.auth().currentUser != nil else { return }
        let userId = UserDeviceService.resolvedUserId()
        var doc = CrashTelemetryPayloadBuilder.errorBreadcrumb(
            errorCode: errorCode,
            metadata: metadata,
            appVersion: Self.cachedAppVersion,
            buildNumber: Self.cachedBuildNumber,
            deviceModel: Self.cachedDeviceModel,
            osVersion: Self.cachedOSVersion,
            occurredAt: Date()
        )
        doc.removeValue(forKey: "occurredAtEpoch")
        doc["occurredAt"] = FieldValue.serverTimestamp()
        doc["platform"] = "ios"
        if !userId.isEmpty {
            doc["userId"] = userId
        }
        errorTelemetry.addDocument(data: doc)
    }
}
