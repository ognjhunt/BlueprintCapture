import Foundation

struct SkuPricing: Codable, Equatable {
    let baseUsd: Int
    let rangeUsd: ClosedRange<Int>

    enum CodingKeys: String, CodingKey {
        case baseUsd
        case rangeUsd
    }
}

// Codable support for ClosedRange<Int> as [min, max]
extension ClosedRange: Codable where Bound == Int {
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let lower = try container.decode(Int.self)
        let upper = try container.decode(Int.self)
        self = lower...upper
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(lowerBound)
        try container.encode(upperBound)
    }
}

// Pricing tiers updated for $50/hr average payout target
// Based on estimated walkthrough times (TWO complete passes):
// - SKU C (Small retail): ~45 min (0.75 hr) → $37.50
// - SKU A (Medium grocery): ~90 min (1.5 hr) → $75
// - SKU B (Large warehouse): ~120 min (2 hr) → $100
let defaultPricing: [SKU: SkuPricing] = [
    .A: .init(baseUsd: 150,  rangeUsd: 100...250),
    .B: .init(baseUsd: 200,  rangeUsd: 150...400),
    .C: .init(baseUsd: 75,   rangeUsd: 50...150)
]

func estimatedPayout(for target: Target, pricing: [SKU: SkuPricing]) -> Int {
    // Payout is based on estimated scan time at $50/hour
    // This ensures fair compensation regardless of property size
    let timeMinutes = estimatedScanTimeMinutes(for: target)
    let hours = Double(timeMinutes) / 60.0
    let payout = Int(hours * 50.0)
    return payout
}

/// Estimates scan time in minutes based on square footage
/// Formula derived from empirical capture times:
/// - 5K sqft ≈ 45 min
/// - 10K sqft ≈ 90 min
/// - 20K+ sqft ≈ 120+ min
func estimatedScanTimeMinutes(for target: Target) -> Int {
    guard let sizeSqFt = target.sizeSqFt, sizeSqFt > 0 else {
        // Default to medium estimate if size unknown
        return 75
    }
    // Linear approximation: ~1 minute per 110 sqft (two-pass coverage)
    let estimated = Int(Double(sizeSqFt) / 110.0)
    // Bounds: minimum 30 min, maximum 180 min
    return max(30, min(180, estimated))
}

/// Formats minutes into a readable duration string
/// e.g., "45 min", "1h 15m"
func formatDuration(_ minutes: Int) -> String {
    if minutes < 60 {
        return "\(minutes) min"
    } else {
        let hours = minutes / 60
        let mins = minutes % 60
        return mins > 0 ? "\(hours)h \(mins)m" : "\(hours)h"
    }
}


