import Foundation
import UIKit

enum BlueprintNotificationType: String {
    case nearbyJobEntered = "nearby.job_entered"
    case reservedJobEntered = "nearby.reserved_job_entered"
    case reservationReminder = "reservation.expiring_soon"
    case reservationExpired = "reservation.expired"
    case captureApproved = "capture.approved"
    case captureNeedsFix = "capture.needs_fix"
    case captureRejected = "capture.rejected"
    case capturePaid = "capture.paid"
    case payoutInTransit = "payout.in_transit"
    case payoutPaid = "payout.paid"
    case payoutFailed = "payout.failed"
    case accountPayoutActionRequired = "account.payout_action_required"
    case accountPayoutsEnabled = "account.payouts_enabled"
}

enum BlueprintNotificationEntityType: String {
    case job
    case capture
    case payout
    case account
}

struct BlueprintNotificationPayload {
    let notificationId: String
    let type: BlueprintNotificationType
    let entityType: BlueprintNotificationEntityType
    let entityId: String
    let route: String
    let title: String
    let body: String
    let metadata: [String: String]
    let sentAt: String

    var routeURL: URL? { URL(string: route) }

    var userInfo: [String: Any] {
        var info: [String: Any] = [
            "notificationId": notificationId,
            "type": type.rawValue,
            "entityType": entityType.rawValue,
            "entityId": entityId,
            "route": route,
            "title": title,
            "body": body,
            "sentAt": sentAt,
        ]

        for (key, value) in metadata {
            info[key] = value
        }

        return info
    }

    init(
        notificationId: String,
        type: BlueprintNotificationType,
        entityType: BlueprintNotificationEntityType,
        entityId: String,
        route: String,
        title: String,
        body: String,
        metadata: [String: String] = [:],
        sentAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.notificationId = notificationId
        self.type = type
        self.entityType = entityType
        self.entityId = entityId
        self.route = route
        self.title = title
        self.body = body
        self.metadata = metadata
        self.sentAt = sentAt
    }

    init?(userInfo: [AnyHashable: Any]) {
        guard
            let notificationId = userInfo["notificationId"] as? String ?? userInfo["gcm.message_id"] as? String,
            let typeRaw = userInfo["type"] as? String,
            let type = BlueprintNotificationType(rawValue: typeRaw),
            let entityTypeRaw = userInfo["entityType"] as? String,
            let entityType = BlueprintNotificationEntityType(rawValue: entityTypeRaw),
            let entityId = userInfo["entityId"] as? String,
            let route = userInfo["route"] as? String
        else {
            return nil
        }

        self.notificationId = notificationId
        self.type = type
        self.entityType = entityType
        self.entityId = entityId
        self.route = route
        self.title = userInfo["title"] as? String ?? ""
        self.body = userInfo["body"] as? String ?? ""
        self.sentAt = userInfo["sentAt"] as? String ?? ISO8601DateFormatter().string(from: Date())

        var metadata: [String: String] = [:]
        for (rawKey, rawValue) in userInfo {
            guard let key = rawKey as? String else { continue }
            switch key {
            case "notificationId", "type", "entityType", "entityId", "route", "title", "body", "sentAt", "aps", "gcm.message_id":
                continue
            default:
                if let stringValue = rawValue as? String {
                    metadata[key] = stringValue
                } else if let number = rawValue as? NSNumber {
                    metadata[key] = number.stringValue
                }
            }
        }
        self.metadata = metadata
    }
}

enum BlueprintRoute: Equatable {
    case scanJob(jobId: String)
    case walletCapture(captureId: UUID)
    case walletPayout(ledgerEntryId: UUID)
    case walletPayoutSetup

    init?(url: URL) {
        guard url.scheme?.lowercased() == "blueprint" else { return nil }
        let host = url.host?.lowercased()
        let parts = url.pathComponents.filter { $0 != "/" }

        if host == "scan", parts.count == 2, parts[0] == "jobs" {
            self = .scanJob(jobId: parts[1])
        } else if host == "wallet", parts.count == 2, parts[0] == "captures" {
            guard let captureId = UUID(uuidString: parts[1]) else { return nil }
            self = .walletCapture(captureId: captureId)
        } else if host == "wallet", parts.count == 2, parts[0] == "payouts" {
            guard let ledgerId = UUID(uuidString: parts[1]) else { return nil }
            self = .walletPayout(ledgerEntryId: ledgerId)
        } else if host == "wallet", parts == ["payout-setup"] {
            self = .walletPayoutSetup
        } else {
            return nil
        }
    }

    var url: URL {
        switch self {
        case .scanJob(let jobId):
            return URL(string: "blueprint://scan/jobs/\(jobId)")!
        case .walletCapture(let captureId):
            return URL(string: "blueprint://wallet/captures/\(captureId.uuidString.lowercased())")!
        case .walletPayout(let ledgerEntryId):
            return URL(string: "blueprint://wallet/payouts/\(ledgerEntryId.uuidString.lowercased())")!
        case .walletPayoutSetup:
            return URL(string: "blueprint://wallet/payout-setup")!
        }
    }
}

@MainActor
final class NotificationRouter {
    static let shared = NotificationRouter()

    private init() {}

    func handle(url: URL) {
        guard let route = BlueprintRoute(url: url) else { return }
        emit(route: route, payload: nil)
    }

    func handle(userInfo: [AnyHashable: Any], persistIfNeeded: Bool) {
        guard let payload = BlueprintNotificationPayload(userInfo: userInfo),
              let routeURL = payload.routeURL,
              let route = BlueprintRoute(url: routeURL) else {
            return
        }

        if persistIfNeeded {
            UserDefaults.standard.set(routeURL.absoluteString, forKey: AppConfig.pendingNotificationRouteKey)
        }

        emit(route: route, payload: payload)
    }

    func consumePendingRouteIfNeeded() {
        guard let routeString = UserDefaults.standard.string(forKey: AppConfig.pendingNotificationRouteKey),
              let url = URL(string: routeString) else { return }
        UserDefaults.standard.removeObject(forKey: AppConfig.pendingNotificationRouteKey)
        handle(url: url)
    }

    private func emit(route: BlueprintRoute, payload: BlueprintNotificationPayload?) {
        switch route {
        case .scanJob(let jobId):
            NotificationCenter.default.post(name: .blueprintOpenTab, object: nil, userInfo: ["tab": "scan"])
            NotificationCenter.default.post(name: .blueprintOpenScanJobDetail, object: nil, userInfo: [
                "jobId": jobId,
                "payload": payload as Any
            ])
        case .walletCapture(let captureId):
            NotificationCenter.default.post(name: .blueprintOpenTab, object: nil, userInfo: ["tab": "wallet"])
            NotificationCenter.default.post(name: .blueprintOpenCaptureDetail, object: nil, userInfo: [
                "captureId": captureId.uuidString.lowercased(),
                "payload": payload as Any
            ])
        case .walletPayout(let ledgerEntryId):
            NotificationCenter.default.post(name: .blueprintOpenTab, object: nil, userInfo: ["tab": "wallet"])
            NotificationCenter.default.post(name: .blueprintOpenPayoutEntry, object: nil, userInfo: [
                "ledgerEntryId": ledgerEntryId.uuidString.lowercased(),
                "payload": payload as Any
            ])
        case .walletPayoutSetup:
            NotificationCenter.default.post(name: .blueprintOpenTab, object: nil, userInfo: ["tab": "wallet"])
            NotificationCenter.default.post(name: .blueprintOpenPayoutSetup, object: nil, userInfo: [
                "payload": payload as Any
            ])
        }
    }
}
