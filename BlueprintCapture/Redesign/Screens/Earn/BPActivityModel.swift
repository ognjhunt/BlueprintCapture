import Foundation
import Combine
import UserNotifications

// MARK: - BPActivityModel
//
// Honest activity feed for the Notifications screen: a re-presentation of real
// backend capture-history state plus real payout-ledger events. No synthetic
// notifications are ever generated (AGENTS.md: never fabricate state).

struct BPActivityEvent: Identifiable, Equatable {
    let id: String
    let icon: String
    let signal: BPSignal
    let title: String
    let body: String
    let date: Date
}

@MainActor
final class BPActivityModel: ObservableObject {
    enum Phase: Equatable { case idle, loading, loaded, failed }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var events: [BPActivityEvent] = []
    @Published private(set) var notificationsAuthorized: Bool?

    func load() async {
        guard phase != .loading else { return }
        phase = .loading

        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: notificationsAuthorized = true
        case .denied: notificationsAuthorized = false
        default: notificationsAuthorized = nil
        }

        var collected: [BPActivityEvent] = []
        var sawBackend = false

        if let history = try? await APIService.shared.fetchCaptureHistory() {
            sawBackend = true
            collected += history.map(Self.event(for:))
        }
        if let ledger = try? await APIService.shared.fetchPayoutLedger() {
            sawBackend = true
            collected += ledger.map(Self.event(for:))
        }

        events = collected.sorted { $0.date > $1.date }
        phase = sawBackend ? .loaded : .failed
    }

    static func event(for entry: CaptureHistoryEntry) -> BPActivityEvent {
        let status = BPStatusPresentation.entry(for: entry.status)
        let icon: String
        switch entry.status {
        case .approved, .paid: icon = "checkmark.seal"
        case .needsRecapture, .needsFix: icon = "arrow.counterclockwise"
        case .rejected: icon = "xmark.octagon"
        default: icon = "doc.viewfinder"
        }
        return BPActivityEvent(
            id: "capture-\(entry.id.uuidString)",
            icon: icon,
            signal: status.signal,
            title: "\(status.label) — \(entry.targetAddress)",
            body: status.explanation,
            date: entry.capturedAt
        )
    }

    static func event(for entry: PayoutLedgerEntry) -> BPActivityEvent {
        let status = BPStatusPresentation.entry(for: entry.status)
        return BPActivityEvent(
            id: "payout-\(entry.id.uuidString)",
            icon: "creditcard",
            signal: status.signal,
            title: "Payout \(status.label.lowercased()) — \(BPFormat.currency(NSDecimalNumber(decimal: entry.amount).doubleValue))",
            body: entry.description ?? status.explanation,
            date: entry.scheduledFor
        )
    }
}
