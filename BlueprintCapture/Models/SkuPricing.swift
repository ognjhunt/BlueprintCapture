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

let defaultPricing: [SKU: SkuPricing] = [
    .A: .init(baseUsd: 300,   rangeUsd: 120...600),
    .B: .init(baseUsd: 25000, rangeUsd: 15000...60000),
    .C: .init(baseUsd: 180,   rangeUsd: 60...400)
]

func estimatedPayout(for target: Target, pricing: [SKU: SkuPricing]) -> Int {
    guard let p = pricing[target.sku] else { return 0 }
    var value = p.baseUsd
    // Future multipliers hook (size/category based)
    // if let size = target.sizeSqFt { value = Int(Double(value) * min(1.5, max(0.8, Double(size) / 20000.0))) }
    // if target.category == "Flagship Retail" { value = Int(Double(value) * 1.25) }
    return value
}


