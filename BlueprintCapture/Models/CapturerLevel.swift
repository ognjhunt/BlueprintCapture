import Foundation

enum CapturerLevel: String, Codable, CaseIterable {
    case novice
    case verified
    case expert
    case master

    var displayName: String {
        rawValue.capitalized
    }

    var icon: String {
        switch self {
        case .novice: return "star"
        case .verified: return "star.fill"
        case .expert: return "star.circle.fill"
        case .master: return "crown.fill"
        }
    }

    var requiredCaptures: Int {
        switch self {
        case .novice: return 0
        case .verified: return 10
        case .expert: return 50
        case .master: return 200
        }
    }

    var requiredAvgQuality: Double {
        switch self {
        case .novice: return 0
        case .verified: return 80
        case .expert: return 90
        case .master: return 95
        }
    }

    var benefits: [String] {
        switch self {
        case .novice:
            return ["Access to all public capture tasks"]
        case .verified:
            return ["Priority access to high-payout tasks", "+5% base rate bonus"]
        case .expert:
            return ["Priority access to high-payout tasks", "+15% base rate bonus", "Exclusive enterprise captures"]
        case .master:
            return ["Top-tier payout rates", "+25% base rate bonus", "Exclusive enterprise captures", "Featured on leaderboard"]
        }
    }

    /// The next level, or nil if already at max.
    var nextLevel: CapturerLevel? {
        switch self {
        case .novice: return .verified
        case .verified: return .expert
        case .expert: return .master
        case .master: return nil
        }
    }

    /// Compute the current level from capture stats.
    static func from(captureCount: Int, avgQuality: Double) -> CapturerLevel {
        if captureCount >= CapturerLevel.master.requiredCaptures && avgQuality >= CapturerLevel.master.requiredAvgQuality {
            return .master
        }
        if captureCount >= CapturerLevel.expert.requiredCaptures && avgQuality >= CapturerLevel.expert.requiredAvgQuality {
            return .expert
        }
        if captureCount >= CapturerLevel.verified.requiredCaptures && avgQuality >= CapturerLevel.verified.requiredAvgQuality {
            return .verified
        }
        return .novice
    }

    /// Progress to the next level as a 0.0–1.0 fraction. Returns 1.0 if at max level.
    static func progressToNext(captureCount: Int, avgQuality: Double) -> Double {
        let current = from(captureCount: captureCount, avgQuality: avgQuality)
        guard let next = current.nextLevel else { return 1.0 }

        let captureProgress = Double(captureCount - current.requiredCaptures) /
            Double(max(1, next.requiredCaptures - current.requiredCaptures))
        let qualityProgress = (avgQuality - current.requiredAvgQuality) /
            max(1, next.requiredAvgQuality - current.requiredAvgQuality)

        // Average of capture count and quality progress, clamped to 0–1
        return min(1.0, max(0.0, (captureProgress + qualityProgress) / 2.0))
    }
}
