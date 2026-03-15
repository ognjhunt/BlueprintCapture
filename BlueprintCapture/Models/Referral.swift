import Foundation

enum ReferralStatus: String, Codable {
    case invited
    case signedUp
    case firstCapture
    case active
}

struct Referral: Codable, Identifiable {
    let id: String
    let referredUserId: String
    let referredUserName: String
    let referredAt: Date
    let status: ReferralStatus
    let lifetimeEarningsCents: Int

    var lifetimeEarnings: Decimal {
        Decimal(lifetimeEarningsCents) / 100
    }

    var statusLabel: String {
        switch status {
        case .invited: return "Invited"
        case .signedUp: return "Signed Up"
        case .firstCapture: return "First Capture"
        case .active: return "Active"
        }
    }
}

struct ReferralStats {
    let invitesSent: Int
    let signUps: Int
    let activeCapturers: Int
    let lifetimeEarningsCents: Int

    var lifetimeEarnings: Decimal {
        Decimal(lifetimeEarningsCents) / 100
    }

    static let empty = ReferralStats(invitesSent: 0, signUps: 0, activeCapturers: 0, lifetimeEarningsCents: 0)
}
