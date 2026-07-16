import Foundation
import FirebaseAuth
import FirebaseFirestore
import UIKit
#if canImport(FirebaseAnalytics)
import FirebaseAnalytics
#endif
#if canImport(FirebaseCrashlytics)
import FirebaseCrashlytics
#endif

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
    private var remoteWritesEnabled: Bool = false
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
        remoteWritesEnabled = Auth.auth().currentUser != nil

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

        if remoteWritesEnabled {
            eventsCollection.document(sessionId).setData(doc)
        }
        CaptureCrashTelemetryService.shared.recordBreadcrumb(
            name: "app_session_start",
            status: "started",
            metadata: ["network_context": networkContext]
        )
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
        guard remoteWritesEnabled else { return }
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
        guard remoteWritesEnabled else { return }
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
        CaptureCrashTelemetryService.shared.recordBreadcrumb(
            name: "app_session_end",
            status: crash ? "crash" : "ended",
            metadata: errorCode.map { ["error_code": $0] } ?? [:]
        )

        // Determine returned (bool) by checking user doc once
        var returnedValue: Bool = false
        guard remoteWritesEnabled else {
            currentSessionId = nil
            sessionStartTime = nil
            interactionCount = 0
            currentReferralBlueprintId = nil
            currentNetworkContext = nil
            currentNetworkSpeed = nil
            return
        }

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
        CaptureCrashTelemetryService.shared.recordErrorCode(errorCode, metadata: metadata)
        guard let sessionId = currentSessionId else { return }
        guard remoteWritesEnabled else { return }
        var doc = baseEventPayload(sessionId: sessionId, eventType: "error")
        doc["errorCode"] = errorCode
        if let metadata = metadata {
            doc["metadata"] = metadata
        }
        eventsCollection.addDocument(data: doc)
        logAnalyticsEvent(
            name: "blueprint_ops_error",
            operation: errorCode,
            status: "failure",
            metadata: metadata
        )
    }

    func logOperationalEvent(operation: String, status: String, metadata: [String: Any]? = nil) {
        CaptureCrashTelemetryService.shared.recordOperationalBreadcrumb(
            operation: operation,
            status: status,
            metadata: metadata
        )
        guard let sessionId = currentSessionId else {
            logAnalyticsEvent(name: "blueprint_ops_event", operation: operation, status: status, metadata: metadata)
            return
        }
        guard remoteWritesEnabled else {
            logAnalyticsEvent(name: "blueprint_ops_event", operation: operation, status: status, metadata: metadata)
            return
        }

        var doc = baseEventPayload(sessionId: sessionId, eventType: "operational")
        doc["operation"] = operation
        doc["status"] = status
        if let metadata {
            doc["metadata"] = metadata
        }
        eventsCollection.addDocument(data: doc)
        logAnalyticsEvent(name: "blueprint_ops_event", operation: operation, status: status, metadata: metadata)
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

    private func logAnalyticsEvent(name: String, operation: String, status: String, metadata: [String: Any]?) {
        #if canImport(FirebaseAnalytics)
        var parameters: [String: Any] = [
            "operation": analyticsSafeValue(operation),
            "status": analyticsSafeValue(status),
        ]
        if let detail = analyticsDetail(from: metadata) {
            parameters["detail"] = detail
        }
        Analytics.logEvent(name, parameters: parameters)
        #endif
    }

    private func analyticsSafeValue(_ raw: String) -> String {
        String(raw.prefix(100))
    }

    private func analyticsDetail(from metadata: [String: Any]?) -> String? {
        guard let metadata else { return nil }
        if let reason = metadata["reason"] as? String, !reason.isEmpty {
            return analyticsSafeValue(reason)
        }
        if let operation = metadata["operation"] as? String, !operation.isEmpty {
            return analyticsSafeValue(operation)
        }
        if let message = metadata["message"] as? String, !message.isEmpty {
            return analyticsSafeValue(message)
        }
        return nil
    }
}

struct CaptureTelemetryBreadcrumb: Codable, Equatable, Sendable {
    let name: String
    let status: String
    let occurredAt: String
    let metadata: [String: String]

    enum CodingKeys: String, CodingKey {
        case name
        case status
        case occurredAt = "occurred_at"
        case metadata
    }
}

struct CaptureClientTelemetrySubmission: Codable, Equatable, Sendable {
    let eventId: String
    let eventType: String
    let severity: String
    let operation: String
    let status: String
    let occurredAt: String
    let sessionId: String?
    let captureId: String?
    let appVersion: String
    let appBuild: String
    let osVersion: String
    let deviceModel: String
    let metadata: [String: String]
    let breadcrumbs: [CaptureTelemetryBreadcrumb]

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case eventType = "event_type"
        case severity
        case operation
        case status
        case occurredAt = "occurred_at"
        case sessionId = "session_id"
        case captureId = "capture_id"
        case appVersion = "app_version"
        case appBuild = "app_build"
        case osVersion = "os_version"
        case deviceModel = "device_model"
        case metadata
        case breadcrumbs
    }

}

struct CapturePendingCrashReport: Codable, Equatable, Sendable {
    let id: String
    let name: String
    let reason: String
    let occurredAt: String
    let appVersion: String
    let appBuild: String
    let osVersion: String
    let deviceModel: String
    let callStackSymbols: [String]
    let breadcrumbs: [CaptureTelemetryBreadcrumb]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case reason
        case occurredAt = "occurred_at"
        case appVersion = "app_version"
        case appBuild = "app_build"
        case osVersion = "os_version"
        case deviceModel = "device_model"
        case callStackSymbols = "call_stack_symbols"
        case breadcrumbs
    }
}

final class CaptureCrashTelemetryService {
    static let shared = CaptureCrashTelemetryService()

    private static let pendingCrashKey = "blueprint.capture.pending_crash_report"
    private static let breadcrumbsKey = "blueprint.capture.telemetry_breadcrumbs"
    private static let maxBreadcrumbs = 24
    private static let maxMetadataPairs = 20
    private static let maxMetadataValueLength = 240

    private let lock = NSLock()
    private var isConfigured = false
    private var breadcrumbs: [CaptureTelemetryBreadcrumb] = []

    private init() {
        breadcrumbs = Self.loadBreadcrumbs()
    }

    func configure() {
        lock.lock()
        let shouldConfigure = !isConfigured
        if shouldConfigure {
            isConfigured = true
        }
        lock.unlock()
        guard shouldConfigure else { return }

        NSSetUncaughtExceptionHandler { exception in
            CaptureCrashTelemetryService.cacheUncaughtException(
                name: exception.name.rawValue,
                reason: exception.reason,
                callStackSymbols: exception.callStackSymbols
            )
        }

        flushPendingCrashReport()
        recordBreadcrumb(
            name: "client_telemetry_configured",
            status: Self.crashlyticsLinked ? "crashlytics_linked" : "crashlytics_not_linked",
            metadata: ["transport": "firebase_crashlytics_backend_route"]
        )
    }

    func recordBreadcrumb(name: String, status: String, metadata: [String: Any]? = nil) {
        let breadcrumb = CaptureTelemetryBreadcrumb(
            name: Self.safeIdentifier(name),
            status: Self.safeIdentifier(status),
            occurredAt: Self.isoString(from: Date()),
            metadata: Self.sanitizedMetadata(metadata)
        )
        lock.lock()
        breadcrumbs.append(breadcrumb)
        if breadcrumbs.count > Self.maxBreadcrumbs {
            breadcrumbs.removeFirst(breadcrumbs.count - Self.maxBreadcrumbs)
        }
        let snapshot = breadcrumbs
        lock.unlock()
        Self.persistBreadcrumbs(snapshot)

        #if canImport(FirebaseCrashlytics)
        Crashlytics.crashlytics().log("\(breadcrumb.name):\(breadcrumb.status)")
        #endif
    }

    func recordOperationalBreadcrumb(operation: String, status: String, metadata: [String: Any]? = nil) {
        recordBreadcrumb(name: operation, status: status, metadata: metadata)
        guard Self.isFailureStatus(status) else { return }
        emitTelemetryEvent(
            eventType: "operational_failure",
            severity: status.lowercased().contains("critical") ? "critical" : "warning",
            operation: operation,
            status: status,
            metadata: metadata
        )
    }

    func recordErrorCode(_ errorCode: String, metadata: [String: Any]? = nil) {
        recordBreadcrumb(name: "error_\(errorCode)", status: "failure", metadata: metadata)
        emitTelemetryEvent(
            eventType: "nonfatal_error",
            severity: "warning",
            operation: errorCode,
            status: "failure",
            metadata: metadata
        )
    }

    private func flushPendingCrashReport() {
        guard let report = Self.consumePendingCrashReport() else { return }
        let metadata: [String: Any] = [
            "uncaught_exception_name": report.name,
            "reason": report.reason,
            "pending_crash_id": report.id,
            "cached_at_launch": "true",
            "call_stack_top": report.callStackSymbols.first ?? ""
        ]
        emitTelemetryEvent(
            eventType: "cached_uncaught_exception",
            severity: "critical",
            operation: report.name,
            status: "flushed_after_launch",
            metadata: metadata,
            breadcrumbsOverride: report.breadcrumbs,
            deviceOverride: report.deviceModel,
            osVersionOverride: report.osVersion,
            appVersionOverride: report.appVersion,
            appBuildOverride: report.appBuild
        )
    }

    private func emitTelemetryEvent(
        eventType: String,
        severity: String,
        operation: String,
        status: String,
        metadata: [String: Any]?,
        breadcrumbsOverride: [CaptureTelemetryBreadcrumb]? = nil,
        deviceOverride: String? = nil,
        osVersionOverride: String? = nil,
        appVersionOverride: String? = nil,
        appBuildOverride: String? = nil
    ) {
        let payload = makeTelemetrySubmission(
            eventType: eventType,
            severity: severity,
            operation: operation,
            status: status,
            metadata: metadata,
            breadcrumbs: breadcrumbsOverride ?? currentBreadcrumbs(),
            deviceModel: deviceOverride ?? UIDevice.current.model,
            osVersion: osVersionOverride ?? UIDevice.current.systemVersion,
            appVersion: appVersionOverride ?? (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"),
            appBuild: appBuildOverride ?? (Bundle.main.infoDictionary?[kCFBundleVersionKey as String] as? String ?? "unknown")
        )
        writeToCrashlytics(payload)
        forwardToBackendAlerting(payload)
    }

    private func makeTelemetrySubmission(
        eventType: String,
        severity: String,
        operation: String,
        status: String,
        metadata: [String: Any]?,
        breadcrumbs: [CaptureTelemetryBreadcrumb],
        deviceModel: String,
        osVersion: String,
        appVersion: String,
        appBuild: String
    ) -> CaptureClientTelemetrySubmission {
        let sanitizedMetadata = Self.sanitizedMetadata(metadata)
        let sessionId = UserDefaults.standard.string(forKey: "currentSessionId")
        let captureId = sanitizedMetadata["capture_id"]
        return CaptureClientTelemetrySubmission(
            eventId: UUID().uuidString.lowercased(),
            eventType: Self.safeIdentifier(eventType),
            severity: Self.safeIdentifier(severity),
            operation: Self.safeIdentifier(operation),
            status: Self.safeIdentifier(status),
            occurredAt: Self.isoString(from: Date()),
            sessionId: sessionId,
            captureId: captureId,
            appVersion: appVersion,
            appBuild: appBuild,
            osVersion: osVersion,
            deviceModel: deviceModel,
            metadata: sanitizedMetadata,
            breadcrumbs: breadcrumbs
        )
    }

    private func currentBreadcrumbs() -> [CaptureTelemetryBreadcrumb] {
        lock.lock()
        let snapshot = breadcrumbs
        lock.unlock()
        return snapshot
    }

    private func writeToCrashlytics(_ payload: CaptureClientTelemetrySubmission) {
        #if canImport(FirebaseCrashlytics)
        let crashlytics = Crashlytics.crashlytics()
        crashlytics.setCustomValue(payload.eventId, forKey: "blueprint_event_id")
        crashlytics.setCustomValue(payload.eventType, forKey: "blueprint_event_type")
        if let captureId = payload.captureId {
            crashlytics.setCustomValue(captureId, forKey: "blueprint_capture_id")
        }
        if let sessionId = payload.sessionId {
            crashlytics.setCustomValue(sessionId, forKey: "blueprint_session_id")
        }
        let error = NSError(
            domain: "io.tryblueprint.capture.telemetry",
            code: payload.severity == "critical" ? 2 : 1,
            userInfo: [
                NSLocalizedDescriptionKey: "\(payload.eventType): \(payload.operation)",
                "status": payload.status,
                "metadata": payload.metadata.description
            ]
        )
        crashlytics.record(error: error)
        #endif
    }

    // NOTE: There is deliberately no direct client Firestore telemetry sink.
    // firestore.rules default-denies client writes to any telemetry
    // collection, so such writes silently failed and duplicated the
    // authoritative sinks: Crashlytics (baseline) and the WebApp
    // `/v1/creator/client-telemetry` route, which persists server-side to
    // `creatorClientTelemetry` with retention/ownership enforced there.
    private func forwardToBackendAlerting(_ payload: CaptureClientTelemetrySubmission) {
        Task(priority: .utility) {
            do {
                try await APIService.shared.submitClientTelemetry(payload)
            } catch {
                #if canImport(FirebaseCrashlytics)
                Crashlytics.crashlytics().log("client_telemetry_backend_forward_failed")
                #endif
            }
        }
    }

    static func cacheUncaughtException(
        name: String,
        reason: String?,
        callStackSymbols: [String],
        userDefaults: UserDefaults = .standard,
        occurredAt: Date = Date()
    ) {
        let report = CapturePendingCrashReport(
            id: UUID().uuidString.lowercased(),
            name: safeIdentifier(name),
            reason: String((reason ?? "unknown").prefix(maxMetadataValueLength)),
            occurredAt: isoString(from: occurredAt),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            appBuild: Bundle.main.infoDictionary?[kCFBundleVersionKey as String] as? String ?? "unknown",
            osVersion: UIDevice.current.systemVersion,
            deviceModel: UIDevice.current.model,
            callStackSymbols: callStackSymbols.prefix(12).map { String($0.prefix(maxMetadataValueLength)) },
            breadcrumbs: loadBreadcrumbs(userDefaults: userDefaults)
        )
        if let data = try? JSONEncoder().encode(report) {
            userDefaults.set(data, forKey: pendingCrashKey)
        }
    }

    static func sanitizedMetadata(_ metadata: [String: Any]?) -> [String: String] {
        guard let metadata else { return [:] }
        var sanitized: [String: String] = [:]
        for key in metadata.keys.sorted().prefix(maxMetadataPairs) {
            let cleanKey = safeIdentifier(key)
            guard !shouldRedactMetadataKey(cleanKey) else { continue }
            guard let value = metadata[key] else { continue }
            let cleanValue = sanitizedMetadataValue(value, key: cleanKey)
            guard !cleanValue.isEmpty else { continue }
            sanitized[cleanKey] = cleanValue
        }
        return sanitized
    }

    static var crashlyticsLinked: Bool {
        #if canImport(FirebaseCrashlytics)
        return true
        #else
        return false
        #endif
    }

    private static func consumePendingCrashReport(userDefaults: UserDefaults = .standard) -> CapturePendingCrashReport? {
        guard let data = userDefaults.data(forKey: pendingCrashKey),
              let report = try? JSONDecoder().decode(CapturePendingCrashReport.self, from: data) else {
            return nil
        }
        userDefaults.removeObject(forKey: pendingCrashKey)
        return report
    }

    private static func loadBreadcrumbs(userDefaults: UserDefaults = .standard) -> [CaptureTelemetryBreadcrumb] {
        guard let data = userDefaults.data(forKey: breadcrumbsKey),
              let breadcrumbs = try? JSONDecoder().decode([CaptureTelemetryBreadcrumb].self, from: data) else {
            return []
        }
        return Array(breadcrumbs.suffix(maxBreadcrumbs))
    }

    private static func persistBreadcrumbs(_ breadcrumbs: [CaptureTelemetryBreadcrumb], userDefaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(Array(breadcrumbs.suffix(maxBreadcrumbs))) {
            userDefaults.set(data, forKey: breadcrumbsKey)
        }
    }

    private static func shouldRedactMetadataKey(_ key: String) -> Bool {
        let lower = key.lowercased()
        if lower.contains("token") || lower.contains("authorization") || lower.contains("password") || lower.contains("secret") || lower.contains("credential") {
            return true
        }
        if lower == "email" || lower.hasSuffix("_email") || lower.contains("phone") {
            return true
        }
        if lower == "lat" || lower == "lng" || lower.contains("address") || lower.contains("location") {
            return true
        }
        return false
    }

    private static func sanitizedMetadataValue(_ value: Any, key: String) -> String {
        let raw: String
        switch value {
        case let bool as Bool:
            raw = bool ? "true" : "false"
        case let string as String:
            raw = string
        case let number as NSNumber:
            raw = number.stringValue
        default:
            raw = String(describing: value)
        }
        if key.lowercased().contains("path") {
            return String(URL(fileURLWithPath: raw).lastPathComponent.prefix(maxMetadataValueLength))
        }
        return String(raw.prefix(maxMetadataValueLength))
    }

    private static func safeIdentifier(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.isEmpty ? "unknown" : trimmed
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._:-")
        let scalars = normalized.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        return String(String(scalars).prefix(120))
    }

    private static func isFailureStatus(_ status: String) -> Bool {
        let normalized = status.lowercased()
        return normalized.contains("fail")
            || normalized.contains("error")
            || normalized.contains("expired")
            || normalized.contains("blocked")
            || normalized.contains("crash")
    }

    private static func isoString(from date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
